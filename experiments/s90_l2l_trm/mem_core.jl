# S90 Part 1: L2L-TRM r7 memory-type core ([memory] contract) and unit / mock-balance fixture gates.
# Spec: discussion/specs/L2L-TRM-draft-memory-type.md (r7), discussion/specs/S90-draft-l2l-trm-memory-type.md (r2).
# Gates here: G7 (frozen90), GM1, GM2 unit (R-MID / pi_u4 binary32 boundaries), GM4 (a)-(h), GM5.
# Arithmetic: no @fastmath / fma / muladd anywhere (checked on LLVM IR in GM2/GM4).
# Run: julia --project=. -e 'include("experiments/s90_l2l_trm/mem_core.jl"); S90MemCore.self_test()'
module S90MemCore

using SHA
using InteractiveUtils: code_llvm

export MemoryConfig, MemSlot, MemoryState, InvalidResourceError, MemoryConfigError
export load_memory_config, serialize_memory, deserialize_memory, state_hash, check_invariants
export OPS_CTX_KEY, OPS_MEM_READ_WORST, OPS_MEM_WRITE_WORST, OPS_MEM_SETTLE_WORST, OPS_MEM_MANDATORY
export two_sum, add_down, add_up, sub_down, sub_up, two_prod_no_fma, div_down, port_arg
export read_memory_pair, read_memory_pair_key, pi_u4, r_mid, write_memory_candidate!, settle_upkeep!, memory_step!
export frozen90, check_gradual_underflow, self_test

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))

# ---------------------------------------------------------------- G7: frozen hashes (experiments/freeze-s90.txt)
const FROZEN90 = [
    ("experiments/s90_l2l_trm/predictions.toml", "088c43e08d5ea6ad683343d6cc3cd6fb1efd09b033e2c7f0125206e76c6903e2"),
    ("discussion/specs/S90-draft-l2l-trm-memory-type.md", "202fb050525ff98eab5b17f4262ef44b773679fc838285df8322ea3f0969a7b6"),
    ("discussion/specs/L2L-TRM-draft-memory-type.md", "85b29668e69a7d9dcb5d0ea0dfacb4689f69157e4b6f2a4ad6c59e589b2e8196"),
]

function frozen90()
    lines = filter(!isempty, strip.(readlines(joinpath(ROOT, "experiments", "freeze-s90.txt"))))
    rec = Dict{String,String}()
    for l in lines
        h, p = split(l; limit = 2)
        rec[strip(p)] = h
    end
    length(rec) == length(FROZEN90) || error("frozen90: freeze-s90.txt has $(length(rec)) entries, expected $(length(FROZEN90))")
    for (p, h) in FROZEN90
        get(rec, p, "") == h || error("frozen90: freeze-s90.txt entry for $p does not match the code constant")
        act = bytes2hex(open(sha256, joinpath(ROOT, p)))
        act == h || error("frozen90: SHA-256 of $p is $act, frozen $h")
    end
    return true
end

# ---------------------------------------------------------------- errors
struct InvalidResourceError <: Exception
    msg::String
end
struct MemoryConfigError <: Exception
    msg::String
end
Base.showerror(io::IO, e::InvalidResourceError) = print(io, "InvalidResourceError: ", e.msg)
Base.showerror(io::IO, e::MemoryConfigError) = print(io, "MemoryConfigError: ", e.msg)

# ---------------------------------------------------------------- operation bounds (r7 §1.1.4)
const OPS_CTX_KEY = 16
OPS_MEM_READ_WORST(C::Integer) = C == 0 ? 0 : 8 * C + 8
OPS_MEM_WRITE_WORST(C::Integer) = C == 0 ? 0 : 8 * C + 16
OPS_MEM_SETTLE_WORST(C::Integer, N_max::Integer) = C == 0 ? 0 : 4 * N_max + 45 + C * (66 * N_max + 31)
OPS_MEM_MANDATORY(C::Integer, N_max::Integer) =
    C == 0 ? 0 : OPS_CTX_KEY + OPS_MEM_READ_WORST(C) + OPS_MEM_SETTLE_WORST(C, N_max)

# ---------------------------------------------------------------- [memory] config and load-time rejection (r7 §1, §2)
const HEADER_BYTES = 8
const SLOT_BYTES = 16
const K_LO = ldexp(1.0, -40)
const K_HI = ldexp(1.0, 40)
const RES_HI = ldexp(1.0, 40)

struct MemoryConfig
    B::Int            # reserved_bytes
    H::Int            # header_bytes (== 8)
    s::Int            # slot_bytes (== 16)
    C::Int            # C_spec = fld(B - H, s)
    K_mem::Float64    # upkeep_rate_per_slot
    N_max::Int        # max_body_cells
    max_read_ops::Int # max_read_ops_per_step
    B_max::Int        # per-step op budget
    ops_trm_min::Int  # OPS_TRM_MIN (S66 §2.2 OPS_FIXED)
end

OPS_MEM_READ_WORST(cfg::MemoryConfig) = OPS_MEM_READ_WORST(cfg.C)
OPS_MEM_WRITE_WORST(cfg::MemoryConfig) = OPS_MEM_WRITE_WORST(cfg.C)
OPS_MEM_SETTLE_WORST(cfg::MemoryConfig) = OPS_MEM_SETTLE_WORST(cfg.C, cfg.N_max)
OPS_MEM_MANDATORY(cfg::MemoryConfig) = OPS_MEM_MANDATORY(cfg.C, cfg.N_max)

# B_max and ops_trm_min are not frozen numbers in r7 / S90 r2; the caller must pass them explicitly.
function load_memory_config(; reserved_bytes::Integer, header_bytes::Integer = HEADER_BYTES, slot_bytes::Integer = SLOT_BYTES,
                            upkeep_rate_per_slot::Real, max_body_cells::Integer, max_read_ops_per_step::Integer,
                            B_max::Integer, ops_trm_min::Integer)
    B = Int(reserved_bytes); H = Int(header_bytes); s = Int(slot_bytes)
    B < H && throw(MemoryConfigError("B < H ($B < $H)"))
    s <= 0 && throw(MemoryConfigError("s <= 0 ($s)"))
    H == HEADER_BYTES || throw(MemoryConfigError("header_bytes must be $HEADER_BYTES (got $H)"))
    s == SLOT_BYTES || throw(MemoryConfigError("slot_bytes must be $SLOT_BYTES (got $s)"))
    C = fld(B - H, s)
    C > typemax(UInt32) && throw(MemoryConfigError("C_spec > typemax(UInt32) ($C)"))
    K = Float64(upkeep_rate_per_slot)
    isfinite(K) || throw(MemoryConfigError("K_mem not finite"))
    (K < K_LO || K > K_HI) && throw(MemoryConfigError("K_mem outside [2^-40, 2^40] ($K)"))
    N = Int(max_body_cells)
    (N < 1 || N > 65536) && throw(MemoryConfigError("max_body_cells outside [1, 65536] ($N)"))
    R = Int(max_read_ops_per_step)
    R < OPS_MEM_READ_WORST(C) && throw(MemoryConfigError("max_read_ops_per_step < OPS_MEM_READ_WORST ($R < $(OPS_MEM_READ_WORST(C)))"))
    Int(B_max) - OPS_MEM_MANDATORY(C, N) < Int(ops_trm_min) &&
        throw(MemoryConfigError("B_max - OPS_MEM_MANDATORY < OPS_TRM_MIN"))
    return MemoryConfig(B, H, s, C, K, N, R, Int(B_max), Int(ops_trm_min))
end

# ---------------------------------------------------------------- memory state (FIFO packed: slots[1] oldest, slots[end] newest)
struct MemSlot
    ctx_key::UInt64
    action::UInt8
    outcome::UInt8
end

mutable struct MemoryState
    slots::Vector{MemSlot}
end
MemoryState() = MemoryState(MemSlot[])
Base.copy(M::MemoryState) = MemoryState(copy(M.slots))

function check_invariants(cfg::MemoryConfig, M::MemoryState)
    cfg.H + cfg.C * cfg.s <= cfg.B || error("invariant: H + C*s > B")
    length(M.slots) <= cfg.C || error("invariant: count > C_spec")
    seen = Set{Tuple{UInt64,UInt8}}()
    for x in M.slots
        x.action in (0x01, 0x02) || error("invariant: action not in {1,2}")
        x.outcome in (0x00, 0x01) || error("invariant: outcome not in {0,1}")
        (x.ctx_key, x.action) in seen && error("invariant: duplicate (k, a)")
        push!(seen, (x.ctx_key, x.action))
    end
    return true
end

# ---------------------------------------------------------------- fixed-length little-endian serialization (r7 §2)
function put_le!(buf::Vector{UInt8}, off::Int, x::Unsigned)
    for i in 0:sizeof(x)-1
        buf[off+i+1] = UInt8((x >> (8i)) & 0xff)
    end
end
function get_le(::Type{T}, buf::Vector{UInt8}, off::Int) where {T<:Unsigned}
    x = zero(T)
    for i in 0:sizeof(T)-1
        x |= T(buf[off+i+1]) << (8i)
    end
    return x
end

function serialize_memory(cfg::MemoryConfig, M::MemoryState)::Vector{UInt8}
    check_invariants(cfg, M)
    buf = zeros(UInt8, cfg.B)
    put_le!(buf, 0, UInt32(length(M.slots)))     # count; pad_h stays 0
    for (i, x) in enumerate(M.slots)
        off = cfg.H + (i - 1) * cfg.s
        put_le!(buf, off, x.ctx_key)
        buf[off+9] = x.action
        buf[off+10] = x.outcome                   # pad_s (6 B) stays 0
    end
    return buf
end

function deserialize_memory(cfg::MemoryConfig, buf::Vector{UInt8})::MemoryState
    length(buf) == cfg.B || error("deserialize: length $(length(buf)) != B $(cfg.B)")
    count = get_le(UInt32, buf, 0)
    get_le(UInt32, buf, 4) == 0 || error("deserialize: pad_h != 0")
    count <= cfg.C || error("deserialize: count $count > C_spec $(cfg.C)")
    slots = MemSlot[]
    for i in 1:cfg.C
        off = cfg.H + (i - 1) * cfg.s
        if i <= count
            all(==(0x00), @view buf[off+11:off+16]) || error("deserialize: pad_s != 0 in slot $i")
            x = MemSlot(get_le(UInt64, buf, off), buf[off+9], buf[off+10])
            x.action in (0x01, 0x02) || error("deserialize: action not in {1,2} in slot $i")
            x.outcome in (0x00, 0x01) || error("deserialize: outcome not in {0,1} in slot $i")
            any(y -> y.ctx_key == x.ctx_key && y.action == x.action, slots) && error("deserialize: duplicate (k, a)")
            push!(slots, x)
        else
            all(==(0x00), @view buf[off+1:off+cfg.s]) || error("deserialize: empty slot $i not zero")
        end
    end
    all(==(0x00), @view buf[cfg.H+cfg.C*cfg.s+1:cfg.B]) || error("deserialize: surplus bytes not zero")
    return MemoryState(slots)
end

state_hash(cfg::MemoryConfig, M::MemoryState) = bytes2hex(sha256(serialize_memory(cfg, M)))

# ---------------------------------------------------------------- directed rounding without FMA (r7 §3.3)
function check_gradual_underflow()
    ldexp(1.0, -1074) != 0.0 || error("gradual underflow: 2^-1074 flushed to zero")
    prevfloat(0.0) < 0.0 || error("gradual underflow: prevfloat(0.0) not < 0")
    nextfloat(0.0) > 0.0 || error("gradual underflow: nextfloat(0.0) not > 0")
    ldexp(1.0, -1022) / 2.0 == ldexp(1.0, -1023) || error("gradual underflow: subnormal division flushed")
    ldexp(3.0, -1074) - ldexp(1.0, -1073) == ldexp(1.0, -1074) || error("gradual underflow: subnormal subtraction flushed")
    get_zero_subnormals() && error("gradual underflow: FTZ/DAZ enabled")
    return true
end

function two_sum(a::Float64, b::Float64)
    x = a + b
    bv = x - a
    av = x - bv
    y = (a - av) + (b - bv)
    return (x, y)
end
function add_down(a::Float64, b::Float64)
    x, y = two_sum(a, b)
    return y < 0.0 ? prevfloat(x) : x
end
function add_up(a::Float64, b::Float64)
    x, y = two_sum(a, b)
    return y > 0.0 ? nextfloat(x) : x
end
sub_down(a::Float64, b::Float64) = add_down(a, -b)
sub_up(a::Float64, b::Float64) = add_up(a, -b)

function two_prod_no_fma(a::Float64, b::Float64)
    p = a * b
    ca = 134217729.0 * a; ah = ca - (ca - a); al = a - ah
    cb = 134217729.0 * b; bh = cb - (cb - b); bl = b - bh
    t1 = ah * bh
    t2 = ah * bl
    t3 = al * bh
    t4 = al * bl
    err = (((t1 - p) + t2) + t3) + t4
    return (p, err)
end

function div_down(K::Float64, N::Int)
    share = K / Float64(N)
    p, err = two_prod_no_fma(share, Float64(N))
    if p > K || (p == K && err > 0.0)
        share = prevfloat(share)
    end
    return share
end

# port increment that never creates matter: port_after - port_old <= paid_lo (r7 §3.3, P6)
function port_arg(port_old::Float64, paid_lo::Float64; use_naive_add::Bool = false)
    target = use_naive_add ? port_old + paid_lo : add_down(port_old, paid_lo)
    return (target, sub_down(target, port_old))
end

# ---------------------------------------------------------------- read / compose / proportional map (r7 §3.1)
r_mid(p_trm::Float32, y::UInt8) = 0.5f0 * (p_trm + Float32(y))

function pi_u4(p1::Float32, p2::Float32)
    denom = p1 + p2
    denom == 0.0f0 && return (0.5f0, 0.5f0)
    q1 = p1 / denom
    q2 = p2 / denom
    m1 = 0.75f0 * q1
    m2 = 0.75f0 * q2
    return (0.125f0 + m1, 0.125f0 + m2)
end

# Read with a precomputed key (C_spec > 0 only). Returns (p1, p2, read_ops, hit1, hit2); read_ops excludes OPS_CTX_KEY.
function read_memory_pair_key(cfg::MemoryConfig, M::MemoryState, k::UInt64, p1_trm::Float32, p2_trm::Float32)
    cfg.C > 0 || error("read_memory_pair_key on C_spec == 0")
    ops = 0
    out = (p1_trm, p2_trm)
    hit = (false, false)
    for a in (0x01, 0x02)
        p = a == 0x01 ? p1_trm : p2_trm
        h = false
        for x in M.slots
            ops += 4
            if x.ctx_key == k && x.action == a
                h && error("read: duplicate (k, a)")
                ops += 4
                p = r_mid(p, x.outcome)
                h = true
            end
        end
        out = a == 0x01 ? (p, out[2]) : (out[1], p)
        hit = a == 0x01 ? (h, hit[2]) : (hit[1], h)
    end
    ops <= OPS_MEM_READ_WORST(cfg) || error("read ops $ops > OPS_MEM_READ_WORST")
    return (out[1], out[2], ops, hit[1], hit[2])
end

# Returns (p1, p2, ops, hit1, hit2); ops includes OPS_CTX_KEY. C_spec == 0 never calls ctx_key_fn and costs exactly 0.
function read_memory_pair(cfg::MemoryConfig, M::MemoryState, ctx_key_fn, p1_trm::Float32, p2_trm::Float32)
    cfg.C == 0 && return (p1_trm, p2_trm, 0, false, false)
    k = UInt64(ctx_key_fn())
    p1, p2, ops, h1, h2 = read_memory_pair_key(cfg, M, k, p1_trm, p2_trm)
    return (p1, p2, OPS_CTX_KEY + ops, h1, h2)
end

# ---------------------------------------------------------------- write candidate: R1 + K-UNIQ-CLEAR + D1 (r7 §3.3.1)
# Mutates the candidate list `M` (callers pass a copy of the committed memory; see memory_step!).
function write_memory_candidate!(cfg::MemoryConfig, M::MemoryState, ctx_key::UInt64, a::UInt8, y::UInt8,
                                 p_pre::Float32, p_trm::Float32; remaining_ops::Int)
    r = (skipped = false, miss = false, cleared = false, replaced = false, appended = false, evicted_d1 = false, ops = 0)
    cfg.C == 0 && return r
    a in (0x01, 0x02) || throw(ArgumentError("action not in {1,2}"))
    y in (0x00, 0x01) || throw(ArgumentError("outcome not in {0,1}"))
    remaining_ops < OPS_MEM_WRITE_WORST(cfg) && return merge(r, (skipped = true,))
    ops = 4
    miss = (y == 0x01 && p_pre < 0.5f0) || (y == 0x00 && p_pre > 0.5f0)
    miss || return merge(r, (ops = ops,))
    idx = 0
    for (i, x) in enumerate(M.slots)
        ops += 4
        if x.ctx_key == ctx_key && x.action == a
            idx = i
            break
        end
    end
    cleared = replaced = appended = evicted = false
    if idx > 0
        ops += 4
        agree = (y == 0x01 && p_trm > 0.5f0) || (y == 0x00 && p_trm < 0.5f0)
        ops += 4 * (length(M.slots) - idx)
        deleteat!(M.slots, idx)
        if agree
            cleared = true
        else
            push!(M.slots, MemSlot(ctx_key, a, y)); ops += 4
            replaced = true
        end
    else
        if length(M.slots) == cfg.C
            ops += 4 * (cfg.C - 1)
            popfirst!(M.slots)
            evicted = true
        end
        push!(M.slots, MemSlot(ctx_key, a, y)); ops += 4
        appended = true
    end
    ops <= OPS_MEM_WRITE_WORST(cfg) || error("write ops $ops > OPS_MEM_WRITE_WORST")
    return (skipped = false, miss = true, cleared = cleared, replaced = replaced, appended = appended, evicted_d1 = evicted, ops = ops)
end

# ---------------------------------------------------------------- prepaid sequential upkeep settlement (r7 §3.3.2)
# Settles the candidate list `cand` (default: M itself) for step s+1 and, on completion, stores the kept tail into M.
# B_vec / port_ref change one slot at a time (slot-unit atomicity); an exception leaves M untouched.
# use_naive_add = true replaces add_down by plain `+` (NC2 hook only; production paths never set it).
function settle_upkeep!(cfg::MemoryConfig, M::MemoryState, B_vec::Vector{Float64}, body_post::Vector{Int},
                        port_ref::Base.RefValue{Float64}; cand::MemoryState = M, use_naive_add::Bool = false)
    nores = (dead = false, purchased = 0, upkeep_evicted = 0, paid_total = 0.0, port_delta = 0.0, ops = 0,
             trace = NamedTuple[])
    cfg.C == 0 && return nores
    isempty(body_post) && return merge(nores, (dead = true,))
    adddn = use_naive_add ? (+) : add_down
    N = length(body_post)
    (1 <= N <= cfg.N_max) || throw(InvalidResourceError("length(body_post) = $N outside [1, N_max = $(cfg.N_max)]"))
    allunique(body_post) || throw(InvalidResourceError("body_post has duplicate cells"))
    for i in body_post
        (1 <= i <= length(B_vec)) || throw(InvalidResourceError("body_post index $i out of range"))
        b = B_vec[i]
        (isfinite(b) && 0.0 <= b <= RES_HI) || throw(InvalidResourceError("cell balance $b outside [0, 2^40]"))
    end
    p0 = port_ref[]
    (isfinite(p0) && 0.0 <= p0 <= RES_HI) || throw(InvalidResourceError("port balance $p0 outside [0, 2^40]"))
    ops = 4 * N + 6
    K = cfg.K_mem
    L = length(cand.slots)
    first_kept = L + 1
    paid_total = 0.0
    trace = NamedTuple[]
    if L > 0
        share = div_down(K, N); ops += 23
        for j in L:-1:1
            tentative_B = B_vec[body_post]; ops += N
            paid_lo = 0.0
            for idx in 1:N
                before = tentative_B[idx]
                m = min(before, share)
                after = sub_up(before, m)
                dec_lo = sub_down(before, after)
                tentative_B[idx] = after
                paid_lo = adddn(paid_lo, dec_lo)
                ops += 25
            end
            pass1 = paid_lo
            for idx in 1:N
                ops += 1
                paid_lo >= K && break
                before = tentative_B[idx]
                ops += 1
                before <= 0.0 && continue
                rem_up = sub_up(K, paid_lo)
                m = min(before, rem_up)
                after = before - m
                dec_lo = sub_down(before, after)
                if dec_lo < m && after > 0.0
                    after = prevfloat(after)
                    dec_lo = sub_down(before, after)
                end
                tentative_B[idx] = after
                paid_lo = adddn(paid_lo, dec_lo)
                ops += 37
            end
            if paid_lo >= K
                port_old = port_ref[]
                target_port, paid_arg = port_arg(port_old, paid_lo; use_naive_add = use_naive_add)
                (isfinite(target_port) && target_port <= RES_HI) ||
                    throw(InvalidResourceError("port would exceed 2^40 at slot $j"))
                B_vec[body_post] .= tentative_B
                port_ref[] = port_old + paid_arg               # port_give! (plain Float64 add)
                first_kept = j
                paid_total += paid_lo
                ops += N + 23
                push!(trace, (j = j, pass1_paid = pass1, paid_lo = paid_lo, purchased = true))
            else
                ops += 1
                push!(trace, (j = j, pass1_paid = pass1, paid_lo = paid_lo, purchased = false))
                break
            end
        end
    end
    kept = cand.slots[first_kept:end]
    ops += 4 * length(kept) + 4 * (cfg.C - length(kept)) + 16
    M.slots = kept
    check_invariants(cfg, M)
    ops <= OPS_MEM_SETTLE_WORST(cfg) || error("settle ops $ops > OPS_MEM_SETTLE_WORST")
    return (dead = false, purchased = length(kept), upkeep_evicted = L - length(kept), paid_total = paid_total,
            port_delta = port_ref[] - p0, ops = ops, trace = trace)
end

# ---------------------------------------------------------------- one step (r7 §3.1 read, §3.3 write + settle)
# a, y: action taken and outcome observed (y is used only after the read). remaining_ops: budget left after TRM.
function memory_step!(cfg::MemoryConfig, M::MemoryState, ctx_key_fn, p1_trm::Float32, p2_trm::Float32, a::UInt8, y::UInt8,
                      B_vec::Vector{Float64}, body_post::Vector{Int}, port_ref::Base.RefValue{Float64};
                      remaining_ops::Int, use_naive_add::Bool = false)
    if cfg.C == 0
        p1, p2 = p1_trm, p2_trm
        return (p1 = p1, p2 = p2, pi = pi_u4(p1, p2), hit = (false, false), read_ops = 0, write = nothing, settle = nothing)
    end
    k = UInt64(ctx_key_fn())
    p1, p2, rops, h1, h2 = read_memory_pair_key(cfg, M, k, p1_trm, p2_trm)
    pis = pi_u4(p1, p2)
    isempty(body_post) && return (p1 = p1, p2 = p2, pi = pis, hit = (h1, h2), read_ops = OPS_CTX_KEY + rops, write = nothing,
                                  settle = settle_upkeep!(cfg, M, B_vec, body_post, port_ref))
    cand = copy(M)
    p_pre = a == 0x01 ? p1 : p2
    p_trm = a == 0x01 ? p1_trm : p2_trm
    w = write_memory_candidate!(cfg, cand, k, a, y, p_pre, p_trm; remaining_ops = remaining_ops)
    st = settle_upkeep!(cfg, M, B_vec, body_post, port_ref; cand = cand, use_naive_add = use_naive_add)
    return (p1 = p1, p2 = p2, pi = pis, hit = (h1, h2), read_ops = OPS_CTX_KEY + rops, write = w, settle = st)
end

# ================================================================ gates
const NCHK = Ref(0)
chk(c::Bool, msg) = (NCHK[] += 1; c || error("FAIL: " * msg); nothing)
function throws(f, T)
    try
        f()
    catch e
        return e isa T
    end
    return false
end
bits(x::Float32) = reinterpret(UInt32, x)
bits(x::Float64) = reinterpret(UInt64, x)
same(a::Float32, b::Float32) = bits(a) == bits(b)
same(a::Float64, b::Float64) = bits(a) == bits(b)

exact_E(before::Vector{Float64}, after::Vector{Float64}) =
    setprecision(BigFloat, 2400) do
        sum(BigFloat.(before) .- BigFloat.(after))
    end
exact_diff(a::Float64, b::Float64) = setprecision(() -> BigFloat(a) - BigFloat(b), BigFloat, 2400)
bigK(x::Float64) = setprecision(() -> BigFloat(x), BigFloat, 2400)

# test configs (B_max / ops_trm_min are synthetic here; S90 r2 does not freeze them)
const T_TRM_MIN = 1000
tcfg(B; K = 0.002, N = 4, R = nothing, Bmax = nothing) = begin
    C = fld(B - 8, 16)
    load_memory_config(reserved_bytes = B, upkeep_rate_per_slot = K, max_body_cells = N,
                       max_read_ops_per_step = R === nothing ? OPS_MEM_READ_WORST(C) : R,
                       B_max = Bmax === nothing ? OPS_MEM_MANDATORY(C, N) + T_TRM_MIN : Bmax, ops_trm_min = T_TRM_MIN)
end
slots(xs...) = MemoryState(MemSlot[MemSlot(UInt64(k), UInt8(a), UInt8(y)) for (k, a, y) in xs])

function no_fma_ir(f, types)
    io = IOBuffer()
    code_llvm(io, f, types; debuginfo = :none)
    ir = String(take!(io))
    return !occursin(r"llvm\.fma|fmuladd|\bcontract\b|\bfast\b|\breassoc\b|\bafn\b", ir)
end

function run_gm1()
    n0 = NCHK[]
    lc(; kw...) = () -> load_memory_config(; merge((reserved_bytes = 24, upkeep_rate_per_slot = 0.002, max_body_cells = 4,
                                                    max_read_ops_per_step = 16, B_max = OPS_MEM_MANDATORY(1, 4) + T_TRM_MIN,
                                                    ops_trm_min = T_TRM_MIN), kw)...)
    # load-time acceptance at the boundaries
    chk(lc()() isa MemoryConfig, "baseline C1 config accepted")
    chk(lc(upkeep_rate_per_slot = ldexp(1.0, -40))().K_mem == ldexp(1.0, -40), "K_mem = 2^-40 accepted")
    chk(lc(upkeep_rate_per_slot = ldexp(1.0, 40))().K_mem == ldexp(1.0, 40), "K_mem = 2^40 accepted")
    chk(lc(max_body_cells = 1, B_max = OPS_MEM_MANDATORY(1, 1) + T_TRM_MIN)().N_max == 1, "N_max = 1 accepted")
    chk(lc(max_body_cells = 65536, B_max = OPS_MEM_MANDATORY(1, 65536) + T_TRM_MIN)().N_max == 65536, "N_max = 65536 accepted")
    for (B, C) in ((8, 0), (9, 0), (23, 0), (24, 1), (40, 2), (2088, 130))
        cfg = tcfg(B)
        chk(cfg.C == C, "C_spec(B=$B) == $C")
    end
    chk(tcfg(8; R = 0, Bmax = T_TRM_MIN).C == 0, "C0 with max_read_ops 0 and B_max = OPS_TRM_MIN accepted")
    # load-time rejection
    E = MemoryConfigError
    chk(throws(lc(reserved_bytes = 7), E), "reject B < H")
    chk(throws(lc(slot_bytes = 0), E), "reject s == 0")
    chk(throws(lc(slot_bytes = -16), E), "reject s < 0")
    chk(throws(lc(header_bytes = 4, reserved_bytes = 24), E), "reject H != 8")
    chk(throws(lc(slot_bytes = 8), E), "reject s != 16")
    chk(throws(lc(reserved_bytes = 8 + 16 * (Int(typemax(UInt32)) + 1)), E), "reject C_spec > typemax(UInt32)")
    for K in (Inf, -Inf, NaN, ldexp(1.0, -41), prevfloat(ldexp(1.0, -40)), nextfloat(ldexp(1.0, 40)), ldexp(1.0, -1074),
              floatmax(Float64), 0.0, -0.002)
        chk(throws(lc(upkeep_rate_per_slot = K), E), "reject K_mem = $K")
    end
    chk(throws(lc(max_body_cells = 0), E), "reject N_max = 0")
    chk(throws(lc(max_body_cells = 65537), E), "reject N_max = 65537")
    chk(throws(lc(max_read_ops_per_step = 15), E), "reject max_read_ops < OPS_MEM_READ_WORST")
    chk(throws(lc(B_max = OPS_MEM_MANDATORY(1, 4) + T_TRM_MIN - 1), E), "reject B_max - MANDATORY < OPS_TRM_MIN")
    chk(throws(() -> tcfg(8; R = 0, Bmax = T_TRM_MIN - 1), E), "reject C0 B_max < OPS_TRM_MIN")

    # runtime rejection (state untouched)
    cfg = tcfg(24; K = 0.25, N = 2)
    for (Bv, body, port, what) in (([1.0, 1.0, 1.0], [1, 2, 3], 0.0, "length(body_post) > N_max"),
                                   ([-1.0, 1.0], [1, 2], 0.0, "negative cell"),
                                   ([NaN, 1.0], [1, 2], 0.0, "NaN cell"),
                                   ([Inf, 1.0], [1, 2], 0.0, "Inf cell"),
                                   ([nextfloat(RES_HI), 1.0], [1, 2], 0.0, "cell > 2^40"),
                                   ([1.0, 1.0], [1, 2], -1.0, "negative port"),
                                   ([1.0, 1.0], [1, 2], NaN, "NaN port"),
                                   ([1.0, 1.0], [1, 2], nextfloat(RES_HI), "port > 2^40"),
                                   ([1.0, 1.0], [1, 1], 0.0, "duplicate body cell"),
                                   ([1.0, 1.0], [1, 3], 0.0, "body index out of range"))
        M = slots((1, 1, 1)); h0 = state_hash(cfg, M); B0 = copy(Bv); pr = Ref(port)
        chk(throws(() -> settle_upkeep!(cfg, M, Bv, body, pr), InvalidResourceError), "runtime reject: $what")
        chk(isequal(Bv, B0) && isequal(pr[], port) && state_hash(cfg, M) == h0, "runtime reject leaves state: $what")
    end
    chk(settle_upkeep!(cfg, slots((1, 1, 1)), [RES_HI, 0.0], [1, 2], Ref(0.0)).purchased == 1, "cell = 2^40 accepted")

    # slot-unit atomicity: single slot
    cfg = tcfg(24; K = 1.0, N = 1)
    M = slots((5, 1, 1)); h0 = state_hash(cfg, M); Bv = [1.0]; pr = Ref(RES_HI)
    chk(throws(() -> settle_upkeep!(cfg, M, Bv, [1], pr), InvalidResourceError), "single-slot port overflow throws")
    chk(Bv == [1.0] && pr[] == RES_HI && state_hash(cfg, M) == h0, "single-slot: B == [1.0], port == 2^40, M unchanged")
    # slot-unit atomicity: two candidate slots, first commits, second throws, M not compacted
    cfg = tcfg(40; K = 1.0, N = 1)
    M = slots((5, 1, 1), (6, 2, 0)); h0 = state_hash(cfg, M); Bv = [2.0]; pr = Ref(RES_HI - 1.0)
    chk(throws(() -> settle_upkeep!(cfg, M, Bv, [1], pr; cand = copy(M)), InvalidResourceError), "two-slot: second slot throws")
    chk(Bv == [1.0] && pr[] == RES_HI, "two-slot: B == [1.0], port == 2^40 after first commit")
    chk(state_hash(cfg, M) == h0, "two-slot: M buffer stays at previous-step state")

    # write skip when remaining ops < OPS_MEM_WRITE_WORST; mandatory settle still completes
    cfg = tcfg(40; K = 0.25, N = 1)
    M = slots((3, 1, 0)); Bv = [1.0]; pr = Ref(0.0)
    r = memory_step!(cfg, M, () -> UInt64(9), 0.9f0, 0.1f0, 0x01, 0x00, Bv, [1], pr; remaining_ops = OPS_MEM_WRITE_WORST(cfg) - 1)
    chk(r.write.skipped && !r.write.miss, "write skipped when remaining_ops < WRITE_WORST")
    chk(M.slots == [MemSlot(3, 1, 0)] && Bv == [0.75] && pr[] == 0.25, "mandatory settle completed after write skip")
    M2 = slots((3, 1, 0)); Bv2 = [1.0]; pr2 = Ref(0.0)
    r2 = memory_step!(cfg, M2, () -> UInt64(9), 0.9f0, 0.1f0, 0x01, 0x00, Bv2, [1], pr2; remaining_ops = OPS_MEM_WRITE_WORST(cfg))
    chk(!r2.write.skipped && r2.write.appended && M2.slots == [MemSlot(3, 1, 0), MemSlot(9, 1, 0)], "write runs at remaining_ops == WRITE_WORST")
    chk(Bv2 == [0.5] && pr2[] == 0.5, "two slots settled")
    chk(r.settle.ops <= OPS_MEM_SETTLE_WORST(cfg) && r2.settle.ops <= OPS_MEM_SETTLE_WORST(cfg) &&
        r2.write.ops <= OPS_MEM_WRITE_WORST(cfg) && r2.read_ops <= OPS_CTX_KEY + OPS_MEM_READ_WORST(cfg), "measured ops within bounds")
    chk(OPS_CTX_KEY + OPS_MEM_READ_WORST(cfg) + OPS_MEM_SETTLE_WORST(cfg) == OPS_MEM_MANDATORY(cfg) &&
        r2.read_ops + r2.settle.ops <= OPS_MEM_MANDATORY(cfg), "mandatory reservation covers measured read + settle")

    # little-endian serialization and zero fill
    cfg = tcfg(40)
    M = slots((0x0102030405060708, 2, 1))
    buf = serialize_memory(cfg, M)
    exp = zeros(UInt8, 40)
    exp[1] = 0x01
    exp[9:16] = [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]
    exp[17] = 0x02; exp[18] = 0x01
    chk(length(buf) == 40 && buf == exp, "LE bytes of a 1-slot C2 buffer")
    chk(deserialize_memory(cfg, buf).slots == M.slots, "round trip")
    cfg130 = tcfg(2088)
    Mf = MemoryState([MemSlot(UInt64(k), UInt8(a), UInt8((k + a) % 2)) for k in 0:64 for a in 1:2])
    chk(deserialize_memory(cfg130, serialize_memory(cfg130, Mf)).slots == Mf.slots, "C130 full round trip")
    for (B, nb) in ((8, 8), (9, 9))
        c0 = tcfg(B; R = 0)
        b0 = serialize_memory(c0, MemoryState())
        chk(length(b0) == nb && all(==(0x00), b0), "C0_B$B buffer is $nb zero bytes")
    end
    cfg9 = tcfg(9; R = 0)
    bad = zeros(UInt8, 9); bad[9] = 0x01
    chk(throws(() -> deserialize_memory(cfg9, bad), ErrorException), "C0_B9 surplus byte nonzero rejected")
    cfg = tcfg(41)   # C2 with 1 surplus byte
    good = serialize_memory(cfg, M)
    chk(length(good) == 41 && good[41] == 0x00, "C2_B41 surplus byte zero")
    for (what, mut) in (("pad_h", b -> (b[5] = 0x01)), ("count > C", b -> (b[1] = 0x03)),
                        ("pad_s", b -> (b[20] = 0x01)), ("empty slot", b -> (b[30] = 0x01)),
                        ("surplus", b -> (b[41] = 0x01)), ("action 3", b -> (b[17] = 0x03)),
                        ("action 0", b -> (b[17] = 0x00)), ("outcome 2", b -> (b[18] = 0x02)),
                        ("duplicate (k,a)", b -> (b[1] = 0x02; b[25:34] = b[9:18])))
        b = copy(good); mut(b)
        chk(throws(() -> deserialize_memory(cfg, b), ErrorException), "deserialize rejects $what")
    end
    chk(throws(() -> deserialize_memory(cfg, good[1:40]), ErrorException), "deserialize rejects wrong length")
    chk(throws(() -> serialize_memory(cfg, slots((1, 1, 0), (1, 1, 1))), ErrorException), "serialize rejects duplicate (k,a)")
    chk(throws(() -> serialize_memory(cfg, slots((1, 1, 0), (2, 1, 1), (3, 1, 1))), ErrorException), "serialize rejects count > C")
    chk(state_hash(cfg, M) == bytes2hex(sha256(good)), "state_hash = SHA-256 of serialized bytes")
    return NCHK[] - n0
end

function run_gm2_unit()
    n0 = NCHK[]
    cfg = tcfg(24)
    p2 = 0.3f0
    exp = Dict((0.0f0, 0x00) => 0.0f0, (0.0f0, 0x01) => 0.5f0,
               (Float32(2.0^-25), 0x00) => Float32(2.0^-26), (Float32(2.0^-25), 0x01) => 0.5f0,
               (0.5f0, 0x00) => 0.25f0, (0.5f0, 0x01) => 0.75f0,
               (1.0f0, 0x00) => 0.5f0, (1.0f0, 0x01) => 1.0f0)
    chk(Float32(2.0^-25) + 1.0f0 == 1.0f0, "binary32: 2^-25 + 1 rounds to 1.0f0")
    for ((p, y), e) in exp
        M = slots((7, 1, y))
        q1, q2, ops, h1, h2 = read_memory_pair(cfg, M, () -> UInt64(7), p, p2)
        chk(same(q1, e) && same(r_mid(p, y), e), "R-MID p=$p y=$y -> $e")
        chk(h1 && !h2 && same(q2, p2), "R-MID leaves other action raw")
        chk(ops == OPS_CTX_KEY + 4 + 4 + 4, "read ops count (1 slot, 1 hit)")
        q1e, q2e, _, h1e, h2e = read_memory_pair(cfg, MemoryState(), () -> UInt64(7), p, p2)
        chk(same(q1e, p) && same(q2e, p2) && !h1e && !h2e, "empty M returns p_TRM bits")
    end
    # pi_u4 binary32 boundaries
    chk(pi_u4(0.0f0, 0.0f0) === (0.5f0, 0.5f0), "pi_u4 denom == 0")
    chk(pi_u4(-0.0f0, 0.0f0) === (0.5f0, 0.5f0), "pi_u4 denom == -0")
    chk(pi_u4(1.0f0, 0.0f0) === (0.875f0, 0.125f0), "pi_u4 (1,0)")
    chk(pi_u4(0.0f0, 1.0f0) === (0.125f0, 0.875f0), "pi_u4 (0,1)")
    chk(pi_u4(0.5f0, 0.5f0) === (0.5f0, 0.5f0), "pi_u4 (0.5,0.5)")
    chk(pi_u4(0.25f0, 0.75f0) === (0.3125f0, 0.6875f0), "pi_u4 (0.25,0.75)")
    chk(pi_u4(Float32(2.0^-25), 0.0f0) === (0.875f0, 0.125f0), "pi_u4 (2^-25, 0)")
    chk(pi_u4(1.0f0, 1.0f0) === (0.5f0, 0.5f0), "pi_u4 (1,1)")
    # reference by exact rational arithmetic with one binary32 rounding per frozen op
    for p1 in (0.0f0, Float32(2.0^-25), 0.1f0, 0.3f0, 0.5f0, 0.7f0, 1.0f0), q in (0.0f0, Float32(2.0^-25), 0.2f0, 0.5f0, 0.9f0, 1.0f0)
        d = Float32(Rational{BigInt}(p1) + Rational{BigInt}(q))
        if d == 0.0f0
            ref = (0.5f0, 0.5f0)
        else
            r1 = Float32(Rational{BigInt}(p1) / Rational{BigInt}(d)); r2 = Float32(Rational{BigInt}(q) / Rational{BigInt}(d))
            m1 = Float32(3 // 4 * Rational{BigInt}(r1)); m2 = Float32(3 // 4 * Rational{BigInt}(r2))
            ref = (Float32(1 // 8 + Rational{BigInt}(m1)), Float32(1 // 8 + Rational{BigInt}(m2)))
        end
        chk(pi_u4(p1, q) === ref, "pi_u4($p1,$q) equals stepwise-rounded rational reference")
    end
    # C_spec == 0: ctx_key_fn never called, cost exactly 0, bits unchanged
    for B in (8, 9)
        c0 = tcfg(B; R = 0)
        called = Ref(0)
        r = read_memory_pair(c0, MemoryState(), () -> (called[] += 1; error("ctx_key_fn called on C0")), 0.3f0, 0.6f0)
        chk(r === (0.3f0, 0.6f0, 0, false, false) && called[] == 0, "C0_B$B read: no ctx_key, ops 0, bits equal")
        st = memory_step!(c0, MemoryState(), () -> error("ctx_key_fn called"), 0.3f0, 0.6f0, 0x01, 0x01, [1.0], [1], Ref(0.0);
                          remaining_ops = 10^9)
        chk(st.read_ops == 0 && st.write === nothing && st.settle === nothing && st.pi === pi_u4(0.3f0, 0.6f0), "C0_B$B step: no memory work")
        s0 = settle_upkeep!(c0, MemoryState(), [1.0], [1], Ref(0.0))
        chk(s0.ops == 0 && s0.paid_total == 0.0, "C0_B$B settle cost 0")
        w0 = write_memory_candidate!(c0, MemoryState(), UInt64(1), 0x01, 0x01, 0.1f0, 0.1f0; remaining_ops = 10^9)
        chk(w0.ops == 0 && !w0.miss, "C0_B$B write cost 0")
    end
    # no FMA / fmuladd / fast-math in the binary32 path
    chk(no_fma_ir(pi_u4, (Float32, Float32)), "pi_u4 LLVM IR has no fma/fmuladd/contract/fast")
    chk(no_fma_ir(r_mid, (Float32, UInt8)), "r_mid LLVM IR has no fma/fmuladd/contract/fast")
    return NCHK[] - n0
end

function run_gm4()
    n0 = NCHK[]
    # arithmetic environment and primitives
    chk(check_gradual_underflow(), "gradual underflow")
    for (f, T) in ((two_sum, (Float64, Float64)), (add_down, (Float64, Float64)), (add_up, (Float64, Float64)),
                   (two_prod_no_fma, (Float64, Float64)), (div_down, (Float64, Int)), (port_arg, (Float64, Float64)))
        chk(no_fma_ir(f, T), "$f LLVM IR has no fma/fmuladd/contract/fast")
    end
    rng_state = Ref(UInt64(0x9E3779B97F4A7C15))
    nxt() = (rng_state[] = rng_state[] * 0x5851F42D4C957F2D + 0x14057B7EF767814F; rng_state[])
    rnd() = begin
        u = nxt()
        e = Int(u % 1115) - 1074          # exponent in [-1074, 40]
        e <= -1074 ? ldexp(Float64(u >> 60), -1074) : ldexp(1.0 + Float64(u >> 12) / 2.0^52, min(e, 39))
    end
    ok_dir = true; ok_prod = true; ok_div = true
    setprecision(BigFloat, 2400) do
        for _ in 1:20000
            a = rnd(); b = rnd()
            ex = BigFloat(a) + BigFloat(b); ed = BigFloat(a) - BigFloat(b)
            ok_dir &= BigFloat(add_down(a, b)) <= ex <= BigFloat(add_up(a, b))
            ok_dir &= BigFloat(sub_down(a, b)) <= ed <= BigFloat(sub_up(a, b))
            x, y = two_sum(a, b); ok_dir &= BigFloat(x) + BigFloat(y) == ex
            if a >= ldexp(1.0, -400) && b >= ldexp(1.0, -400)   # error term stays normal (use: share >= 2^-56, N <= 2^16)
                p, err = two_prod_no_fma(a, b); ok_prod &= BigFloat(p) + BigFloat(err) == BigFloat(a) * BigFloat(b)
            end
        end
        for _ in 1:20000
            K = ldexp(1.0 + Float64(nxt() >> 12) / 2.0^52, Int(nxt() % 81) - 40)
            N = Int(nxt() % 65536) + 1
            sh = div_down(K, N)
            gap = BigFloat(K) - BigFloat(N) * BigFloat(sh)
            ok_div &= gap >= 0 && gap <= 2 * BigFloat(N) * (BigFloat(nextfloat(sh)) - BigFloat(sh)) && sh >= ldexp(1.0, -56)
        end
    end
    chk(ok_dir, "add_down <= exact <= add_up on [0, 2^40] incl. subnormals (20000 pairs)")
    chk(ok_prod, "two_prod_no_fma exact on [2^-400, 2^40]^2")
    chk(ok_div, "div_down: N*share <= K_mem, share >= 2^-56 (20000 cases)")
    # subnormal balance: after = 0, decrement exactly before
    cfg = tcfg(24; K = 0.25, N = 2)
    sub = ldexp(1.0, -1074)
    Bv = [sub, 1.0]; B0 = copy(Bv); pr = Ref(0.0)
    r = settle_upkeep!(cfg, slots((1, 1, 1)), Bv, [1, 2], pr)
    chk(r.purchased == 1 && Bv[1] == 0.0 && exact_E(B0, Bv) >= bigK(0.25) && exact_diff(pr[], 0.0) <= bigK(r.paid_total) <= exact_E(B0, Bv),
        "subnormal cell fully drained, purchase exact")

    # (a) first write is not free: empty M, alive, balance 0, miss -> purchase fails, count 0, next read 0 hits
    cfg = tcfg(40; K = 0.002, N = 1)
    M = MemoryState(); Bv = [0.0]; pr = Ref(0.0)
    st = memory_step!(cfg, M, () -> UInt64(11), 0.9f0, 0.2f0, 0x01, 0x00, Bv, [1], pr; remaining_ops = 10^9)
    chk(st.write.miss && st.write.appended && st.settle.purchased == 0 && isempty(M.slots), "(a) miss written to candidate but purchase fails")
    chk(Bv == [0.0] && pr[] == 0.0, "(a) no charge")
    q = read_memory_pair(cfg, M, () -> UInt64(11), 0.9f0, 0.2f0)
    chk(!q[4] && !q[5] && same(q[1], 0.9f0), "(a) next-step read finds nothing")

    # (b) P1 boundary: K = 1, B = [0.5, prevfloat(0.5)] -> fail, unchanged, port +0
    cfg = tcfg(24; K = 1.0, N = 2)
    Bv = [0.5, prevfloat(0.5)]; B0 = copy(Bv); pr = Ref(0.0); M = slots((1, 1, 1))
    r = settle_upkeep!(cfg, M, Bv, [1, 2], pr)
    chk(r.purchased == 0 && isempty(M.slots) && Bv == B0 && pr[] == 0.0 && r.trace[1].paid_lo == prevfloat(1.0), "(b) P1 boundary: purchase fails, no change")
    chk(throws(() -> tcfg(24; K = floatmax(Float64)), MemoryConfigError) && throws(() -> tcfg(24; K = ldexp(1.0, -1074)), MemoryConfigError),
        "(b) K_mem = floatmax / 2^-1074 rejected at load")

    # (c) P2/P3 bounded boundary: K = 2.5*2^-40, B = [0, 2^13] -> pass-2 1-ulp correction, success
    K = 2.5 * ldexp(1.0, -40)
    cfg = tcfg(24; K = K, N = 2)
    Bv = [0.0, ldexp(1.0, 13)]; B0 = copy(Bv); pr = Ref(0.0)
    r = settle_upkeep!(cfg, slots((1, 1, 1)), Bv, [1, 2], pr)
    E = exact_E(B0, Bv)
    chk(r.purchased == 1 && E >= bigK(K) && exact_diff(pr[], 0.0) <= bigK(r.paid_total) <= E, "(c) P2/P3 boundary purchase")
    chk(Bv[1] == 0.0, "(c) empty cell untouched")

    # (d) r4 P2: N = 4, B = fill(3*2^12, 4), K = 2.5*2^-39 -> pass-1 decrement 0, E = 3*2^-39 <= K + u
    u = ldexp(1.0, -39); K = 2.5 * u
    cfg = tcfg(24; K = K, N = 4)
    Bv = fill(3.0 * 2.0^12, 4); B0 = copy(Bv); pr = Ref(0.0)
    r = settle_upkeep!(cfg, slots((1, 1, 1)), Bv, [1, 2, 3, 4], pr)
    E = exact_E(B0, Bv)
    chk(r.purchased == 1 && r.trace[1].pass1_paid == 0.0, "(d) pass-1 decrement 0")
    chk(E == bigK(3 * u) && E <= bigK(K) + bigK(u) && count(Bv .!= B0) == 1, "(d) one cell, E = 3*2^-39 <= K + u")
    chk(exact_diff(pr[], 0.0) <= bigK(r.paid_total) <= E, "(d) port <= paid_lo <= E")

    # (e) even split: N = 3, ones, K = 0.002 -> success, K <= E <= K + ulp(1) + 7 ulp(0.002)
    K = 0.002
    cfg = tcfg(24; K = K, N = 3)
    Bv = [1.0, 1.0, 1.0]; B0 = copy(Bv); pr = Ref(0.0)
    r = settle_upkeep!(cfg, slots((1, 1, 1)), Bv, [1, 2, 3], pr)
    E = exact_E(B0, Bv)
    chk(r.purchased == 1 && bigK(K) <= E <= bigK(K) + bigK(eps(1.0)) + 7 * bigK(eps(0.002)), "(e) even split bounds")
    chk(r.trace[1].pass1_paid <= K && exact_diff(pr[], 0.0) <= bigK(r.paid_total) <= E, "(e) pass 1 <= K, port <= paid_lo <= E")

    # (f) P6 port non-creation
    t, a = port_arg(1.0, 3 * ldexp(1.0, -54))
    chk(t == 1.0 && a == 0.0 && exact_diff(1.0 + a, 1.0) <= bigK(3 * ldexp(1.0, -54)), "(f) port 1.0 + 3*2^-54 -> arg 0")
    t, a = port_arg(1.0, 5 * ldexp(1.0, -54))
    chk(t == 1.0 + ldexp(1.0, -52) && a == ldexp(1.0, -52) && exact_diff(1.0 + a, 1.0) <= bigK(5 * ldexp(1.0, -54)), "(f) port 1.0 + 5*2^-54 -> arg 2^-52")
    K = 3 * ldexp(1.0, -40)
    cfg = tcfg(24; K = K, N = 1)
    Bv = [1.0]; B0 = copy(Bv); pr = Ref(2.0^14)
    r = settle_upkeep!(cfg, slots((1, 1, 1)), Bv, [1], pr)
    E = exact_E(B0, Bv)
    chk(r.purchased == 1 && exact_diff(pr[], 2.0^14) == 0 && 0 <= bigK(r.paid_total) <= E && E >= bigK(K), "(f) settle via port 2^14: increment 0 <= paid_lo <= E")

    # (g) partial shortfall: K = 0.25, B = [0.375], 2 candidates -> newest only, B = [0.125], port +0.25
    cfg = tcfg(40; K = 0.25, N = 1)
    M = slots((1, 1, 1), (2, 2, 0)); Bv = [0.375]; pr = Ref(0.0)
    r = settle_upkeep!(cfg, M, Bv, [1], pr)
    chk(r.purchased == 1 && r.upkeep_evicted == 1 && M.slots == [MemSlot(2, 2, 0)], "(g) newest kept, oldest evicted")
    chk(Bv == [0.125] && pr[] == 0.25 && exact_E([0.375], Bv) == bigK(0.25), "(g) E = 0.25, remainder 0.125 untouched")

    # (h) no double charge: hold 1 step -> 1 charge (0.25); hold 2 steps -> 2 charges (0.5); death absorption
    for hold in (1, 2)
        cfg = tcfg(24; K = 0.25, N = 1)
        M = MemoryState(); Bv = [1.0]; pr = Ref(0.0); charges = 0
        k = () -> UInt64(20)
        s = memory_step!(cfg, M, k, 0.75f0, 0.5f0, 0x01, 0x00, Bv, [1], pr; remaining_ops = 10^9)   # miss -> write (20,1,0)
        charges += s.settle.purchased
        chk(M.slots == [MemSlot(20, 1, 0)], "(h) slot bought at step 1")
        for _ in 2:hold                                                                               # no miss: Y=0, p=0.375
            s = memory_step!(cfg, M, k, 0.75f0, 0.5f0, 0x01, 0x00, Bv, [1], pr; remaining_ops = 10^9)
            chk(s.hit[1] && !s.write.miss, "(h) held slot read, no write")
            charges += s.settle.purchased
        end
        # read, miss with TRM agreeing (Y=1, p_trm=0.75, composite 0.375) -> K-UNIQ-CLEAR, nothing to buy
        s = memory_step!(cfg, M, k, 0.75f0, 0.5f0, 0x01, 0x01, Bv, [1], pr; remaining_ops = 10^9)
        chk(s.hit[1] && s.write.cleared && isempty(M.slots) && s.settle.purchased == 0, "(h) cleared after hold, no purchase")
        charges += s.settle.purchased
        chk(charges == hold && Bv == [1.0 - 0.25 * hold] && pr[] == 0.25 * hold, "(h) hold $hold step(s): $hold charge(s), total $(0.25 * hold)")
    end
    cfg = tcfg(40; K = 0.25, N = 2)
    M = slots((1, 1, 1), (2, 2, 0)); h0 = state_hash(cfg, M); Bv = [1.0, 1.0]; pr = Ref(0.5)
    s = memory_step!(cfg, M, () -> UInt64(3), 0.1f0, 0.9f0, 0x01, 0x01, Bv, Int[], pr; remaining_ops = 10^9)
    chk(s.write === nothing && s.settle.dead && s.settle.ops == 0 && s.settle.paid_total == 0.0 && s.settle.upkeep_evicted == 0,
        "(h) death: no write, no charge, no eviction")
    chk(state_hash(cfg, M) == h0 && Bv == [1.0, 1.0] && pr[] == 0.5, "(h) death: final state frozen")

    # operation bounds (fixed integers from r7 §1.1.4) and measured <= worst at N_max, full C
    chk(OPS_MEM_READ_WORST(0) == 0 && OPS_MEM_WRITE_WORST(0) == 0 && OPS_MEM_SETTLE_WORST(0, 576) == 0 && OPS_MEM_MANDATORY(0, 576) == 0, "C0 bounds 0")
    chk(OPS_MEM_READ_WORST(130) == 1048 && OPS_MEM_WRITE_WORST(130) == 1056, "C130 read/write bounds")
    chk(OPS_MEM_SETTLE_WORST(1, 4) == 356 && OPS_MEM_SETTLE_WORST(2, 4) == 651 && OPS_MEM_SETTLE_WORST(130, 4) == 38411, "settle bounds C1/C2/C130 at N_max = 4")
    chk(OPS_MEM_MANDATORY(130, 4) == 16 + 1048 + 38411, "mandatory C130")
    cfg = tcfg(2088; K = 0.002, N = 4)
    Mf = MemoryState([MemSlot(UInt64(k), UInt8(a), 0x01) for k in 0:64 for a in 1:2])
    q = read_memory_pair(cfg, Mf, () -> UInt64(64), 0.4f0, 0.6f0)
    Bv = fill(1.0, 4); pr = Ref(0.0)
    r = settle_upkeep!(cfg, Mf, Bv, [1, 2, 3, 4], pr)
    chk(q[3] <= OPS_CTX_KEY + OPS_MEM_READ_WORST(cfg) && r.purchased == 130 && r.ops <= OPS_MEM_SETTLE_WORST(cfg), "C130 full: measured ops within bounds")
    w = write_memory_candidate!(cfg, copy(Mf), UInt64(999), 0x01, 0x01, 0.1f0, 0.1f0; remaining_ops = 10^9)
    chk(w.evicted_d1 && w.ops <= OPS_MEM_WRITE_WORST(cfg), "C130 full write (D1) within bound")
    return NCHK[] - n0
end

function run_gm5()
    n0 = NCHK[]
    cfg = tcfg(2088)
    ps = Float32[0.0f0, Float32(2.0^-25), 0.1f0, 0.25f0, 0.5f0, 0.6f0, 0.75f0, 0.99f0, 1.0f0]
    ok_ctx = true; ok_act = true; differs = 0
    for k in 0:64, a in (0x01, 0x02), y in (0x00, 0x01)
        Mk = slots((k, a, y))
        for p1 in ps, p2 in ps
            e = read_memory_pair(cfg, MemoryState(), () -> UInt64(k), p1, p2)
            for k2 in (k == 0 ? (1, 64) : (0, k == 64 ? 63 : k + 1))
                r = read_memory_pair(cfg, Mk, () -> UInt64(k2), p1, p2)
                r0 = read_memory_pair(cfg, MemoryState(), () -> UInt64(k2), p1, p2)
                ok_ctx &= same(r[1], r0[1]) && same(r[2], r0[2]) && pi_u4(r[1], r[2]) === pi_u4(r0[1], r0[2]) && !r[4] && !r[5]
            end
            r = read_memory_pair(cfg, Mk, () -> UInt64(k), p1, p2)
            if a == 0x01
                ok_act &= same(r[2], e[2]) && !r[5]
                differs += !same(r[1], e[1])
            else
                ok_act &= same(r[1], e[1]) && !r[4]
                differs += !same(r[2], e[2])
            end
        end
    end
    chk(ok_ctx, "GM5 other context k' != k: (p1, p2) and (pi1, pi2) bit-identical")
    chk(ok_act, "GM5 same context, other action a' != a: raw p_a' bit-identical")
    chk(differs > 0, "GM5 sanity: the held (k, a) does change p_a somewhere")
    return NCHK[] - n0
end

function self_test()
    NCHK[] = 0
    frozen90(); println("PASS G7 frozen90 (3 SHA-256 match freeze-s90.txt)")
    println("PASS GM1 ($(run_gm1()) checks)")
    println("PASS GM2-unit ($(run_gm2_unit()) checks)")
    println("PASS GM4 (a)-(h) + subnormal + op bounds ($(run_gm4()) checks)")
    println("PASS GM5 ($(run_gm5()) checks)")
    println("ALL PASS: $(NCHK[]) checks")
    return true
end

end # module
