# S60 deterministic inference of TRM (spec discussion/specs/S60-trm-det.md r3). Canonical Julia; rust/trm-det is the copy.
# Port of SamsungSAILMontreal/TinyRecursiveModels (commit 7de0d20), models/layers.py and models/recursive_reasoning/trm.py,
# eval-mode forward only, attention variant, puzzle_emb_len 0. Copyright (c) 2025 Samsung Electronics Co., Ltd.
# MIT License: see ../LICENSE-upstream-MIT.txt
#
# Every float op is a single IEEE binary32 op in a fixed order: sums start at +0 and run over increasing index,
# products are rounded before the add (no fma, no BLAS, no @simd, no @fastmath, no libm). exp is exp_det below.
# Arrays are flat row-major Vector{Float32} (last index fastest), indices 0-based in the formulas (+1 on access).

module TrmDet

const F32 = Float32
const MAGIC_BUNDLE = b"TRMDET1\n"
const MAGIC_OUT = b"TRMOUT1\n"
const TAG_F32 = 0x01
const TAG_I32 = 0x02

# ---------------- binary records (spec §2) ----------------

struct Rec
    name::String
    tag::UInt8
    dims::Vector{Int}
    f::Vector{Float32}
    i::Vector{Int32}
end
RecF(name, dims, v::Vector{Float32}) = Rec(name, TAG_F32, collect(Int, dims), v, Int32[])
RecI(name, dims, v::Vector{Int32}) = Rec(name, TAG_I32, collect(Int, dims), Float32[], v)

function read_recs(path::AbstractString, magic)
    open(path, "r") do io
        m = read(io, 8)
        m == magic || error(string(path, ": bad magic"))
        n = Int(ltoh(read(io, UInt32)))
        recs = Rec[]
        for _ in 1:n
            l = Int(ltoh(read(io, UInt16)))
            name = String(read(io, l))
            length(name) == l || error("short name")
            tag = read(io, UInt8)
            d = Int(read(io, UInt8))
            dims = Int[Int(ltoh(read(io, UInt32))) for _ in 1:d]
            cnt = d == 0 ? 0 : prod(dims)
            if tag == TAG_F32
                v = Vector{Float32}(undef, cnt)
                read!(io, v)
                push!(recs, RecF(name, dims, ltoh.(v)))
            elseif tag == TAG_I32
                v = Vector{Int32}(undef, cnt)
                read!(io, v)
                push!(recs, RecI(name, dims, ltoh.(v)))
            else
                error(string(path, ": bad tag ", tag, " in ", name))
            end
        end
        eof(io) || error(string(path, ": trailing bytes"))
        return recs
    end
end

function write_recs(path::AbstractString, magic, recs::Vector{Rec})
    open(path, "w") do io
        write(io, magic)
        write(io, htol(UInt32(length(recs))))
        for r in recs
            write(io, htol(UInt16(ncodeunits(r.name))))
            write(io, r.name)
            write(io, r.tag)
            write(io, UInt8(length(r.dims)))
            for d in r.dims
                write(io, htol(UInt32(d)))
            end
            r.tag == TAG_F32 ? write(io, htol.(r.f)) : write(io, htol.(r.i))
        end
    end
    return path
end

recdict(recs) = Dict(r.name => r for r in recs)

# ---------------- exp_det (spec §1) ----------------

const LOG2E = reinterpret(F32, 0x3fb8aa3b)
const LN2_HI = reinterpret(F32, 0x3f317200)
const LN2_LO = reinterpret(F32, 0x35bfbe8e)
const C0 = reinterpret(F32, 0x3f800000)
const C1 = reinterpret(F32, 0x3f800000)
const C2 = reinterpret(F32, 0x3f000000)
const C3 = reinterpret(F32, 0x3e2aaaab)
const C4 = reinterpret(F32, 0x3d2aaaab)
const C5 = reinterpret(F32, 0x3c088889)
const C6 = reinterpret(F32, 0x3ab60b61)
const C7 = reinterpret(F32, 0x39500d01)

# mutation hooks (defaults off): :exp_lin truncates the polynomial at degree 1 (control n3)
const EXP_MUT = Ref(:none)
# diagnostic hook for gate E: when set, every exp_det argument is appended
const EXP_LOG = Ref{Union{Nothing,Vector{Float32}}}(nothing)

function exp_det(x::F32)
    log = EXP_LOG[]
    log === nothing || push!(log, x)
    isnan(x) && return x
    x > F32(88) && return F32(Inf)
    x < F32(-87) && return F32(0)
    t = x * LOG2E
    y = t + F32(0.5)
    i = unsafe_trunc(Int32, y)
    if F32(i) > y
        i -= Int32(1)
    end
    k = F32(i)
    r = (x - k * LN2_HI) - k * LN2_LO
    local p::F32
    if EXP_MUT[] === :exp_lin
        p = C1 * r
        p = p + C0
    else
        p = C7
        p = p * r; p = p + C6
        p = p * r; p = p + C5
        p = p * r; p = p + C4
        p = p * r; p = p + C3
        p = p * r; p = p + C2
        p = p * r; p = p + C1
        p = p * r; p = p + C0
    end
    scale = reinterpret(F32, UInt32(i + Int32(127)) << 23)
    return p * scale
end

# ---------------- model ----------------

struct Layer
    wqkv::Vector{F32}
    wo::Vector{F32}
    wgu::Vector{F32}
    wdown::Vector{F32}
end

struct Model
    B::Int; S::Int; V::Int; H::Int; nh::Int; hd::Int; I::Int
    Hc::Int; Lc::Int; nl::Int; hmax::Int; pos::Int; nsteps::Int
    eps::F32; c707::F32; escale::F32
    emb_tok::Vector{F32}
    emb_pos::Vector{F32}
    cos::Vector{F32}
    sin::Vector{F32}
    lm::Vector{F32}
    qw::Vector{F32}
    qb::Vector{F32}
    hinit::Vector{F32}
    linit::Vector{F32}
    layers::Vector{Layer}
    swap_order::Bool                 # control n1 (default false)
end

function getrec(d, name, tag)
    haskey(d, name) || error(string("bundle: missing record ", name))
    r = d[name]
    r.tag == tag || error(string("bundle: wrong type for ", name))
    return r
end
getf(d, name) = getrec(d, name, TAG_F32).f
geti(d, name) = getrec(d, name, TAG_I32).i

"Model from bundle records. Every f32 value is checked finite (spec §1 r2)."
function Model(recs::Vector{Rec}; swap_order::Bool=false)
    for r in recs
        r.tag == TAG_F32 && !all(isfinite, r.f) && error(string("bundle: non-finite value in ", r.name))
    end
    d = recdict(recs)
    c = geti(d, "cfg")
    length(c) == 13 || error("bundle: cfg length")
    B, S, V, H, nh, I, Hc, Lc, nl, hmax, pos, pel, nsteps = Int.(c)
    pel == 0 || error("bundle: puzzle_emb_len must be 0")
    k = getf(d, "const")
    length(k) == 3 || error("bundle: const length")
    hd = H ÷ nh
    layers = Layer[]
    for l in 0:nl-1
        p = string("inner.L_level.layers.", l)
        push!(layers, Layer(getf(d, p * ".self_attn.qkv_proj.weight"), getf(d, p * ".self_attn.o_proj.weight"),
                            getf(d, p * ".mlp.gate_up_proj.weight"), getf(d, p * ".mlp.down_proj.weight")))
    end
    epos = pos == 2 ? getf(d, "inner.embed_pos.embedding_weight") : F32[]
    cs = pos == 1 ? getf(d, "rope.cos") : F32[]
    sn = pos == 1 ? getf(d, "rope.sin") : F32[]
    return Model(B, S, V, H, nh, hd, I, Hc, Lc, nl, hmax, pos, nsteps, k[1], k[2], k[3],
                 getf(d, "inner.embed_tokens.embedding_weight"), epos, cs, sn, getf(d, "inner.lm_head.weight"),
                 getf(d, "inner.q_head.weight"), getf(d, "inner.q_head.bias"), getf(d, "inner.H_init"),
                 getf(d, "inner.L_init"), layers, swap_order)
end

"y[r,o] = sum_i x[r,i]*W[o,i] (+ b[o]); acc from +0, i increasing."
function linear(x::Vector{F32}, rows::Int, nin::Int, W::Vector{F32}, nout::Int, b::Union{Nothing,Vector{F32}}=nothing)
    y = Vector{F32}(undef, rows * nout)
    @inbounds for r in 0:rows-1, o in 0:nout-1
        acc = F32(0)
        xo = r * nin
        wo = o * nin
        for i in 0:nin-1
            acc = acc + x[xo+i+1] * W[wo+i+1]
        end
        if b !== nothing
            acc = acc + b[o+1]
        end
        y[r*nout+o+1] = acc
    end
    return y
end

function rms_norm(x::Vector{F32}, rows::Int, H::Int, eps::F32)
    y = Vector{F32}(undef, rows * H)
    fh = F32(H)
    @inbounds for r in 0:rows-1
        s = F32(0)
        for k in 0:H-1
            v = x[r*H+k+1]
            s = s + v * v
        end
        v = s / fh
        inv = F32(1) / sqrt(v + eps)
        for k in 0:H-1
            y[r*H+k+1] = x[r*H+k+1] * inv
        end
    end
    return y
end

function vadd(a::Vector{F32}, b::Vector{F32})
    length(a) == length(b) || error("vadd length")
    y = similar(a)
    @inbounds for j in eachindex(a)
        y[j] = a[j] + b[j]
    end
    return y
end

silu(x::F32) = x * (F32(1) / (F32(1) + exp_det(-x)))

function attention(m::Model, L::Layer, h::Vector{F32})
    B, S, H, nh, hd = m.B, m.S, m.H, m.nh, m.hd
    qkv = linear(h, B * S, H, L.wqkv, 3H)
    half = hd ÷ 2
    n = B * nh * S * hd
    q = Vector{F32}(undef, n); k = Vector{F32}(undef, n); v = Vector{F32}(undef, n)
    @inbounds for b in 0:B-1, hh in 0:nh-1, s in 0:S-1, d in 0:hd-1
        base = (b * S + s) * 3H
        dst = ((b * nh + hh) * S + s) * hd + d + 1
        q[dst] = qkv[base+hh*hd+d+1]
        k[dst] = qkv[base+(nh+hh)*hd+d+1]
        v[dst] = qkv[base+(2nh+hh)*hd+d+1]
    end
    if m.pos == 1
        q = rope(m, q); k = rope(m, k)
    end
    scale = F32(1) / sqrt(F32(hd))
    out = Vector{F32}(undef, B * S * H)
    sc = Vector{F32}(undef, S)
    @inbounds for b in 0:B-1, hh in 0:nh-1
        hb = (b * nh + hh) * S
        for i in 0:S-1
            for j in 0:S-1
                acc = F32(0)
                for d in 0:hd-1
                    acc = acc + q[(hb+i)*hd+d+1] * k[(hb+j)*hd+d+1]
                end
                sc[j+1] = acc * scale
            end
            mx = sc[1]
            for j in 1:S-1
                if sc[j+1] > mx
                    mx = sc[j+1]
                end
            end
            for j in 0:S-1
                sc[j+1] = exp_det(sc[j+1] - mx)
            end
            z = F32(0)
            for j in 0:S-1
                z = z + sc[j+1]
            end
            for j in 0:S-1
                sc[j+1] = sc[j+1] / z
            end
            for d in 0:hd-1
                acc = F32(0)
                for j in 0:S-1
                    acc = acc + sc[j+1] * v[(hb+j)*hd+d+1]
                end
                out[(b*S+i)*H+hh*hd+d+1] = acc
            end
        end
    end
    return linear(out, B * S, H, L.wo, H)
end

"qe = q*cos + rot(q)*sin per (b, head, s, d); tables are (S, hd) row-major."
function rope(m::Model, q::Vector{F32})
    hd, S = m.hd, m.S
    half = hd ÷ 2
    y = similar(q)
    nrow = length(q) ÷ hd
    @inbounds for row in 0:nrow-1
        s = row % S
        for d in 0:hd-1
            x = q[row*hd+d+1]
            rh = d < half ? -q[row*hd+d+half+1] : q[row*hd+d-half+1]
            c = m.cos[s*hd+d+1]
            sn = m.sin[s*hd+d+1]
            a = x * c
            bb = rh * sn
            y[row*hd+d+1] = a + bb
        end
    end
    return y
end

function swiglu(m::Model, L::Layer, x::Vector{F32})
    rows = m.B * m.S
    I = m.I
    g = linear(x, rows, m.H, L.wgu, 2I)
    a = Vector{F32}(undef, rows * I)
    @inbounds for r in 0:rows-1, j in 0:I-1
        a[r*I+j+1] = silu(g[r*2I+j+1]) * g[r*2I+I+j+1]
    end
    return linear(a, rows, I, L.wdown, m.H)
end

"Block parts (for the first-block intermediates of gate G-i)."
function block_parts(m::Model, L::Layer, h::Vector{F32})
    rows = m.B * m.S
    t = attention(m, L, h)
    hs = rms_norm(vadd(h, t), rows, m.H, m.eps)
    mo = swiglu(m, L, hs)
    out = rms_norm(vadd(hs, mo), rows, m.H, m.eps)
    return (first_op_out = t, norm1_out = hs, mlp_out = mo, norm2_out = out)
end
block(m::Model, L::Layer, h::Vector{F32}) = block_parts(m, L, h).norm2_out

function l_level(m::Model, z::Vector{F32}, inj::Vector{F32})
    h = vadd(z, inj)
    for L in m.layers
        h = block(m, L, h)
    end
    return h
end

function input_embeddings(m::Model, tokens::Vector{Int32})
    B, S, H = m.B, m.S, m.H
    e = Vector{F32}(undef, B * S * H)
    @inbounds for b in 0:B-1, s in 0:S-1
        t = Int(tokens[b*S+s+1])
        0 <= t < m.V || error("token out of range")
        for k in 0:H-1
            x = m.emb_tok[t*H+k+1]
            if m.pos == 2
                x = m.c707 * (x + m.emb_pos[s*H+k+1])
            end
            e[(b*S+s)*H+k+1] = m.escale * x
        end
    end
    return e
end

function h_round(m::Model, zH::Vector{F32}, zL::Vector{F32}, emb::Vector{F32})
    if m.swap_order
        zH = l_level(m, zH, zL)
        for _ in 1:m.Lc
            zL = l_level(m, zL, vadd(zH, emb))
        end
        return zH, zL
    end
    for _ in 1:m.Lc
        zL = l_level(m, zL, vadd(zH, emb))
    end
    zH = l_level(m, zH, zL)
    return zH, zL
end

mutable struct Carry
    zH::Vector{F32}
    zL::Vector{F32}
    steps::Vector{Int32}
    halted::Vector{Bool}
    cd_inputs::Vector{Int32}
    cd_pid::Vector{Int32}
end
copycarry(c::Carry) = Carry(copy(c.zH), copy(c.zL), copy(c.steps), copy(c.halted), copy(c.cd_inputs), copy(c.cd_pid))

function initial_carry(m::Model)
    n = m.B * m.S * m.H
    return Carry(zeros(F32, n), zeros(F32, n), zeros(Int32, m.B), fill(true, m.B), zeros(Int32, m.B * m.S), zeros(Int32, m.B))
end

"ACT reset: halted rows get H_init/L_init, steps 0, current_data from the batch."
function act_reset(m::Model, c::Carry, inputs::Vector{Int32}, pid::Vector{Int32})
    r = copycarry(c)
    S, H = m.S, m.H
    for b in 0:m.B-1
        c.halted[b+1] || continue
        for s in 0:S-1, k in 0:H-1
            r.zH[(b*S+s)*H+k+1] = m.hinit[k+1]
            r.zL[(b*S+s)*H+k+1] = m.linit[k+1]
        end
        r.steps[b+1] = 0
        for s in 0:S-1
            r.cd_inputs[b*S+s+1] = inputs[b*S+s+1]
        end
        r.cd_pid[b+1] = pid[b+1]
    end
    return r
end

function outputs_from_z(m::Model, zH::Vector{F32})
    B, S, H = m.B, m.S, m.H
    logits = linear(zH, B * S, H, m.lm, m.V)
    x0 = Vector{F32}(undef, B * H)
    for b in 0:B-1, k in 0:H-1
        x0[b*H+k+1] = zH[(b*S)*H+k+1]
    end
    q = linear(x0, B, H, m.qw, 2, m.qb)
    return logits, F32[q[2b+1] for b in 0:B-1], F32[q[2b+2] for b in 0:B-1]
end

function act_step(m::Model, c::Carry, inputs::Vector{Int32}, pid::Vector{Int32})
    r = act_reset(m, c, inputs, pid)
    emb = input_embeddings(m, r.cd_inputs)
    zH, zL = r.zH, r.zL
    for _ in 1:m.Hc
        zH, zL = h_round(m, zH, zL, emb)
    end
    logits, qh, qc = outputs_from_z(m, zH)
    steps = Int32[r.steps[b] + Int32(1) for b in 1:m.B]
    halted = Bool[steps[b] >= m.hmax for b in 1:m.B]
    return Carry(zH, zL, steps, halted, r.cd_inputs, r.cd_pid), (logits = logits, q_halt = qh, q_continue = qc)
end

batch_of(d, k::Integer) = (geti(d, string("x", k, ".inputs")), geti(d, string("x", k, ".pid")))

"Records of one case in the fixed order of spec §2."
function case_recs(m::Model, case::String, c::Carry, o)
    B, S, H, V = m.B, m.S, m.H, m.V
    return Rec[RecF(case * ".logits", (B, S, V), o.logits), RecF(case * ".q_halt", (B,), o.q_halt),
               RecF(case * ".q_continue", (B,), o.q_continue), RecF(case * ".z_H", (B, S, H), c.zH),
               RecF(case * ".z_L", (B, S, H), c.zL), RecI(case * ".steps", (B,), c.steps),
               RecI(case * ".halted", (B,), Int32.(c.halted)), RecI(case * ".cd_inputs", (B, S), c.cd_inputs),
               RecI(case * ".cd_pid", (B,), c.cd_pid)]
end

"Full run (steps 1..n_steps from the initial carry, then mixed). Returns (records, carries, outputs)."
function run_bundle(m::Model, recs::Vector{Rec})
    d = recdict(recs)
    sin_ = geti(d, "steps.input")
    length(sin_) == m.nsteps || error("steps.input length")
    out = Rec[]
    carries, outs = Carry[], Any[]
    c = initial_carry(m)
    c1 = nothing
    for k in 1:m.nsteps
        inp, pid = batch_of(d, sin_[k])
        c, o = act_step(m, c, inp, pid)
        k == 1 && (c1 = copycarry(c))
        append!(out, case_recs(m, string("step", k), c, o))
        push!(carries, copycarry(c)); push!(outs, o)
    end
    mc = copycarry(c1)
    sh = geti(d, "mixed.start_halted")
    mc.halted = Bool[x != 0 for x in sh]
    inp, pid = batch_of(d, geti(d, "mixed.input")[1])
    c, o = act_step(m, mc, inp, pid)
    append!(out, case_recs(m, "mixed", c, o))
    push!(carries, copycarry(c)); push!(outs, o)
    return out, carries, outs
end

"First-block intermediates and h_round ends of step 1 (for gate G-i, W1)."
function step1_intermediates(m::Model, recs::Vector{Rec})
    d = recdict(recs)
    inp, pid = batch_of(d, geti(d, "steps.input")[1])
    r = act_reset(m, initial_carry(m), inp, pid)
    emb = input_embeddings(m, r.cd_inputs)
    hin = vadd(r.zL, vadd(r.zH, emb))
    bp = block_parts(m, m.layers[1], hin)
    ends = Tuple{Vector{F32},Vector{F32}}[]
    zH, zL = r.zH, r.zL
    for _ in 1:m.Hc
        zH, zL = h_round(m, zH, zL, emb)
        push!(ends, (copy(zH), copy(zL)))
    end
    return (input_embeddings = emb, reset_z_H = r.zH, reset_z_L = r.zL, block_input_h = hin,
            block_first_op_out = bp.first_op_out, block_norm1_out = bp.norm1_out, block_mlp_out = bp.mlp_out,
            block_norm2_out = bp.norm2_out, h_round_end = ends)
end

"Expected output layout (spec §2): names, tags and dims from the bundle cfg."
function expected_layout(recs::Vector{Rec})
    c = geti(recdict(recs), "cfg")
    B, S, V, H = Int(c[1]), Int(c[2]), Int(c[3]), Int(c[4])
    lay = Tuple{String,UInt8,Vector{Int}}[]
    for case in ("step1", "step2", "step3", "step4", "mixed")
        push!(lay, (case * ".logits", TAG_F32, [B, S, V]), (case * ".q_halt", TAG_F32, [B]),
              (case * ".q_continue", TAG_F32, [B]), (case * ".z_H", TAG_F32, [B, S, H]), (case * ".z_L", TAG_F32, [B, S, H]),
              (case * ".steps", TAG_I32, [B]), (case * ".halted", TAG_I32, [B]), (case * ".cd_inputs", TAG_I32, [B, S]),
              (case * ".cd_pid", TAG_I32, [B]))
    end
    return lay
end

"flat row-major -> Julia array of the official shape (for comparison with TrmPort / fixtures)."
to_jl(v::AbstractVector, dims) = length(dims) == 1 ? collect(v) :
    permutedims(reshape(collect(v), reverse(Tuple(dims))...), length(dims):-1:1)
"Julia array of the official shape -> flat row-major."
to_rm(a::AbstractArray) = ndims(a) == 1 ? collect(vec(a)) : vec(permutedims(a, ndims(a):-1:1))

end # module
