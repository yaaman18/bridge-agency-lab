# S91a adapter (discussion/specs/S91a-draft-aue-memory.md r3 §4-§5, L5B-3/L5B-4/L5B-5): OneLife{LawL2} (core/one_life.jl) +
# TracePred (P_DECAY 8, K_WIN 0.002; experiments/onestep/onestep.jl) + the [memory] core experiments/s90_l2l_trm/mem_core.jl,
# as a two-phase species of bed_mem.jl. core/, onestep.jl and mem_core.jl are included / copied from source text, never changed.
# As onestep.jl: core/circuit.jl's step! and one_life.jl's _live are copied from their source text with ONE draw hook added;
# the hook receives `old` (the previous-step receptor vector st.active), never `nw` (nw: negative control NC-M3 only).
# Phase 1: OneLife step + TracePred + memory read (M unchanged); Phase 2: R1 write candidate + prepaid upkeep settlement
# (writes only w.B, w.port, M). Negative-control flags (inject_*) default to false; production paths never set them.
# phenomenal_claim = :not_certified (fixed).

isdefined(Main, :LabCore) || Base.include(Main, normpath(joinpath(@__DIR__, "..", "..", "core", "LabCore.jl")))
isdefined(Main, :AUESeamBed) || Base.include(Main, joinpath(@__DIR__, "bed_mem.jl"))

module AdapterAUEAMem

using SHA
import Main.LabCore
using ..AUESeamBed

const LAB = normpath(joinpath(@__DIR__, "..", ".."))
include(joinpath(LAB, "core", "one_life.jl"))
include(joinpath(LAB, "experiments", "s90_l2l_trm", "mem_core.jl"))
using .S90MemCore

export AUEAMemAdapter, AUEAMemState, PendingWrite, StepRec, NOPENDING, TracePred,
       make_s91a_initial_state, make_s91a_inputs, capacity_spec_text, capacity_bytes, CAPACITIES,
       ctx_key_s91a, rand_u64_stream, env_drive, life_digest, MAPPING_SPEC, MAPPING_SPEC_HASH, OPS_PRED_WORST,
       OpCount, predict_c, pi_u4_c, update_c

# ---------------------------------------------------------------- mapping spec (species_aue_a_mem.toml mapping_spec_hash)
const MAPPING_SPEC = "S91a mapping r3: ctx_key(old, exp_step) = (exp_step == 0) ? UInt64(64) : sum(UInt64(old[R1IDX[i]]) << (i-1) for i in 1:6), " *
    "R1IDX = (1,2,3,4,7,8), old = previous-step receptor vector st.active in the b.perm body frame (never nw); " *
    "action coord {1,2} = patch motors b.patch; Y_t = (y[a] > 0); " *
    "draw u = Float64(rand_u64 >> 11) * 2.0^-53, pis = pi_u4(p1::Float32, p2::Float32), a = (u < Float64(pis[1])) ? 1 : 2 (strict <)"
const MAPPING_SPEC_HASH = bytes2hex(sha256(MAPPING_SPEC))

# ---------------------------------------------------------------- step_s91a! / _live_s91a (source copies with the draw hook)
function rep1(f, anchor, new)
    n = length(findall(anchor, f)); n == 1 || error("anchor occurs $n times: $anchor")
    return replace(f, anchor => new)
end
function _aue_step_source(src, name::String, recv::String)
    i = findfirst("function step!(st::CState, b::Circuit, y;", src); i === nothing && error("anchor: function step!")
    j = findnext("\nend\n", src, i[1]); j === nothing && error("anchor: end")
    f = src[i[1]:j[end]]
    f = rep1(f, "function step!(st::CState, b::Circuit, y;", "function $name(st::CState, b::Circuit, y;")
    f = rep1(f, "rest_off = false, body_flag = nothing)", "rest_off = false, body_flag = nothing, draw = nothing)")
    a = "        for m in cand; m != win && (nw[m] = false); end\n"
    f = rep1(f, a, """
        if draw !== nothing
            dcs = cand
            if idle_first; didl = [m for m in cand if now - st.lastM[m] > FORGET]; isempty(didl) || (dcs = didl); end
            win = draw(cand, dcs, win, key, b, conf, habit, total, y, $recv)
        end
""" * a)
    return f
end
const _CIRCUIT_SRC = read(joinpath(LAB, "core", "circuit.jl"), String)
Core.eval(LabCore, Meta.parse(_aue_step_source(_CIRCUIT_SRC, "step_s91a!", "old")))
Core.eval(LabCore, Meta.parse(_aue_step_source(_CIRCUIT_SRC, "step_s91a_leak!", "nw")))   # NC-M3 only

function _live_source(name::String, stepname::String)
    src = read(joinpath(LAB, "core", "one_life.jl"), String)
    i = findfirst("function _live(s::OneLife{L}, g,", src); i === nothing && error("anchor: _live")
    j = findnext("\nend\n", src, i[1]); f = src[i[1]:j[end]]
    f = rep1(f, "function _live(s::OneLife{L}, g,", "function $name(draw, s::OneLife{L}, g,")
    f = rep1(f, "out = step!(circuit, b, [y[1], y[2], 0.0]; noise = noise,", "out = LabCore.$stepname(circuit, b, [y[1], y[2], 0.0]; draw = draw, noise = noise,")
    return f
end
Core.eval(@__MODULE__, Meta.parse(_live_source("_live_s91a", "step_s91a!")))
Core.eval(@__MODULE__, Meta.parse(_live_source("_live_s91a_leak", "step_s91a_leak!")))

# ---------------------------------------------------------------- TracePred (onestep.jl:49-67, the same definitions)
struct TracePred; m1::Float64; m2::Float64; end
const K_WIN = 0.002; const P_DECAY = 8.0
TracePred() = TracePred(0.5, 0.5)
function predict(p::TracePred, R)
    q = (1 * K_WIN <= R) ? p : TracePred()
    return (q, q.m1, q.m2)
end
_clip(x) = min(199 / 200, max(1 / 200, x))
function update(p::TracePred, a, ans)
    t = ans ? 1.0 : 0.0
    a == 1 ? TracePred(_clip(p.m1 + (t - p.m1) / P_DECAY), p.m2) : TracePred(p.m1, _clip(p.m2 + (t - p.m2) / P_DECAY))
end
pred_bytes(p::TracePred) = (io = IOBuffer(); write(io, UInt8(1)); write(io, htol(reinterpret(UInt64, p.m1))); write(io, htol(reinterpret(UInt64, p.m2))); take!(io))
body_R(life::OneLife) = (w = life.w; sum((w.B[i] for i in eachindex(w.C) if w.C[i] != 0); init = 0.0))

# Counted primitive operations of one drawn step, counted as they execute (a step without a draw costs 0): predict = K_win
# compare 1 (+ 2 on the low-balance reset); Float32 conversions 2; pi_u4 = add 1, zero test 1 (zero branch ends here: 2), else
# divisions 2, multiplications 2, additions 2 (8); draw = shift, conversion, multiplication of u, Float64(pi1), strict < (5);
# update = outcome select 1, patch branch 1, subtraction, division, addition 3, clip 2 (7). Normal step 23, reset 25, zero 17.
# Checked against OPS_PRED_WORST every drawn step. The counted forms return bit-identical values to predict / pi_u4 / update.
const OPS_PRED_WORST = 64
mutable struct OpCount; n::Int; end
function predict_c(p::TracePred, R, c::OpCount)
    c.n += 1
    (1 * K_WIN <= R) && return (p, p.m1, p.m2)
    c.n += 2
    q = TracePred()
    return (q, q.m1, q.m2)
end
function pi_u4_c(p1::Float32, p2::Float32, c::OpCount)
    c.n += 1; denom = p1 + p2
    c.n += 1; denom == 0.0f0 && return (0.5f0, 0.5f0)
    c.n += 2; q1 = p1 / denom; q2 = p2 / denom
    c.n += 2; m1 = 0.75f0 * q1; m2 = 0.75f0 * q2
    c.n += 2; return (0.125f0 + m1, 0.125f0 + m2)
end
function update_c(p::TracePred, a, ans, c::OpCount)
    c.n += 1; t = ans ? 1.0 : 0.0
    c.n += 1
    if a == 1
        c.n += 3; v = p.m1 + (t - p.m1) / P_DECAY
        c.n += 2; return TracePred(_clip(v), p.m2)
    else
        c.n += 3; v = p.m2 + (t - p.m2) / P_DECAY
        c.n += 2; return TracePred(p.m1, _clip(v))
    end
end

# ---------------------------------------------------------------- ctx_key (spec §4.2, H: exp_step == 0 -> 64)
const R1IDX = (1, 2, 3, 4, 7, 8)
function ctx_key_s91a(old::AbstractVector{Bool}, exp_step::Integer)::UInt64
    exp_step == 0 && return UInt64(64)
    k = UInt64(0)
    for i in 1:6
        old[R1IDX[i]] && (k |= UInt64(1) << (i - 1))
    end
    return k
end

# ---------------------------------------------------------------- state
struct PendingWrite
    drawn::Bool
    k::UInt64
    a::Int
    Y_t::Bool
    p_pre::Float32
    p_base::Float32
    remaining_ops::Int
end
const NOPENDING = PendingWrite(false, UInt64(0), 0, false, 0.0f0, 0.0f0, 0)

# Read-only record of the last Phase 1 (statistics; part of digest_excl_settle).
struct StepRec
    drawn::Bool
    k::UInt64
    a::Int                 # executed patch (route_det: the DET winner's patch)
    a_draw::Int            # drawn patch
    det_patch::Int
    Y_t::Bool              # y[a_draw] > 0
    take::Float64          # harvest of the executed patch a this step (drawn steps)
    take1::Float64; take2::Float64   # harvest of patch 1 / 2 this step (every alive step, drawn or not)
    take_all::Float64      # take1 + take2
    y1::Float64; y2::Float64
    p1_base::Float32; p2_base::Float32
    p1::Float32; p2::Float32
    pi1::Float32; pi2::Float32
    u::Float64
    hit1::Bool; hit2::Bool
    ops_pred::Int
    read_ops::Int
end
const NOREC = StepRec(false, UInt64(0), 0, 0, 0, false, 0.0, 0.0, 0.0, 0.0, NaN, NaN, NaN32, NaN32, NaN32, NaN32, NaN32, NaN32, NaN, false, false, 0, 0)

struct AUEAMemState
    life::OneLife{LawL2}
    pred::TracePred
    M::MemoryState
    cfg::MemoryConfig
    exp_step::Int
    pending_write::PendingWrite
    last_rec::StepRec
end

# ---------------------------------------------------------------- capacities and the species spec text
const CAPACITIES = (:C0_B8, :C0_B9, :C1, :C2, :C130)
const _CAP_BYTES = Dict(:C0_B8 => 8, :C0_B9 => 9, :C1 => 24, :C2 => 40, :C130 => 2088)
capacity_bytes(c::Symbol) = _CAP_BYTES[c]
const SPEC_PATH = joinpath(@__DIR__, "species_aue_a_mem.toml")

# The species text of a capacity: the default text with the reserved_bytes and max_read_ops_per_step lines rewritten.
function capacity_spec_text(c::Symbol; path::AbstractString = SPEC_PATH)
    B = capacity_bytes(c); C = fld(B - 8, 16)
    src = read(path, String)
    src = rep1(src, "\nreserved_bytes = 40\n", "\nreserved_bytes = $B\n")
    src = rep1(src, "\nmax_read_ops_per_step = 24\n", "\nmax_read_ops_per_step = $(OPS_MEM_READ_WORST(C))\n")
    return src
end

struct AUEAMemAdapter <: AbstractSpeciesAdapter
    spec::SpeciesSpec
    cfg::MemoryConfig
    capacity::Symbol
    organ_type::String
    route_det::Bool                 # NC-M5: records the draw, acts as DET
    inject_leak_nw::Bool            # NC-M3: the hook receives nw instead of old
    inject_c0_ctx::Bool             # NC-M1b: ctx_key computed (and charged) on C_spec == 0
    inject_c0b9_surplus::Bool       # NC-M1a: surplus byte of the memory bytes non-zero
    inject_fake_paid::Bool          # NC-M2a: settlement on a copy of the cell balances (cells untouched), port credited, payment reported
    inject_fake_port_delta::Bool    # NC-M2b: cells debited, port untouched, port delta reported
    inject_scalar_inflate::Bool     # NC-M2c: memory_upkeep_paid + 1.0 reported
    inject_free_hold::Bool          # NC-M4: non-drawn steps keep the memory without settlement
    inject_false_death::Bool        # NC-M6: is_alive reports false
    inject_phase2_tamper::Bool      # NC-M7a: Phase 2 writes the circuit
    inject_pending_tamper::Bool     # NC-M7b: Phase 2 rewrites pending_write.a
    inject_phase1_write::Bool       # NC-M8: Phase 1 writes M
    inject_leak_amount::Float64     # GB-M2 leak: matter removed from a body cell after settlement
    inject_outflow_tamper::Symbol   # GB-M3: Phase 2 adds to w.port.outflow on a dead step (:dead) / a settling step (:live)
end

function AUEAMemAdapter(capacity::Symbol = :C2; spec_text::Union{Nothing,String} = nothing,
                        organ_type::String = "L2_circuit_bin3_tracepred_mem",
                        route_det::Bool = false, inject_leak_nw::Bool = false, inject_c0_ctx::Bool = false,
                        inject_c0b9_surplus::Bool = false, inject_fake_paid::Bool = false, inject_fake_port_delta::Bool = false,
                        inject_scalar_inflate::Bool = false, inject_free_hold::Bool = false, inject_false_death::Bool = false,
                        inject_phase2_tamper::Bool = false, inject_pending_tamper::Bool = false, inject_phase1_write::Bool = false,
                        inject_leak_amount::Float64 = 0.0, inject_outflow_tamper::Symbol = :none)
    inject_outflow_tamper in (:none, :dead, :live) || error("inject_outflow_tamper must be :none, :dead or :live")
    spec = load_species_spec_text(spec_text === nothing ? capacity_spec_text(capacity) : spec_text)
    spec.has_memory || error("species spec has no [memory]")
    spec.mapping_spec_hash == MAPPING_SPEC_HASH || error("mapping_spec_hash != SHA-256(MAPPING_SPEC)")
    cfg = load_memory_config(reserved_bytes = spec.memory_reserved_bytes, header_bytes = spec.memory_header_bytes,
                             slot_bytes = spec.memory_slot_bytes, upkeep_rate_per_slot = spec.memory_upkeep_rate,
                             max_body_cells = spec.memory_max_body_cells, max_read_ops_per_step = spec.memory_max_read_ops,
                             B_max = spec.budget_per_step, ops_trm_min = OPS_PRED_WORST)
    cfg.C == spec.memory_c_spec || error("C_spec mismatch between bed and memory core")
    OPS_MEM_MANDATORY(cfg) + OPS_MEM_WRITE_WORST(cfg) + OPS_PRED_WORST <= spec.budget_per_step ||
        error("per-step budget below the worst-case reservation")
    AUEAMemAdapter(spec, cfg, capacity, organ_type, route_det, inject_leak_nw, inject_c0_ctx, inject_c0b9_surplus,
                   inject_fake_paid, inject_fake_port_delta, inject_scalar_inflate, inject_free_hold, inject_false_death,
                   inject_phase2_tamper, inject_pending_tamper, inject_phase1_write, inject_leak_amount, inject_outflow_tamper)
end

AUESeamBed.species_spec(a::AUEAMemAdapter) = a.spec
AUESeamBed.uses_two_phase_memory(::AUEAMemAdapter) = true
AUESeamBed.is_run_invalid_exception(::AUEAMemAdapter, e) = e isa InvalidResourceError

# ---------------------------------------------------------------- initial state (spec §4.1)
function make_s91a_initial_state(seed::Integer, cfg::MemoryConfig)::AUEAMemState
    life = onelife_birth(seed, LawL2)
    for g in LabCore.BO_CUR
        life, err = onelife_step(life, Int.(g))
        err && error("BO_CUR drive rejected")
    end
    return AUEAMemState(life, TracePred(), MemoryState(), cfg, 0, NOPENDING, NOREC)
end
make_s91a_initial_state(seed::Integer, a::AUEAMemAdapter) = make_s91a_initial_state(seed, a.cfg)

# ---------------------------------------------------------------- environments and rand_u64 (spec §5)
function env_drive(env::Symbol, s::Integer)::Tuple{Int,Int}
    if env === :env_stat
        g = Int.(LabCore.bo_season(s)); return (g[1], g[2])
    elseif env === :env_rev
        g = Int.(LabCore.bo_season(s)); return s < 2000 ? (g[1], g[2]) : (g[2], g[1])
    elseif env === :env_depl
        c = (s % 200) + 1
        return c <= 60 ? (2, 1) : c <= 120 ? (1, 2) : (0, 0)
    end
    error("unknown environment $env")
end
function rand_u64_stream(seed::Integer, steps::Integer)::Vector{UInt64}
    rng = LabCore.Mulberry(seed + 100_000)
    out = Vector{UInt64}(undef, steps)
    for s in 1:steps
        u1 = UInt32(trunc(UInt64, rng() * 4294967296.0))
        u2 = UInt32(trunc(UInt64, rng() * 4294967296.0))
        out[s] = (UInt64(u1) << 32) | UInt64(u2)
    end
    return out
end
function make_s91a_inputs(seed::Integer, env::Symbol, steps::Integer)::Vector{StampedInput}
    ru = rand_u64_stream(seed, steps)
    [StampedInput(s, Dict{String,Any}("g1" => env_drive(env, s)[1], "g2" => env_drive(env, s)[2], "rand_u64" => ru[s+1]))
     for s in 0:steps-1]
end

# ---------------------------------------------------------------- digests (little-endian canonical bytes)
function _rec_bytes(io::IO, r::StepRec)
    for f in fieldnames(StepRec)
        v = getfield(r, f)
        v isa Bool ? write(io, UInt8(v)) : write(io, htol(v))
    end
end
function _pw_bytes(io::IO, p::PendingWrite)
    write(io, UInt8(p.drawn)); write(io, htol(p.k)); write(io, htol(Int64(p.a))); write(io, UInt8(p.Y_t))
    write(io, htol(p.p_pre)); write(io, htol(p.p_base)); write(io, htol(Int64(p.remaining_ops)))
end
function _tail_bytes(io::IO, st::AUEAMemState)
    write(io, pred_bytes(st.pred)); write(io, htol(Int64(st.exp_step))); _pw_bytes(io, st.pending_write); _rec_bytes(io, st.last_rec)
    write(io, htol(Int64(st.cfg.B)))
end
# Every component except the Phase 2 write set {w.B at body cells, w.port.reservoir, w.port.outflow, M}.
# The bytes are those of onelife_encode on a copy whose body-cell B, port.reservoir and port.outflow are 0.0, written without the copy.
function _enc_fields(io::IO, x, subst)
    for f in fieldnames(typeof(x))
        v = haskey(subst, f) ? subst[f] : getfield(x, f)
        if Nothing <: fieldtype(typeof(x), f)
            v === nothing ? write(io, 0x00) : (write(io, 0x01); _enc(io, v))
        else
            _enc(io, v)
        end
    end
end
function AUESeamBed.digest_excl_settle(::AUEAMemAdapter, st::AUEAMemState)::String
    w = st.life.w
    Bz = copy(w.B); for i in eachindex(w.C); w.C[i] != 0 && (Bz[i] = 0.0); end
    p = w.port
    pz = Port(0.0, p.scale, p.unit, p.inflow, 0.0)
    io = IOBuffer()
    for f in fieldnames(OneLife{LawL2})
        v = getfield(st.life, f)
        if f === :w
            _enc_fields(io, w, Dict{Symbol,Any}(:B => Bz, :port => pz))
        elseif Nothing <: fieldtype(OneLife{LawL2}, f)
            v === nothing ? write(io, 0x00) : (write(io, 0x01); _enc(io, v))
        else
            _enc(io, v)
        end
    end
    _tail_bytes(io, st)
    bytes2hex(sha256(take!(io)))
end
# Reference form (deep copy, used by the self-test to check the fast form above byte for byte).
function _excl_bytes_ref(st::AUEAMemState)
    c = deepcopy(st.life)
    for i in eachindex(c.w.C); c.w.C[i] != 0 && (c.w.B[i] = 0.0); end
    c.w.port.reservoir = 0.0; c.w.port.outflow = 0.0
    io = IOBuffer(); write(io, onelife_encode(c)); _tail_bytes(io, st)
    bytes2hex(sha256(take!(io)))
end
# The full state: the life (with w.B and w.port), the tail of digest_excl_settle, and the fixed-length memory bytes.
function AUESeamBed.state_digest(a::AUEAMemAdapter, st::AUEAMemState)::String
    io = IOBuffer(); write(io, onelife_encode(st.life)); _tail_bytes(io, st); write(io, AUESeamBed.memory_bytes(a, st))
    bytes2hex(sha256(take!(io)))
end
# The life and the predictor only (memory bytes excluded; GB-M1 comparison with the memoryless baseline).
life_digest(st::AUEAMemState) = bytes2hex(sha256(vcat(onelife_encode(st.life), pred_bytes(st.pred))))

function AUESeamBed.memory_bytes(a::AUEAMemAdapter, st::AUEAMemState)::Vector{UInt8}
    m = serialize_memory(st.cfg, st.M)
    (a.inject_c0b9_surplus && length(m) > st.cfg.H + st.cfg.C * st.cfg.s) && (m[end] = 0x01)
    return m
end
AUESeamBed.is_alive(a::AUEAMemAdapter, st::AUEAMemState) = a.inject_false_death ? false : (!st.life.dead && !_empty_body(st.life))
AUESeamBed.body_cell_ids(::AUEAMemAdapter, st::AUEAMemState) = [i for i in eachindex(st.life.w.C) if st.life.w.C[i] != 0]
AUESeamBed.body_balances(a::AUEAMemAdapter, st::AUEAMemState) = st.life.w.B[AUESeamBed.body_cell_ids(a, st)]
AUESeamBed.port_balance(::AUEAMemAdapter, st::AUEAMemState) = st.life.w.port.reservoir
AUESeamBed.port_outflow(::AUEAMemAdapter, st::AUEAMemState) = st.life.w.port.outflow
# Exact sum (2400-bit, explicit precision; the global default is never changed here, see bed_mem.jl) rounded once to Float64,
# so that the reported total is monotone in the exact total.
_bf(x) = BigFloat(x; precision = BIGPREC)
function _pk(x::BigFloat)
    (precision(x) == BIGPREC && bigprec_ok()) || throw(MemoryAccountingViolation("BigFloat precision $(precision(x)) != $(BIGPREC) (precision downgraded)"))
    return x
end
function _exact_sum(xs)
    s = _pk(_bf(0))
    for x in xs; s = _pk(s + _pk(_bf(x))); end
    return s
end
function AUESeamBed.total_matter(::AUEAMemAdapter, st::AUEAMemState)::Float64
    w = st.life.w
    return Float64(_exact_sum(Iterators.flatten(((w.port.reservoir,), (v for i in eachindex(w.A) for v in (w.A[i], w.B[i]))))))
end

# ---------------------------------------------------------------- Phase 1 (spec §4.2; M is not changed)
mutable struct _Box
    rec::StepRec
    pred_eff::TracePred
end

# test hook: a given u (u_override) in place of the rand_u64 conversion
_make_draw(box::_Box, ad::AUEAMemAdapter, st::AUEAMemState, R::Float64, u::Float64) =
    _make_draw(box, ad, st, R, UInt64(0); u_override = u)
function _make_draw(box::_Box, ad::AUEAMemAdapter, st::AUEAMemState, R::Float64, ru::UInt64; u_override::Union{Nothing,Float64} = nothing)
    cfg = st.cfg
    return function (cand, cs, win, key, b, conf, habit, total, y, old)
        s = sort([m for m in cs if b.patch[m] <= 2]; by = m -> (b.patch[m], m))
        length(unique(b.patch[m] for m in s)) >= 2 || return win
        c = OpCount(0)
        pe, p1b, p2b = predict_c(st.pred, R, c)
        c.n += 2; p1f = Float32(p1b); p2f = Float32(p2b)
        k = UInt64(0); rops = 0; h1 = h2 = false
        if cfg.C == 0
            p1, p2 = p1f, p2f
            if ad.inject_c0_ctx
                k = ctx_key_s91a(old, st.exp_step); rops = OPS_CTX_KEY
            end
        else
            k = ctx_key_s91a(old, st.exp_step)
            p1, p2, rops, h1, h2 = read_memory_pair(cfg, st.M, () -> k, p1f, p2f)
        end
        pis = pi_u4_c(p1, p2, c)
        u = u_override === nothing ? Float64(ru >> 11) * 2.0^-53 : u_override
        c.n += 3                                  # u = Float64(rand_u64 >> 11) * 2^-53 (only on a drawn step)
        c.n += 2; a = (u < Float64(pis[1])) ? 1 : 2
        ch = s[findfirst(m -> b.patch[m] == a, s)]
        ex = ad.route_det ? win : ch
        box.pred_eff = pe
        box.rec = StepRec(true, k, b.patch[ex], a, b.patch[win], y[a] > 0, 0.0, 0.0, 0.0, 0.0, Float64(y[1]), Float64(y[2]),
                          p1f, p2f, p1, p2, pis[1], pis[2], u, h1, h2, c.n, rops)
        return ex
    end
end

function _out(a::AUEAMemAdapter, st::AUEAMemState)
    acts = onelife_acts(st.life)
    DeclaredOutput(Dict{String,Any}("act_patch_1" => (1 in acts ? 1 : 0), "act_patch_2" => (2 in acts ? 1 : 0),
                                    "alive" => AUESeamBed.is_alive(a, st), "constituents" => count(!=(0), st.life.w.C)), a.organ_type)
end

function AUESeamBed.step_species_pre_settle(a::AUEAMemAdapter, st::AUEAMemState, si::StampedInput, budget::Budget)
    life = st.life
    g = (Int(si.ports["g1"]), Int(si.ports["g2"]))
    ru = UInt64(si.ports["rand_u64"])
    M = copy(st.M)
    if life.dead || _empty_body(life)
        nl = life.dead ? deepcopy(life) : _detect(life)
        mid = AUEAMemState(nl, st.pred, M, st.cfg, st.exp_step + 1, NOPENDING, NOREC)
        return (mid, _out(a, mid), StepCost(0, 0.0, 0.0, 0.0), nothing)
    end
    _drive_ok(g) || throw(ArgumentError("drive $g outside {0..5}^2"))
    box = _Box(NOREC, st.pred)
    U = 0.02
    pool_pre = copy(life.pool)
    y = [min(5.0, floor(r / U + 1e-9)) for r in pool_pre]
    hook = _make_draw(box, a, st, body_R(life), ru)
    live = a.inject_leak_nw ? _live_s91a_leak : _live_s91a
    nl = Base.invokelatest(live, hook, life, g, U, 0.004, 0.002, :bin3, true, true, false)
    r = box.rec
    uc = OpCount(0)
    pred2 = r.drawn ? update_c(box.pred_eff, r.a_draw, r.Y_t, uc) : st.pred     # onestep.jl:122 (also on a dying step)
    # the harvest of every patch this step (drawn or not), recomputed read-only from the acting motors (same arithmetic as _live)
    acts = onelife_acts(nl)
    offer = [0.0, 0.0]; for p in acts; offer[p] = y[p]; end
    d = LabCore.allocate(offer)
    tk = [(!isempty(acts) && d[k] > 0) ? min(pool_pre[k], d[k] * U) : 0.0 for k in 1:2]
    pw = NOPENDING
    if !r.drawn
        r = StepRec(false, UInt64(0), 0, 0, 0, false, 0.0, tk[1], tk[2], tk[1] + tk[2], NaN, NaN, NaN32, NaN32, NaN32, NaN32,
                    NaN32, NaN32, NaN, false, false, 0, 0)
    else
        ops_pred = r.ops_pred + uc.n
        ops_pred <= OPS_PRED_WORST || error("ops_pred $(ops_pred) > OPS_PRED_WORST")
        r = StepRec(r.drawn, r.k, r.a, r.a_draw, r.det_patch, r.Y_t, tk[r.a], tk[1], tk[2], tk[1] + tk[2], r.y1, r.y2, r.p1_base, r.p2_base,
                    r.p1, r.p2, r.pi1, r.pi2, r.u, r.hit1, r.hit2, ops_pred, r.read_ops)
        if st.cfg.C > 0
            remaining = budget.ops_per_step - r.ops_pred - r.read_ops - OPS_MEM_SETTLE_WORST(st.cfg)
            p_pre = r.a_draw == 1 ? r.p1 : r.p2
            p_base = r.a_draw == 1 ? r.p1_base : r.p2_base
            pw = PendingWrite(true, r.k, r.a_draw, r.Y_t, p_pre, p_base, remaining)
        end
    end
    if a.inject_phase1_write && st.cfg.C > 0 && length(M.slots) < st.cfg.C &&
       !any(x -> x.ctx_key == UInt64(0xdead) && x.action == 0x01, M.slots)
        push!(M.slots, MemSlot(UInt64(0xdead), 0x01, 0x01))
    end
    mid = AUEAMemState(nl, pred2, M, st.cfg, st.exp_step + 1, pw, r)
    return (mid, _out(a, mid), StepCost(r.ops_pred + r.read_ops, 0.0, 0.0, 0.0), nothing)
end

# ---------------------------------------------------------------- Phase 2 (spec §4.2; writes only w.B, w.port, M)
function AUESeamBed.settle_species_memory!(a::AUEAMemAdapter, w::AUEAMemState, alive_post::Bool, ::Budget)
    cfg = w.cfg
    info = Dict{String,Any}()
    if !alive_post || cfg.C == 0
        a.inject_outflow_tamper === :dead && !alive_post && (w.life.w.port.outflow += 1.0)
        return (w, SettleCost(length(w.M.slots), Float64[], 0.0, 0.0, 0, 0, info))
    end
    pw = w.pending_write
    cand = copy(w.M)
    wops = 0
    if pw.drawn && pw.remaining_ops >= OPS_MEM_WRITE_WORST(cfg)
        wr = write_memory_candidate!(cfg, cand, pw.k, UInt8(pw.a), UInt8(pw.Y_t), pw.p_pre, pw.p_base; remaining_ops = pw.remaining_ops)
        wops = wr.ops
        info["write"] = wr
    end
    wl = w.life.w
    body_post = [i for i in eachindex(wl.C) if wl.C[i] != 0]
    if a.inject_free_hold && !pw.drawn
        w.M.slots = cand.slots
        info["settle"] = nothing
        return (w, SettleCost(length(w.M.slots), Float64[], 0.0, 0.0, 0, wops, info))
    end
    if a.inject_fake_paid
        Bc = copy(wl.B); p_ref = Ref(wl.port.reservoir)
        st = settle_upkeep!(cfg, w.M, Bc, body_post, p_ref; cand = cand)
        wl.port.reservoir = p_ref[]; wl.port.outflow += st.port_delta
    else
        p_ref = Ref(wl.port.reservoir)
        st = settle_upkeep!(cfg, w.M, wl.B, body_post, p_ref; cand = cand)
        if !a.inject_fake_port_delta
            wl.port.reservoir = p_ref[]
            wl.port.outflow += st.port_delta
        end
    end
    a.inject_leak_amount != 0.0 && (wl.B[body_post[1]] -= a.inject_leak_amount)
    a.inject_outflow_tamper === :live && (wl.port.outflow += 2.0^-20)
    info["settle"] = st
    slot_paid_lo = Float64[tr.paid_lo for tr in st.trace if tr.purchased]
    paid = Float64(_exact_sum(slot_paid_lo))
    a.inject_scalar_inflate && (paid += 1.0)
    out = w
    a.inject_phase2_tamper && (w.life.circuit.t += 1)
    if a.inject_pending_tamper && pw.drawn
        p2 = PendingWrite(pw.drawn, pw.k, 3 - pw.a, pw.Y_t, pw.p_pre, pw.p_base, pw.remaining_ops)
        out = AUEAMemState(w.life, w.pred, w.M, w.cfg, w.exp_step, p2, w.last_rec)
    end
    return (out, SettleCost(length(w.M.slots), slot_paid_lo, paid, st.port_delta, st.ops, wops, info))
end

end # module AdapterAUEAMem
