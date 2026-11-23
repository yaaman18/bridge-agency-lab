# S64 C0: the seq_len = 47 TRM (config a, and the 1x1 control) trained in pure Julia (spec discussion/specs/S64-c0-trm-openloop.md
# r3 §1.2, §3). The forward is the official eval forward as ported in ../trm/TrmPort.jl (post-norm blocks, RoPE, SwiGLU;
# per H round z_L <- L(z_L, z_H + e) L_cycles times, then z_H <- L(z_H, z_L)). Training follows §3.1 items 5-9: in each ACT step
# the first H_cycles - 1 rounds run without gradient and the last round with it, z is detached between steps, the losses of the
# halt_max_steps steps are averaged and one AdamATan2 update is made; ê's loss reaches e_head only (stop-gradient at z_H).
# Layout: features down the rows, examples across the columns (column n = s + S (b - 1), s the 1-based position, b the example).
# Matrix products are BLAS GEMM (single BLAS thread, set by the caller). Generic in the element type: Float32 for training and
# evaluation, Float64 for gate G2. No change to TrmPort, TrmDet or rust/.
module TrmC0

using LinearAlgebra

const S = 47; const V = 12; const H = 32; const NH = 4; const HD = 8; const IM = 256; const NL = 2
const QCOL = (46, 47)          # the question positions 45 (Q1) and 46 (Q2), 0-based, as 1-based columns
const ROW8 = 9; const ROW7 = 8 # lm_head rows of the tokens 8 (<あり>) and 7 (<なし>)
const RMS_EPS = 1e-5

struct Cfg; Hc::Int; Lc::Int; hmax::Int; end
const CFG_TRM = Cfg(3, 6, 3)
const CFG_1X1 = Cfg(1, 1, 1)

# negative-control hook for G2(a): :sign flips the sign of the correction term in the RMS-norm backward
const MUT = Ref(:none)

# ---------------- parameters ----------------
mutable struct Params{T}
    emb::Matrix{T}                # (H, V): column t + 1 = the official embed_tokens row of token t
    wqkv::Vector{Matrix{T}}       # (3H, H), the official (out, in)
    wo::Vector{Matrix{T}}         # (H, H)
    wgu::Vector{Matrix{T}}        # (2 IM, H)
    wd::Vector{Matrix{T}}         # (H, IM)
    lm::Matrix{T}                 # (V, H)
    ew::Matrix{T}                 # (1, H)   e_head weight
    eb::Vector{T}                 # (1,)     e_head bias
    hinit::Vector{T}; linit::Vector{T}
end
Params{T}() where {T} = Params{T}(zeros(T, H, V), [zeros(T, 3H, H) for _ in 1:NL], [zeros(T, H, H) for _ in 1:NL],
                                  [zeros(T, 2IM, H) for _ in 1:NL], [zeros(T, H, IM) for _ in 1:NL], zeros(T, V, H),
                                  zeros(T, 1, H), zeros(T, 1), zeros(T, H), zeros(T, H))
plist(p::Params) = Any[p.emb, p.wqkv[1], p.wo[1], p.wgu[1], p.wd[1], p.wqkv[2], p.wo[2], p.wgu[2], p.wd[2], p.lm, p.ew, p.eb, p.hinit, p.linit]
const PNAMES = ["embed_tokens", "L0.qkv_proj", "L0.o_proj", "L0.gate_up_proj", "L0.down_proj",
                "L1.qkv_proj", "L1.o_proj", "L1.gate_up_proj", "L1.down_proj", "lm_head", "e_head.weight", "e_head.bias", "H_init", "L_init"]
const PDECAY = [true, true, true, true, true, true, true, true, true, true, true, false, false, false]   # 2-D weights only
const BODY = 1:10   # embed, the blocks, lm_head (what G2(b) requires bit-identical)
function convert_params(::Type{T}, p::Params) where {T}
    q = Params{T}()
    for (a, b) in zip(plist(q), plist(p)); a .= T.(b); end
    return q
end
copy_params(p::Params{T}) where {T} = convert_params(T, p)
zero_params!(p::Params) = (for a in plist(p); fill!(a, 0); end; p)
param_bytes(p::Params{Float32}) = reduce(vcat, [reinterpret(UInt8, htol.(vec(copy(a)))) for a in plist(p)])

# truncated normal on [-2σ, 2σ]: Box-Muller from two uniforms (one normal per pair), rejected outside |z| <= 2
function tnorm(r, n, σ)
    out = Vector{Float64}(undef, n); i = 0
    while i < n
        u1 = r(); u2 = r()
        z = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2)
        abs(z) <= 2.0 || continue
        i += 1; out[i] = σ * z
    end
    return out
end
# fill an official (out, in) matrix from values in the official row-major order (in fastest)
function fill_rm!(W::AbstractMatrix, vals)
    no, ni = size(W)
    for o in 1:no, i in 1:ni; W[o, i] = vals[(o-1)*ni+i]; end
    return W
end
"§3.2 initialization from the uniform stream r (Mulberry(640001)): embed_tokens, then layer 0 (qkv, o, gate_up, down) and
layer 1, then H_init and L_init, each in the official row-major order; lm_head and e_head are zero."
function init_params(r)
    p = Params{Float32}()
    E = zeros(Float64, V, H); fill_rm!(E, tnorm(r, V * H, 1 / sqrt(H))); p.emb .= Float32.(permutedims(E))
    for l in 1:NL
        for (W, din) in ((p.wqkv[l], H), (p.wo[l], H), (p.wgu[l], H), (p.wd[l], IM))
            A = zeros(Float64, size(W)); fill_rm!(A, tnorm(r, length(W), 1 / sqrt(din))); W .= Float32.(A)
        end
    end
    p.hinit .= Float32.(tnorm(r, H, 0.02)); p.linit .= Float32.(tnorm(r, H, 0.02))
    return p
end

"the official state dict (Julia arrays in the official shapes); q_head as the official init (weight 0, bias -5), unused"
function official_state(p::Params{Float32})
    d = Dict{String,Array{Float32}}()
    d["inner.embed_tokens.embedding_weight"] = Array(permutedims(p.emb))
    for l in 1:NL
        pre = "inner.L_level.layers.$(l-1)"
        d[pre*".self_attn.qkv_proj.weight"] = copy(p.wqkv[l]); d[pre*".self_attn.o_proj.weight"] = copy(p.wo[l])
        d[pre*".mlp.gate_up_proj.weight"] = copy(p.wgu[l]); d[pre*".mlp.down_proj.weight"] = copy(p.wd[l])
    end
    d["inner.lm_head.weight"] = copy(p.lm)
    d["inner.q_head.weight"] = zeros(Float32, 2, H); d["inner.q_head.bias"] = fill(-5.0f0, 2)
    d["inner.H_init"] = copy(p.hinit); d["inner.L_init"] = copy(p.linit)
    return d
end

# ---------------- work space ----------------
mutable struct BlockBuf{T}
    x::Matrix{T}; qkv::Matrix{T}; q::Array{T,4}; k::Array{T,4}; v::Array{T,4}; P::Array{T,4}; O::Array{T,4}
    o::Matrix{T}; t::Matrix{T}; r1::Vector{T}; h1::Matrix{T}; gu::Matrix{T}; a::Matrix{T}; m::Matrix{T}; r2::Vector{T}; out::Matrix{T}
end
function BlockBuf{T}(B) where {T}
    N = S * B
    return BlockBuf{T}(zeros(T, H, N), zeros(T, 3H, N), zeros(T, S, HD, NH, B), zeros(T, S, HD, NH, B), zeros(T, S, HD, NH, B),
                       zeros(T, S, S, NH, B), zeros(T, S, HD, NH, B), zeros(T, H, N), zeros(T, H, N), zeros(T, N), zeros(T, H, N),
                       zeros(T, 2IM, N), zeros(T, IM, N), zeros(T, H, N), zeros(T, N), zeros(T, H, N))
end
mutable struct Work{T}
    B::Int
    cs::Matrix{T}; sn::Matrix{T}                  # RoPE tables (S, HD)
    ng::BlockBuf{T}                               # forward without gradient
    gr::Vector{Vector{BlockBuf{T}}}               # the gradient round: (L_cycles + 1) calls x NL blocks
    emb::Matrix{T}; zH::Matrix{T}; zL::Matrix{T}; zH0::Matrix{T}; zL0::Matrix{T}; inj::Matrix{T}
    d1::Matrix{T}; d2::Matrix{T}; dh1::Matrix{T}; dgu::Matrix{T}; da::Matrix{T}; dov::Matrix{T}
    dO::Array{T,4}; dQ::Array{T,4}; dK::Array{T,4}; dV::Array{T,4}; dP::Matrix{T}; dqkv::Matrix{T}
    dzH::Matrix{T}; dzH0::Matrix{T}; dzL::Matrix{T}; dh0::Matrix{T}; demb::Matrix{T}; tmp::Matrix{T}
    gguT::Vector{Matrix{T}}                       # gate_up weight gradients accumulated transposed (H, 2 IM): OpenBLAS is
                                                  # ~40x slower on the (2 IM, H) += (2 IM, N) (N, H) shape
end
function Work{T}(B, ncalls, cs, sn) where {T}
    N = S * B; z() = zeros(T, H, N); z4() = zeros(T, S, HD, NH, B)
    gr = [[BlockBuf{T}(B) for _ in 1:NL] for _ in 1:ncalls]
    nb = ncalls > 0
    return Work{T}(B, T.(cs), T.(sn), BlockBuf{T}(B), gr, z(), z(), z(), z(), z(), z(),
                   nb ? z() : zeros(T, 0, 0), nb ? z() : zeros(T, 0, 0), nb ? z() : zeros(T, 0, 0),
                   nb ? zeros(T, 2IM, N) : zeros(T, 0, 0), nb ? zeros(T, IM, N) : zeros(T, 0, 0), nb ? z() : zeros(T, 0, 0),
                   nb ? z4() : zeros(T, 0, 0, 0, 0), nb ? z4() : zeros(T, 0, 0, 0, 0), nb ? z4() : zeros(T, 0, 0, 0, 0),
                   nb ? z4() : zeros(T, 0, 0, 0, 0), zeros(T, S, S), nb ? zeros(T, 3H, N) : zeros(T, 0, 0),
                   z(), z(), z(), z(), z(), z(), [zeros(T, nb ? H : 0, nb ? 2IM : 0) for _ in 1:NL])
end

# ---------------- forward ----------------
# exp for the Float32 training and evaluation: Cephes expf (range reduction by k = round(x log2 e), degree-6 polynomial,
# about 1 ulp), branch-free so that the loops vectorize; the argument is clamped to [-87, 88] (exp(-87) = 1.6e-38 stands
# for smaller values). Float64 (gate G2) uses Base.exp.
@inline function fexp(x::Float32)
    x = clamp(x, -87.0f0, 88.0f0)
    k = round(x * 1.44269504088896341f0)
    r = (x - k * 0.693359375f0) - k * -2.12194440f-4
    z = r * r
    y = (((((1.9875691500f-4 * r + 1.3981999507f-3) * r + 8.3334519073f-3) * r + 4.1665795894f-2) * r +
          1.6666665459f-1) * r + 5.0000001201f-1) * z + r + 1.0f0
    return y * reinterpret(Float32, (unsafe_trunc(Int32, k) + Int32(127)) << 23)
end
@inline fexp(x::Float64) = exp(x)
function rmsnorm!(y, r, a, b)
    T = eltype(y); fh = T(H); e = T(RMS_EPS)
    @inbounds for n in axes(y, 2)
        ss = zero(T)
        for k in 1:H; v = a[k, n] + b[k, n]; y[k, n] = v; ss += v * v; end
        rn = one(T) / sqrt(ss / fh + e); r[n] = rn
        for k in 1:H; y[k, n] *= rn; end
    end
    return y
end

"One block (attention, then SwiGLU, post-norm): w.x -> w.out; every intermediate kept in w."
function block_fwd!(w::BlockBuf{T}, p::Params{T}, l::Int, cs, sn) where {T}
    B = size(w.q, 4); half = HD ÷ 2
    mul!(w.qkv, p.wqkv[l], w.x)
    q4 = reshape(w.qkv, HD, 3NH, S, B)
    @inbounds for b in 1:B, h in 1:NH, d in 1:HD
        dd = d <= half ? d + half : d - half; sg = d <= half ? -one(T) : one(T)
        for s in 1:S
            c = cs[s, d]; sv = sn[s, d]
            w.q[s, d, h, b] = q4[d, h, s, b] * c + (sg * q4[dd, h, s, b]) * sv
            w.k[s, d, h, b] = q4[d, NH+h, s, b] * c + (sg * q4[dd, NH+h, s, b]) * sv
            w.v[s, d, h, b] = q4[d, 2NH+h, s, b]
        end
    end
    scale = one(T) / sqrt(T(HD))
    @inbounds for b in 1:B, h in 1:NH
        Pm = view(w.P, :, :, h, b)
        mul!(Pm, view(w.k, :, :, h, b), transpose(view(w.q, :, :, h, b)))   # Pm[j, i] = k_j . q_i
        for i in 1:S
            mx = typemin(T)
            for j in 1:S; x = Pm[j, i] * scale; Pm[j, i] = x; mx = x > mx ? x : mx; end
            @simd for j in 1:S; Pm[j, i] = fexp(Pm[j, i] - mx); end
            z = zero(T)
            @simd for j in 1:S; z += Pm[j, i]; end
            @simd for j in 1:S; Pm[j, i] = Pm[j, i] / z; end
        end
        mul!(view(w.O, :, :, h, b), transpose(Pm), view(w.v, :, :, h, b))  # O[i, d] = sum_j P[j, i] V[j, d]
    end
    o3 = reshape(w.o, HD, NH, S, B)
    @inbounds for b in 1:B, s in 1:S, h in 1:NH, d in 1:HD; o3[d, h, s, b] = w.O[s, d, h, b]; end
    mul!(w.t, p.wo[l], w.o)
    rmsnorm!(w.h1, w.r1, w.x, w.t)
    mul!(w.gu, p.wgu[l], w.h1)
    @inbounds for n in axes(w.a, 2)
        @simd for j in 1:IM
            g = w.gu[j, n]
            w.a[j, n] = (g * (one(T) / (one(T) + fexp(-g)))) * w.gu[IM+j, n]
        end
    end
    mul!(w.m, p.wd[l], w.a)
    rmsnorm!(w.out, w.r2, w.h1, w.m)
    return w.out
end

function embed!(w::Work{T}, p::Params{T}, tok::AbstractMatrix{UInt8}) where {T}
    es = sqrt(T(H)); B = w.B
    @inbounds for b in 1:B, s in 1:S
        t = Int(tok[s, b]) + 1; n = s + S * (b - 1)
        for k in 1:H; w.emb[k, n] = es * p.emb[k, t]; end
    end
end
function init_carry!(w::Work{T}, p::Params{T}) where {T}
    @inbounds for n in axes(w.zH, 2), k in 1:H; w.zH[k, n] = p.hinit[k]; w.zL[k, n] = p.linit[k]; end
end

"L_level without gradient: dst <- blocks(zin + inj) (dst may be zin)"
function llevel_ng!(dst, w::Work, p, zin, inj)
    b = w.ng
    b.x .= zin .+ inj
    for l in 1:NL
        block_fwd!(b, p, l, w.cs, w.sn)
        l < NL && copyto!(b.x, b.out)
    end
    copyto!(dst, b.out)
end
function h_round_ng!(w::Work, p, cfg::Cfg)
    for _ in 1:cfg.Lc
        w.inj .= w.zH .+ w.emb
        llevel_ng!(w.zL, w, p, w.zL, w.inj)
    end
    llevel_ng!(w.zH, w, p, w.zH, w.zL)
end
"the last round of an ACT step, every block's intermediates kept; the entry (z_H0, z_L0) is the detach point"
function round_grad_fwd!(w::Work, p, cfg::Cfg)
    copyto!(w.zH0, w.zH); copyto!(w.zL0, w.zL)
    w.inj .= w.zH0 .+ w.emb
    zin = w.zL0
    for c in 1:cfg.Lc
        bf = w.gr[c]
        bf[1].x .= zin .+ w.inj
        for l in 1:NL
            block_fwd!(bf[l], p, l, w.cs, w.sn)
            l < NL && copyto!(bf[l+1].x, bf[l].out)
        end
        zin = bf[NL].out
    end
    bf = w.gr[cfg.Lc+1]
    bf[1].x .= w.zH0 .+ zin
    for l in 1:NL
        block_fwd!(bf[l], p, l, w.cs, w.sn)
        l < NL && copyto!(bf[l+1].x, bf[l].out)
    end
    copyto!(w.zL, zin); copyto!(w.zH, bf[NL].out)
end

# ---------------- backward ----------------
function rms_bwd!(dx, y, r, dy)
    T = eltype(dx); fh = T(H); sgn = MUT[] === :sign ? -one(T) : one(T)
    @inbounds for n in axes(dx, 2)
        c = zero(T)
        for k in 1:H; c += dy[k, n] * y[k, n]; end
        c /= fh; rn = r[n]
        for k in 1:H; dx[k, n] = rn * (dy[k, n] - sgn * y[k, n] * c); end
    end
    return dx
end
"dout -> dx (no aliasing), the weight gradients of layer l added into g"
function block_bwd!(dx, w::Work{T}, c::BlockBuf{T}, p::Params{T}, g::Params{T}, l::Int, dout) where {T}
    B = w.B; half = HD ÷ 2; o1 = one(T)
    rms_bwd!(w.d2, c.out, c.r2, dout)
    mul!(g.wd[l], w.d2, transpose(c.a), o1, o1)
    mul!(w.da, transpose(p.wd[l]), w.d2)
    @inbounds for n in axes(w.da, 2)
        @simd for j in 1:IM
            gg = c.gu[j, n]; uu = c.gu[IM+j, n]
            sg = o1 / (o1 + fexp(-gg)); sl = gg * sg; dav = w.da[j, n]
            w.dgu[j, n] = dav * uu * (sg * (o1 + gg * (o1 - sg)))
            w.dgu[IM+j, n] = dav * sl
        end
    end
    mul!(w.gguT[l], c.h1, transpose(w.dgu), o1, o1)
    mul!(w.dh1, transpose(p.wgu[l]), w.dgu)
    w.dh1 .+= w.d2
    rms_bwd!(w.d1, c.h1, c.r1, w.dh1)
    mul!(g.wo[l], w.d1, transpose(c.o), o1, o1)
    mul!(w.dov, transpose(p.wo[l]), w.d1)
    o3 = reshape(w.dov, HD, NH, S, B)
    @inbounds for b in 1:B, h in 1:NH, d in 1:HD, s in 1:S; w.dO[s, d, h, b] = o3[d, h, s, b]; end
    scale = o1 / sqrt(T(HD))
    @inbounds for b in 1:B, h in 1:NH
        Pm = view(c.P, :, :, h, b); dOm = view(w.dO, :, :, h, b)
        mul!(view(w.dV, :, :, h, b), Pm, dOm)                     # dV[j, d] = sum_i P[j, i] dO[i, d]
        mul!(w.dP, view(c.v, :, :, h, b), transpose(dOm))        # dP[j, i] = v_j . dO_i
        for i in 1:S
            cc = zero(T)
            for j in 1:S; cc += Pm[j, i] * w.dP[j, i]; end
            for j in 1:S; w.dP[j, i] = Pm[j, i] * (w.dP[j, i] - cc); end
        end
        mul!(view(w.dQ, :, :, h, b), transpose(w.dP), view(c.k, :, :, h, b), scale, zero(T))   # dQ[i, d] = sc sum_j dA[j, i] K[j, d]
        mul!(view(w.dK, :, :, h, b), w.dP, view(c.q, :, :, h, b), scale, zero(T))              # dK[j, d] = sc sum_i dA[j, i] Q[i, d]
    end
    q4 = reshape(w.dqkv, HD, 3NH, S, B)
    @inbounds for b in 1:B, h in 1:NH, d in 1:HD
        for s in 1:S
            cv = w.cs[s, d]
            if d <= half
                s2 = w.sn[s, d+half]
                q4[d, h, s, b] = cv * w.dQ[s, d, h, b] + s2 * w.dQ[s, d+half, h, b]
                q4[d, NH+h, s, b] = cv * w.dK[s, d, h, b] + s2 * w.dK[s, d+half, h, b]
            else
                s2 = w.sn[s, d-half]
                q4[d, h, s, b] = cv * w.dQ[s, d, h, b] - s2 * w.dQ[s, d-half, h, b]
                q4[d, NH+h, s, b] = cv * w.dK[s, d, h, b] - s2 * w.dK[s, d-half, h, b]
            end
            q4[d, 2NH+h, s, b] = w.dV[s, d, h, b]
        end
    end
    mul!(g.wqkv[l], w.dqkv, transpose(c.x), o1, o1)
    mul!(dx, transpose(p.wqkv[l]), w.dqkv)
    dx .+= w.d1
    return dx
end
function call_bwd!(dres, w::Work, p, g, bf, dout)
    block_bwd!(w.tmp, w, bf[2], p, g, 2, dout)
    block_bwd!(dres, w, bf[1], p, g, 1, w.tmp)
end
"w.dzH (gradient at the round's z_H output) -> w.dzH0, w.dzL (= d z_L0); w.demb accumulated"
function round_bwd!(w::Work, p, g, cfg::Cfg)
    call_bwd!(w.dzL, w, p, g, w.gr[cfg.Lc+1], w.dzH)
    copyto!(w.dzH0, w.dzL)
    for c in cfg.Lc:-1:1
        call_bwd!(w.dh0, w, p, g, w.gr[c], w.dzL)
        w.dzH0 .+= w.dh0; w.demb .+= w.dh0
        copyto!(w.dzL, w.dh0)
    end
end

# ---------------- the two-word stablemax head (§1.2) ----------------
smx(x::Float64) = x >= 0 ? x + 1.0 : 1.0 / (1.0 - x)
dsmx(x::Float64) = x >= 0 ? 1.0 : 1.0 / ((1.0 - x) * (1.0 - x))
p2(l8::Float64, l7::Float64) = (a = smx(l8); a / (a + smx(l7)))
"loss -log p(Y) with p = s(l8) / (s(l8) + s(l7)); returns (loss, dL/dl8, dL/dl7, p)"
function lmloss(l8::Float64, l7::Float64, y::Bool)
    s8 = smx(l8); s7 = smx(l7); z = s8 + s7
    L = y ? -log(s8 / z) : -log(s7 / z)
    g8 = ((y ? -1.0 / s8 : 0.0) + 1.0 / z) * dsmx(l8)
    g7 = ((y ? 0.0 : -1.0 / s7) + 1.0 / z) * dsmx(l7)
    return L, g8, g7, s8 / z
end
sigm(x::Float64) = 1.0 / (1.0 + exp(-x))
@inline function dotcol(W, row, Z, col)
    T = eltype(Z); acc = zero(T)
    @inbounds for k in 1:H; acc += W[row, k] * Z[k, col]; end
    return acc
end

# ---------------- gradient of one batch ----------------
"Records of one gradient pass, for G2(a): per ACT step the detach point, ê's target and z_H at the question columns."
struct GradRec{T}; zH0::Vector{Matrix{T}}; zL0::Vector{Matrix{T}}; et::Vector{Vector{Bool}}; zq::Vector{Matrix{T}}; end
GradRec{T}() where {T} = GradRec{T}(Matrix{T}[], Matrix{T}[], Vector{Bool}[], Matrix{T}[])

"""work spaces by column count (the distinct inputs of a batch are run in the smallest size that holds them)"""
struct WorkSet{T}; ncalls::Int; cs::Matrix{T}; sn::Matrix{T}; w::Dict{Int,Work{T}}; end
WorkSet{T}(ncalls, cs, sn) where {T} = WorkSet{T}(ncalls, T.(cs), T.(sn), Dict{Int,Work{T}}())
getwork!(W::WorkSet{T}, n) where {T} = get!(() -> Work{T}(n, W.ncalls, W.cs, W.sn), W.w, n)
const SIZES = (16, 32, 48, 64)

"""g <- d(loss)/d(params) for the batch (tok (S, B), act in {1, 2}, Y); returns (mean lm loss, mean ê loss) over steps and batch.
With a WorkSet, each distinct input of the batch is one column (the forward and backward of identical inputs are identical;
the heads' gradients of all its examples are added on that column) and the columns are padded, with no loss, to a size of
SIZES; with a Work, every example is its own column (G2(a), and G2(d)'s reference)."""
function grad!(g::Params{T}, p::Params{T}, W, cfg::Cfg, tok, act, Y; ce = 1.0, rec = nothing) where {T}
    Bt = size(tok, 2)
    zero_params!(g)
    if W isa Work
        W.B == Bt || error("grad!: batch $Bt != work $(W.B)")
        w = W; tokc = tok; cols = [[b] for b in 1:Bt]
    else
        ids = Dict{Vector{UInt8},Int}(); uniq = Int[]; cols = Vector{Int}[]
        for b in 1:Bt
            k = tok[:, b]; j = get(ids, k, 0)
            if j == 0; push!(uniq, b); push!(cols, Int[]); j = length(uniq); ids[k] = j; end
            push!(cols[j], b)
        end
        nb = SIZES[findfirst(>=(length(uniq)), SIZES)]
        while length(uniq) < nb; push!(uniq, uniq[end]); push!(cols, Int[]); end
        w = getwork!(W, nb); tokc = tok[:, uniq]
    end
    for a in w.gguT; fill!(a, 0); end
    ws = 1.0 / (cfg.hmax * Bt)
    Llm, Le = grad_chunk!(g, p, w, cfg, tokc, cols, act, Y, ws, ce, rec)
    for l in 1:NL; g.wgu[l] .+= transpose(w.gguT[l]); end
    return Llm, Le
end
function grad_chunk!(g::Params{T}, p::Params{T}, w::Work{T}, cfg::Cfg, tok, cols, act, Y, ws, ce, rec) where {T}
    B = w.B; nex = length(act)
    embed!(w, p, tok); init_carry!(w, p); fill!(w.demb, 0)
    Llm = 0.0; Le = 0.0
    for k in 1:cfg.hmax
        for _ in 1:cfg.Hc-1; h_round_ng!(w, p, cfg); end
        round_grad_fwd!(w, p, cfg)
        fill!(w.dzH, 0)
        ets = Vector{Bool}(undef, nex); zq = zeros(T, H, nex)
        @inbounds for b in 1:B, i in cols[b]
            col = (b - 1) * S + QCOL[act[i]]
            l8 = Float64(dotcol(p.lm, ROW8, w.zH, col)); l7 = Float64(dotcol(p.lm, ROW7, w.zH, col))
            L, g8, g7, pa = lmloss(l8, l7, Y[i])
            Llm += L * ws
            G8 = T(g8 * ws); G7 = T(g7 * ws)
            for j in 1:H
                z = w.zH[j, col]; zq[j, i] = z
                g.lm[ROW8, j] += G8 * z; g.lm[ROW7, j] += G7 * z
                w.dzH[j, col] += G8 * p.lm[ROW8, j] + G7 * p.lm[ROW7, j]
            end
            # ê: its loss reaches e_head only (z_H is read, not differentiated)
            el = Float64(dotcol(p.ew, 1, w.zH, col) + p.eb[1]); e = sigm(el)
            et = (pa >= 0.5) != Y[i]; ets[i] = et
            Le += -(et ? log(e) : log(1.0 - e)) * ws
            ge = T((e - (et ? 1.0 : 0.0)) * ce * ws)
            for j in 1:H; g.ew[1, j] += ge * w.zH[j, col]; end
            g.eb[1] += ge
        end
        if rec !== nothing
            push!(rec.zH0, copy(w.zH0)); push!(rec.zL0, copy(w.zL0)); push!(rec.et, ets); push!(rec.zq, zq)
        end
        round_bwd!(w, p, g, cfg)
        if cfg.Hc == 1 && k == 1   # the round's entry is H_init, L_init themselves
            @inbounds for n in axes(w.dzH0, 2), j in 1:H; g.hinit[j] += w.dzH0[j, n]; g.linit[j] += w.dzL[j, n]; end
        end
    end
    es = sqrt(T(H))
    @inbounds for b in 1:B, s in 1:S
        t = Int(tok[s, b]) + 1; n = s + S * (b - 1)
        for j in 1:H; g.emb[j, t] += es * w.demb[j, n]; end
    end
    return Llm, Le
end

"G2(a): the loss as a function of the parameters with every detach point, ê's target and ê's z_H fixed at the recorded values
(the entry of the 1x1's only round is H_init, L_init of p themselves)."
function loss_fixed(p::Params{T}, w::Work{T}, cfg::Cfg, tok, act, Y, rec::GradRec{T}; ce = 1.0) where {T}
    B = w.B; size(tok, 2) == B || error("loss_fixed: one chunk only")
    embed!(w, p, tok)
    ws = 1.0 / (cfg.hmax * B); L = 0.0
    for k in 1:cfg.hmax
        if cfg.Hc == 1 && k == 1
            init_carry!(w, p)
        else
            copyto!(w.zH, rec.zH0[k]); copyto!(w.zL, rec.zL0[k])
        end
        h_round_ng!(w, p, cfg)
        @inbounds for b in 1:B
            col = (b - 1) * S + QCOL[act[b]]
            l8 = Float64(dotcol(p.lm, ROW8, w.zH, col)); l7 = Float64(dotcol(p.lm, ROW7, w.zH, col))
            L += lmloss(l8, l7, Y[b])[1] * ws
            el = Float64(dotcol(p.ew, 1, rec.zq[k], b) + p.eb[1]); e = sigm(el); et = rec.et[k][b]
            L += ce * -(et ? log(e) : log(1.0 - e)) * ws
        end
    end
    return L
end

# ---------------- AdamATan2 (§3.2) ----------------
mutable struct Opt{T}; m::Vector{Array{T}}; v::Vector{Array{T}}; t::Int; end
Opt(p::Params{T}) where {T} = Opt{T}([zero(a) for a in plist(p)], [zero(a) for a in plist(p)], 0)
lr_at(lr, t; warm = 50) = t <= warm ? lr * t / warm : lr
"one update of every array of p; wd on the 2-D weights only. bias_correct = false is G2(c)'s negative control."
function adam_step!(p::Params{T}, g::Params{T}, o::Opt{T}, lr, wd; a = 1.27, b = 1.0, b1 = 0.9, b2 = 0.95, warm = 50,
                    bias_correct = true) where {T}
    o.t += 1; t = o.t
    eta = lr_at(lr, t; warm = warm)
    bc1 = bias_correct ? T(1 - b1^t) : one(T); bc2 = bias_correct ? T(1 - b2^t) : one(T)
    B1 = T(b1); B2 = T(b2); C1 = T(1 - b1); C2 = T(1 - b2); A = T(eta * a); Bb = T(b)
    for (i, (th, gr)) in enumerate(zip(plist(p), plist(g)))
        dec = T(1 - eta * (PDECAY[i] ? wd : 0.0))
        m = o.m[i]; v = o.v[i]
        @inbounds for j in eachindex(th)
            gj = gr[j]
            m[j] = B1 * m[j] + C1 * gj
            v[j] = B2 * v[j] + C2 * gj * gj
            mh = m[j] / bc1; vh = v[j] / bc2
            th[j] = th[j] * dec - A * atan(mh, Bb * sqrt(vh))
        end
    end
end
function train_step!(p, g, o, w, cfg, tok, act, Y, lr, wd; ce = 1.0)
    L = grad!(g, p, w, cfg, tok, act, Y; ce = ce)
    adam_step!(p, g, o, lr, wd)
    return L
end

# ---------------- evaluation (no gradient) ----------------
"the final ACT step's z_H (H, S B) and z_L for the batch tok"
function final_state!(w::Work, p, cfg::Cfg, tok)
    embed!(w, p, tok); init_carry!(w, p)
    for _ in 1:cfg.hmax, _ in 1:cfg.Hc; h_round_ng!(w, p, cfg); end
    return w.zH, w.zL
end
"p_a (two-word stablemax, Float64), ê_a = σ(e_logit) for a = 1, 2 and z_H at the two question columns, for each column of tok"
function predict!(pp, ee, zq, w::Work{T}, p::Params{T}, cfg::Cfg, tok) where {T}
    size(tok, 2) == w.B || error("predict!: one chunk at a time")
    final_state!(w, p, cfg, tok)
    @inbounds for b in 1:w.B, a in 1:2
        col = (b - 1) * S + QCOL[a]
        pp[a, b] = p2(Float64(dotcol(p.lm, ROW8, w.zH, col)), Float64(dotcol(p.lm, ROW7, w.zH, col)))
        ee[a, b] = sigm(Float64(dotcol(p.ew, 1, w.zH, col) + p.eb[1]))
        for j in 1:H; zq[j, a, b] = w.zH[j, col]; end
    end
end

end # module
