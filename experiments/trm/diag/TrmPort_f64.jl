module TrmPortF64
#
# 範囲（手 2）: layers.py の全部と、trm.py の Block・ReasoningModule・_Inner の
# __init__・_input_embeddings・empty_carry・reset_carry。
# 範囲（手 3）: _Inner.forward の H/L 周回（推論では全周回を同じ式で回す）、h_round_ends、
# ACT の包み（評価モードだけ: halted = steps >= halt_max_steps）、ACTModel・Carry・
# initial_carry・act_forward。負の対照の引数は swap_update_order・q_head_pos・bad_norm_order・bad_rope_value。
# 配列は公式と同じ (batch, seq, hidden)。添字だけ 1 始まり。重みは公式と同じ (out, in)。
# 照合の手では、属性の欠けを「ない」とみなせるよう構造の欄は名前つき組(Missing)で持つ
# （継ぎ目: 次の手で木構造にするときに名前つき組を型に替える）。

module TrmPort

using JSON
using LinearAlgebra: BLAS

export LayerConfig, CastedLinear, CastedEmbedding, RotaryEmbedding, Attention, SwiGLU, Block,
       ReasoningModule, Inner, rms_norm, rotate_half, apply_rotary_pos_emb, load_fixture, Float64,
       input_embeddings, reset_carry, norm1, first_op, mlp_fn, silu, swiglu_inter,
       ACTModel, Carry, initial_carry, act_forward, inner_forward, h_round_ends

const Float64 = Float64

_missing(name::Symbol, fields::Vector{Any}) = (names = fields, values = name)

"公式の省略時の値（TinyRecursiveReasoningModel_ACTV1Config の既定）。fixtures の config に書かれていない欄にだけ使う。"
const CONFIG_DEFAULTS = Dict{Symbol,Any}(:rms_norm_eps => 1e-5, :rope_theta => 10000.0, :puzzle_emb_len => 16, :mlp_t => false, :puzzle_emb_ndim => 0)

function _default(name::Symbol)
    haskey(CONFIG_DEFAULTS, name) || error(string("config field missing: ", name))
    return CONFIG_DEFAULTS[name]
end

function _getattr(cfg, name::Symbol)
    if cfg isa NamedTuple && haskey(cfg, :names)
        i = findfirst(==(name), cfg.names)
        i === nothing && return _default(name)
        return cfg.values[i]
    else
        haskey(cfg, name) || return _default(name)
        return getproperty(cfg, name)
    end
end

_find_multiple(a, b) = cld(a, b) * b

# ---- layers.py ----

"rotate_half: 指定軸（既定は最後）の前半を後半と入れ替え、前半に負号。"
function rotate_half(x::AbstractArray{T}; dim::Int=ndims(x)) where {T}
    d = size(x, dim)
    h = d ÷ 2
    sz = ntuple(i -> size(x, i), ndims(x))
    y = similar(x)
    for I in CartesianIndices(sz)
        j = I[dim]
        J = CartesianIndex(Base.setindex(Tuple(I), mod1(j + h, d), dim))
        y[I] = j <= h ? -x[J] : x[J]
    end
    return y
end

"apply_rotary_pos_emb: q, k: (bs, seq, hd, heads)、cos, sin: (seq, hd) を頭の軸へ広げる。"
function apply_rotary_pos_emb(q::AbstractArray{T}, k::AbstractArray{T}, cos::AbstractMatrix, sin::AbstractMatrix) where {T}
    c = reshape(cos, 1, size(cos, 1), size(cos, 2), 1)
    s = reshape(sin, 1, size(sin, 1), size(sin, 2), 1)
    # 内部の (bs, seq, hd, heads) では公式の最後の特徴軸が第 3 軸。
    qe = (q .* c) .+ (rotate_half(q; dim=3) .* s)
    ke = (k .* c) .+ (rotate_half(k; dim=3) .* s)
    return qe, ke
end

"CastedLinear: W は (out, in)。y = x * W'（公式の F.linear）。"
struct CastedLinear
    weight::Matrix{Float64}
    bias::Union{Nothing,Vector{Float64}}
end
CastedLinear(w, bias=nothing) = CastedLinear(Array{Float64,2}(ndims(w) == 2 ? w : reshape(w, 1, :)),
                                            bias === nothing ? nothing : vec(Array{Float64}(bias)))

function (l::CastedLinear)(x::AbstractArray{Float64,3})
    b, s, i = size(x)
    @assert i == size(l.weight, 2) "CastedLinear input $i != $(size(l.weight, 2))"
    # 列優先の先頭 2 軸をまとめ、各 (batch, seq) の特徴を一行として保つ。
    y = reshape(x, b * s, i) * transpose(l.weight) # (b*s, out)
    y = reshape(y, b, s, size(l.weight, 1))
    if l.bias !== nothing
        y = y .+ reshape(l.bias, 1, 1, :)
    end
    return y
end
(l::CastedLinear)(x::AbstractMatrix{Float64}) = reshape(l(reshape(x, size(x, 1), 1, size(x, 2))), size(x, 1), :)
(l::CastedLinear)(x::AbstractVector{Float64}) = vec(l(reshape(x, length(x), 1, 1)))

"""CastedEmbedding: 表を (num_embeddings, embedding_dim) で持つ（torch と同じ形）。
forward は F.embedding(input, w) = w[input, :]：idx の形のまま後に embedding_dim を付けた形で返す
（fixtures の idx は 0 始まりなのでここで +1 する）。"""
struct CastedEmbedding
    embedding_weight::Matrix{Float64}
end
CastedEmbedding(w::AbstractArray) = CastedEmbedding(Array{Float64,2}(ndims(w) == 2 ? w : reshape(w, 1, :)))
CastedEmbedding(w::AbstractMatrix, init_std, cast_to) = CastedEmbedding(w)

function (e::CastedEmbedding)(idx::AbstractArray{<:Integer})
    v = vec(idx)
    w = e.embedding_weight                     # (num_embeddings, embedding_dim)
    n, d = length(v), size(w, 2)
    out = Matrix{Float64}(undef, n, d)
    for i in 1:n
        out[i, :] = view(w, Int(v[i]) + 1, :)  # fixture は 0 始まり、表は 1 始まり（行を引く）
    end
    outshape = ndims(idx) == 0 ? (d,) : (size(idx)..., d)
    return reshape(out, outshape)
end

"RotaryEmbedding: inv_freq = 1/base^(arange(0,dim,2)/dim)、emb = cat(freqs, freqs)。"
function RotaryEmbedding(dim::Integer, max_position_embeddings::Integer, base::Real)
    inv_freq = [Float64(1.0) / Float64(base)^(Float64(2k) / Float64(dim)) for k in 0:(dim ÷ 2 - 1)]
    cos_cached = Matrix{Float64}(undef, max_position_embeddings, dim)
    sin_cached = Matrix{Float64}(undef, max_position_embeddings, dim)
    for t in 0:(max_position_embeddings - 1)
        for k in 1:(dim ÷ 2)
            ang = Float64(t) * inv_freq[k]
            c = cos(ang)
            s = sin(ang)
            cos_cached[t + 1, k] = c
            cos_cached[t + 1, k + dim ÷ 2] = c
            sin_cached[t + 1, k] = s
            sin_cached[t + 1, k + dim ÷ 2] = s
        end
    end
    return cos_cached, sin_cached
end

mutable struct Attention
    hidden_size::Int
    head_dim::Int
    num_heads::Int
    num_kv_heads::Int
    causal::Bool
    qkv_proj::CastedLinear
    o_proj::CastedLinear
    bad_rope_value::Bool     # 負の対照 (vii)。既定は false
end

"Attention.forward: qkv_proj → 頭ごとに分ける → q・k に rope → 因子なしの scaled dot-product → o_proj。"
function (a::Attention)(cos_sin, hidden_states::AbstractArray{Float64,3})
    bs, seq, _ = size(hidden_states)
    qkv = a.qkv_proj(hidden_states)                      # (bs, seq, (nh+2nkv)*hd)
    nh, nkv, hd = a.num_heads, a.num_kv_heads, a.head_dim
    # 公式の .view(B, S, nh+2nkv, hd) は行優先で f = スライス*hd + d（d が最も速い）。
    # 列優先では (bs, seq, hd, スライス) と並べると f = d + hd*(スライス-1) になり一致する。
    qkv = reshape(qkv, bs, seq, hd, nh + 2nkv)
    q = qkv[:, :, :, 1:nh]                               # (bs, seq, hd, nh)
    k = qkv[:, :, :, nh+1:nh+nkv]
    v = qkv[:, :, :, nh+nkv+1:nh+2nkv]
    q = Array(q); k = Array(k); v = Array(v)
    if cos_sin !== nothing
        cos, sin = cos_sin
        q, k = apply_rotary_pos_emb(q, k, cos, sin)
        if a.bad_rope_value                              # 負の対照 (vii)。既定は false
            v, _ = apply_rotary_pos_emb(v, v, cos, sin)
        end
    end
    attn = similar(v)                                    # (bs, seq, hd, nh)
    # scaled_dot_product_attention は 1/sqrt(E) を掛ける（E = query の最後の次元 = hd）
    scale = Float64(1) / sqrt(Float64(hd))
    for bi in 1:bs, hi in 1:nh
        g = hi <= nkv ? hi : nkv
        qi = Array(view(q, bi, :, :, hi))                # (seq, hd)
        ki = Array(view(k, bi, :, :, g))
        vi = Array(view(v, bi, :, :, g))
        scores = (qi * transpose(ki)) .* scale           # (seq_q, seq_k)
        if a.causal
            for r in 1:seq, c in (r+1):seq
                scores[r, c] = Float64(-Inf)
            end
        end
        mx = maximum(scores; dims=2)
        e = exp.(scores .- mx)
        p = e ./ sum(e; dims=2)
        attn[bi, :, :, hi] = p * vi
    end
    # 公式の .reshape(B, S, nh*hd) は f = 頭*hd + d。(bs, seq, hd, nh) の並びなら f = d + hd*(頭-1) で一致。
    out = reshape(attn, bs, seq, nh * hd)
    return a.o_proj(out)
end

"silu(x) = x * sigmoid(x)。"
silu(x::AbstractArray{Float64}) = x .* (Float64(1) ./ (Float64(1) .+ exp.(-x)))

struct SwiGLU
    gate_up_proj::CastedLinear
    down_proj::CastedLinear
end
down_proj(m::SwiGLU) = m.down_proj
gate_up_proj(m::SwiGLU) = m.gate_up_proj

"inter = round(expansion*hidden*2/3) を 256 の倍数に切り上げ（_find_multiple）。"
swiglu_inter(hidden::Integer, expansion::Real) = _find_multiple(round(Int, Float64(expansion) * hidden * 2 / 3), 256)

function SwiGLU(hidden::Integer, expansion::Real; gate_up=nothing, down=nothing)
    inter = swiglu_inter(hidden, expansion)
    gu = gate_up === nothing ? CastedLinear(zeros(Float64, inter * 2, hidden)) : CastedLinear(gate_up)
    dp = down === nothing ? CastedLinear(zeros(Float64, hidden, inter)) : CastedLinear(down)
    return SwiGLU(gu, dp)
end

function (m::SwiGLU)(x::AbstractArray{Float64,3})
    g = m.gate_up_proj(x)
    inter = size(g, 3) ÷ 2
    gate = Array(g[:, :, 1:inter])
    up = Array(g[:, :, inter+1:end])
    return m.down_proj(silu(gate) .* up)
end

"rms_norm: Float32 の中で variance = mean(x^2)、x * rsqrt(variance + eps)。"
function rms_norm(hidden_states::AbstractArray{Float64}, variance_epsilon::Real)
    @assert ndims(hidden_states) <= 3
    b = Array{Float64,3}(hidden_states)
    v = sum(abs2, b; dims=3) ./ Float64(size(b, 3))
    return hidden_states .* (Float64(1) ./ sqrt.(v .+ Float64(variance_epsilon)))
end

# ---- trm.py: Block ----

mutable struct Block
    config::Any
    puzzle_emb_len::Int
    mlp_t::Union{Nothing,SwiGLU}
    self_attn::Union{Nothing,Attention}
    mlp::SwiGLU
    norm_eps::Float64
    bad_norm::Symbol                  # 負の対照 (viii) を置く正規化。既定は :none
end

function Block(cfg)
    mlp_t_flag = Bool(_getattr(cfg, :mlp_t))
    h = Int(_getattr(cfg, :hidden_size))
    nheads = Int(_getattr(cfg, :num_heads))
    pel = Int(_getattr(cfg, :puzzle_emb_ndim))
    slen = Int(_getattr(cfg, :seq_len))
    puzz_len = Int(_getattr(cfg, :puzzle_emb_len))
    puzzle_emb_len = puzz_len == 0 ? cld(pel, h) : puzz_len
    mlp_t = mlp_t_flag ? SwiGLU(slen + puzzle_emb_len, _getattr(cfg, :expansion)) : nothing
    attn = mlp_t_flag ? nothing :
           Attention(h, h ÷ nheads, nheads, nheads, false,
                     CastedLinear(zeros(Float64, 3nheads * (h ÷ nheads), h)), CastedLinear(zeros(Float64, h, nheads * (h ÷ nheads))), false)
    return Block(cfg, puzzle_emb_len, mlp_t, attn,
                 SwiGLU(h, _getattr(cfg, :expansion)), Float64(_getattr(cfg, :rms_norm_eps)), :none)
end

"""norm1: 一つめの正規化の出力（mlp_t の構成でも (batch, seq, hidden) の形で返す）。
mlp_t の構成の bad_norm == :norm1 のときだけ、転置の前（mlp_t の入力）で正規化する（負の対照 (viii)）。
注意機構の構成では違いを出さない（(viii) は mlp_t の構成に置く）。"""
function norm1(b::Block, cos_sin, h::AbstractArray{Float64,3})
    if b.mlp_t !== nothing
        t = Float64.(permutedims(h, (1, 3, 2)))           # (bs, hidden, seq)
        out = (b.bad_norm == :norm1 ? rms_norm(t, b.norm_eps) : t) .+ b.mlp_t(t)
        return Float64.(permutedims(rms_norm(out, b.norm_eps), (1, 3, 2)))
    else
        return rms_norm(h .+ b.self_attn(cos_sin, h), b.norm_eps)
    end
end

"first_op: 最初の演算の出力（mlp_t の構成では転置した形のまま）。"
function first_op(b::Block, cos_sin, h::AbstractArray{Float64,3})
    if b.mlp_t !== nothing
        return b.mlp_t(Float64.(permutedims(h, (1, 3, 2))))
    else
        return b.self_attn(cos_sin, h)
    end
end

"mlp_out: 二つめの演算（MLP）の出力。"
mlp_fn(b::Block, hs::AbstractArray{Float64,3}) = b.mlp(hs)

"Block.forward: 注意機構の版と mlp_t の版。"
function (b::Block)(cos_sin, hidden_states::AbstractArray{Float64,3})
    hs = norm1(b, cos_sin, hidden_states)
    out = mlp_fn(b, hs)
    return rms_norm(hs .+ out, b.norm_eps)
end

# ---- trm.py: ReasoningModule ----

struct ReasoningModule
    layers::Vector{Block}
end

function (m::ReasoningModule)(hidden_states::AbstractArray{Float64,3}, input_injection::AbstractArray{Float64,3}; cos_sin=nothing)
    hs = hidden_states .+ input_injection
    for layer in m.layers
        hs = layer(cos_sin, hs)
    end
    return hs
end

# ---- trm.py: _Inner ----

mutable struct Inner
    config::Any
    embed_scale::Float64
    embed_tokens::CastedEmbedding
    lm_head::CastedLinear
    q_head::CastedLinear
    puzzle_emb_len::Int
    puzzle_emb::Union{Nothing,CastedEmbedding}
    rotary_emb::Union{Nothing,Tuple{Matrix{Float64},Matrix{Float64}}}
    embed_pos::Union{Nothing,CastedEmbedding}
    L_level::ReasoningModule
    H_init::Array{Float64,3}                                    # (1, 1, hidden)：torch.where で batch に放送
    L_init::Array{Float64,3}
    swap_update_order::Bool                                 # 負の対照 (iv)。既定は false
    q_head_pos::Int                                         # 負の対照 (v)。既定は 1
end

function Inner(cfg)
    h = Int(_getattr(cfg, :hidden_size))
    nheads = Int(_getattr(cfg, :num_heads))
    embed_scale = Float64(sqrt(Float64(h)))
    pel = Int(_getattr(cfg, :puzzle_emb_ndim))
    puzz_len = Int(_getattr(cfg, :puzzle_emb_len))
    puzzle_emb_len = puzz_len == 0 ? cld(pel, h) : puzz_len
    embed_tokens = CastedEmbedding(zeros(Float64, Int(_getattr(cfg, :vocab_size)), h))
    lm_head = CastedLinear(zeros(Float64, Int(_getattr(cfg, :vocab_size)), h))
    q_head = CastedLinear(zeros(Float64, 2, h), zeros(Float64, 2))   # 公式は重み 0・バイアス -5
    puzzle_emb = pel > 0 ? CastedEmbedding(zeros(Float64, Int(_getattr(cfg, :num_puzzle_identifiers)), pel)) : nothing
    pos = String(_getattr(cfg, :pos_encodings))
    npos = Int(_getattr(cfg, :seq_len)) + puzzle_emb_len
    rotary = pos == "rope" ? RotaryEmbedding(h ÷ nheads, npos, _getattr(cfg, :rope_theta)) : nothing
    embed_pos = pos == "learned" ? CastedEmbedding(zeros(Float64, npos, h)) : nothing
    L_level = ReasoningModule([Block(cfg) for _ in 1:Int(_getattr(cfg, :L_layers))])
    return Inner(cfg, embed_scale, embed_tokens, lm_head, q_head, puzzle_emb_len, puzzle_emb,
                 rotary, embed_pos, L_level, zeros(Float64, 1, 1, h), zeros(Float64, 1, 1, h), false, 1)
end

"_input_embeddings: token → puzzle（前に連結）→ learned の位置（0.707106781 倍）→ embed_scale 倍。"
function input_embeddings(inner::Inner, input::AbstractArray{<:Integer}, puzzle_identifiers::AbstractArray{<:Integer})
    h = Int(_getattr(inner.config, :hidden_size))
    # 表は fixture と同じ 1 始まりの添字で引く（CastedEmbedding の中で +1 する）。
    # 入力が permutedims の見かけの転置なら、返りも転置の筋になるので実体化する。
    embedding = Array{Float64,3}(inner.embed_tokens(input))
    if inner.puzzle_emb !== nothing
        pe = inner.puzzle_emb(puzzle_identifiers)               # (bs, puzzle_emb_ndim)
        pad = inner.puzzle_emb_len * h - size(pe, 2)
        if pad > 0                                              # F.pad((0, pad)): 最後の軸の後ろに 0 を足す
            pe = hcat(pe, zeros(Float64, size(pe, 1), pad))
        end
        bs, nrow = size(pe, 1), inner.puzzle_emb_len
        # 公式の view(-1, puzzle_emb_len, hidden): 行ごとに 行優先 で並べ替える
        pe3 = Array{Float64,3}(undef, bs, nrow, h)
        for bi in 1:bs, r in 1:nrow, k in 1:h
            pe3[bi, r, k] = pe[bi, (r - 1) * h + k]
        end
        embedding = cat(pe3, embedding; dims=2)
    end
    if inner.embed_pos !== nothing
        idx = collect(0:(size(embedding, 2) - 1))
        pos = inner.embed_pos(idx)                              # (長さ npos, hidden)
        embedding = Float64(0.707106781) .* (embedding .+ reshape(pos, 1, size(pos, 1), h))
    end
    return inner.embed_scale .* embedding
end

"reset_carry: reset_flag は batch ごとの真偽。真の行を H_init・L_init に置き換える。"
function reset_carry(inner::Inner, reset_flag::AbstractVector{Bool}, z_H::AbstractArray{Float64,3}, z_L::AbstractArray{Float64,3})
    a = copy(z_H)
    b = copy(z_L)
    for i in 1:size(a, 1)
        if reset_flag[i]
            # torch.where(reset.view(-1,1,1), H_init, z_H): H_init は (d,) で z の最後の軸に広がる
            a[i:i, :, :] .= reshape(_flat_hidden(inner.H_init, size(a, 3)), 1, 1, size(a, 3))
            b[i:i, :, :] .= reshape(_flat_hidden(inner.L_init, size(b, 3)), 1, 1, size(b, 3))
        end
    end
    return a, b
end

"_flat_hidden: (hidden,) と (1, 1, hidden) の両方を同じに扱い、hidden 長さのベクトルにする。"
function _flat_hidden(x::AbstractArray, h::Integer)
    @assert length(x) == h "init size $(size(x)) != $h"
    return vec(x)
end

# ---- trm.py: _Inner.forward（H/L 周回）と ACT の包み（評価モード） ----

# ---- trm.py: ACT の包み（評価モードだけ） ----

"Carry: 公式の ACTV1Carry。z_* は (batch, seq_total, hidden)、current_data は生の整数の配列。"
mutable struct Carry
    z_H::Array{Float64,3}
    z_L::Array{Float64,3}
    steps::Vector{Int}
    halted::Vector{Bool}
    current_data::Dict{String,Array{Int}}
end

"ACTModel: Inner を組み、重みを state（公式の名前 → 配列）から入れる。負の対照の引数は既定で公式の式のまま。"
mutable struct ACTModel
    config::Any
    inner::Inner
    cos_sin::Union{Nothing,Tuple{Matrix{Float64},Matrix{Float64}}}
    swap_update_order::Bool
    q_head_pos::Int
end

function ACTModel(cfg, state::AbstractDict; swap_update_order::Bool=false, q_head_pos::Integer=1,
                  bad_norm_order::Bool=false, bad_rope_value::Bool=false)
    inner = Inner(cfg)
    inner.embed_tokens = CastedEmbedding(copy(state["inner.embed_tokens.embedding_weight"]))
    inner.lm_head = CastedLinear(copy(state["inner.lm_head.weight"]))
    inner.q_head = CastedLinear(copy(state["inner.q_head.weight"]), copy(state["inner.q_head.bias"]))
    h = Int(_getattr(cfg, :hidden_size))
    inner.H_init = reshape(copy(state["inner.H_init"]), 1, 1, h)
    inner.L_init = reshape(copy(state["inner.L_init"]), 1, 1, h)
    if inner.puzzle_emb !== nothing
        inner.puzzle_emb = CastedEmbedding(copy(state["inner.puzzle_emb.weights"]))
    end
    if inner.embed_pos !== nothing
        inner.embed_pos = CastedEmbedding(copy(state["inner.embed_pos.embedding_weight"]))
    end
    nh = Int(_getattr(cfg, :num_heads))
    hd = h ÷ nh
    for (i, blk) in enumerate(inner.L_level.layers)
        pre = "inner.L_level.layers." * string(i - 1)
        if blk.self_attn !== nothing
            qkv = copy(state[pre * ".self_attn.qkv_proj.weight"])
            blk.self_attn = Attention(blk.self_attn.hidden_size, hd, nh, nh, false,
                                      CastedLinear(qkv), CastedLinear(copy(state[pre * ".self_attn.o_proj.weight"])),
                                      bad_rope_value)
        end
        expn = _getattr(cfg, :expansion)
        if blk.mlp_t !== nothing
            # mlp_t は (batch, hidden, seq) を受けるので、入力の幅は seq_len + puzzle_emb_len。
            blk.mlp_t = SwiGLU(size(state[pre * ".mlp_t.gate_up_proj.weight"], 2), expn;
                               gate_up=copy(state[pre * ".mlp_t.gate_up_proj.weight"]),
                               down=copy(state[pre * ".mlp_t.down_proj.weight"]))
            bad_norm_order && (blk.bad_norm = :norm1)
        end
        blk.mlp = SwiGLU(h, expn; gate_up=copy(state[pre * ".mlp.gate_up_proj.weight"]),
                         down=copy(state[pre * ".mlp.down_proj.weight"]))
    end
    inner.swap_update_order = swap_update_order
    inner.q_head_pos = q_head_pos
    return ACTModel(cfg, inner, inner.rotary_emb, swap_update_order, q_head_pos)
end

"initial_carry: 空の carry（z は 0 で有限、steps 0、halted 全部真、current_data は batch と同じ形の 0）。"
function initial_carry(model::ACTModel, batch::AbstractDict)
    inputs = Array{Int}(batch["inputs"])
    pid = Array{Int}(batch["puzzle_identifiers"])
    b = size(inputs, 1)
    seq = size(inputs, 2) + model.inner.puzzle_emb_len
    h = Int(_getattr(model.config, :hidden_size))
    cd = Dict{String,Array{Int}}("inputs" => zeros(Int, size(inputs)), "puzzle_identifiers" => zeros(Int, size(pid)))
    return Carry(zeros(Float64, b, seq, h), zeros(Float64, b, seq, h), zeros(Int, b), fill(true, b), cd)
end

"h_round: 一つの H 周回（L_cycles 回の L と、そのあとの H 1 回）。"
function h_round(inner::Inner, z_H0::AbstractArray{Float64,3}, z_L0::AbstractArray{Float64,3}, emb::AbstractArray{Float64,3};
                 cos_sin=nothing, swap::Bool=false)
    z_H = Array{Float64,3}(z_H0)
    z_L = Array{Float64,3}(z_L0)
    for _ in 1:Int(_getattr(inner.config, :L_cycles))
        # 公式: z_L = L_level(z_L, z_H + emb)。
        z_L = inner.L_level(z_L, z_H .+ emb; cos_sin=cos_sin)
        # 負の対照 (iv): 同じ周回で z_H を先に書き換える（既定はしない）。
        swap && (z_H = inner.L_level(z_H, z_L; cos_sin=cos_sin))
    end
    # 公式は L_cycles 回のあとに z_H = L_level(z_H, z_L) を 1 回。
    z_H = inner.L_level(z_H, z_L; cos_sin=cos_sin)
    return z_H, z_L
end

"recursion: 初期 z_H・z_L から H_cycles 周回（h_round を H_cycles 回）。最後の周回の z を返す。"
function recursion(inner::Inner, z_H0::AbstractArray{Float64,3}, z_L0::AbstractArray{Float64,3}, emb::AbstractArray{Float64,3};
                   cos_sin=nothing, swap::Bool=false)
    z_H = Array{Float64,3}(z_H0)
    z_L = Array{Float64,3}(z_L0)
    for _ in 1:Int(_getattr(inner.config, :H_cycles))
        z_H, z_L = h_round(inner, z_H, z_L, emb; cos_sin=cos_sin, swap=swap)
    end
    return z_H, z_L
end

"""inner_forward: 公式の _Inner.forward（推論。全周回を同じ式で回す）。
logits = lm_head(z_H)[:, puzzle_emb_len:]、q = q_head(z_H[:, 0]) の 2 値。新しい carry の z は detach した z_H・z_L。"""
function inner_forward(model::ACTModel, carry::Carry, batch::AbstractDict)
    inner = model.inner
    emb = Array{Float64,3}(input_embeddings(inner, batch["inputs"], batch["puzzle_identifiers"]))
    z_H, z_L = recursion(inner, carry.z_H, carry.z_L, emb; cos_sin=model.cos_sin, swap=inner.swap_update_order)
    pel = inner.puzzle_emb_len
    logits = Array{Float64,3}(inner.lm_head(Array{Float64,3}(z_H)))
    logits = logits[:, pel+1:end, :]
    pos = inner.q_head_pos
    1 <= pos <= size(z_H, 2) || error(string("q_head_pos out of bounds: ", pos))
    q = Array{Float64,3}(inner.q_head(Array{Float64,3}(z_H[:, pos:pos, :]))) # (batch, 1, 2)
    q = reshape(Array{Float64,2}(q[:, 1, :]), size(q, 1), 2)
    q_halt = q[:, 1]
    q_cont = q[:, 2]
    new_carry = Carry(Array{Float64,3}(z_H), Array{Float64,3}(z_L), Int[], Bool[], Dict{String,Array{Int}}())
    return new_carry, Dict{String,Any}("logits" => logits, "q_halt_logits" => q_halt, "q_continue_logits" => q_cont)
end

"""act_forward: 公式の ACTV1.forward（評価モード）。halted の行だけ carry を reset し、
steps を 0 に、current_data を batch で置き換えてから inner を 1 回進める。
steps += 1、halted = steps >= halt_max_steps。"""
function act_forward(model::ACTModel, carry::Carry, batch::AbstractDict)
    inner = model.inner
    b = size(carry.z_H, 1)
    prev_halted = copy(carry.halted)                     # 公式の carry.halted
    size(prev_halted) == (b,) || error("halted length does not match batch")
    size(carry.steps) == (b,) || error("steps length does not match batch")
    # 1) 先に carry を reset（停止していた行を H_init/L_init に戻す）し、steps・current_data を入れ替える。
    z_H, z_L = reset_carry(inner, prev_halted, carry.z_H, carry.z_L)
    steps = Vector{Int}(undef, b)
    for i in 1:b
        steps[i] = prev_halted[i] ? 0 : carry.steps[i]
    end
    cd = Dict{String,Array{Int}}()
    for k in keys(carry.current_data)
        cur = carry.current_data[k]
        new = Array{Int}(batch[k])
        size(cur) == size(new) || error(string("current_data ", k, " shape mismatch"))
        w = copy(Array{Int}(cur))
        colons = ntuple(_ -> Colon(), ndims(w) - 1)
        for i in 1:b
            prev_halted[i] && (w[i:i, colons...] .= view(new, i:i, colons...))
        end
        cd[k] = w
    end
    # 2) inner forward は reset 後・current_data 置き換え後の入力で回す。
    # 公式の new_current_data は {k: ... for k, v in carry.current_data.items()} を keys とし、
    # 値は torch.where(halted, batch[k], v)。その値をそのまま inner の入力にする。
    act_batch = Dict{String,Any}()
    for k in keys(cd)
        haskey(batch, k) || error(string("current_data key missing in batch: ", k))
        act_batch[k] = cd[k]
    end
    # z は reset 後の値から回す（公式: new_inner_carry の z が inner.forward の初期値）。
    prev = Carry(z_H, z_L, copy(carry.steps), copy(prev_halted), cd)
    out_carry, outputs = inner_forward(model, prev, act_batch)
    # 3) 評価モード: steps += 1、halted = steps >= halt_max_steps。
    for i in 1:b
        steps[i] += 1
    end
    hmax = Int(_getattr(model.config, :halt_max_steps))
    halted = Bool[steps[i] >= hmax for i in 1:b]
    return Carry(out_carry.z_H, out_carry.z_L, steps, halted, cd), outputs
end

"h_round_ends: 1 手めの入力で、初期 carry（reset 後）から各 H 周回の終わりの (z_H, z_L) を順に返す。"
function h_round_ends(model::ACTModel, batch::AbstractDict)
    inner = model.inner
    carry = initial_carry(model, batch)
    rH, rL = reset_carry(inner, fill(true, size(carry.z_H, 1)), carry.z_H, carry.z_L)
    emb = Array{Float64,3}(input_embeddings(inner, batch["inputs"], batch["puzzle_identifiers"]))
    out = Tuple{Array{Float64,3},Array{Float64,3}}[]
    z_H, z_L = rH, rL
    for _ in 1:Int(_getattr(inner.config, :H_cycles))
        z_H, z_L = h_round(inner, z_H, z_L, emb; cos_sin=model.cos_sin, swap=inner.swap_update_order)
        push!(out, (copy(z_H), copy(z_L)))
    end
    return out
end

# ---- fixtures ----

"""_to_julia: 行優先（最後の添字が最も速い）の data と shape → Julia の shape の配列。
permutedims(reshape(data, reverse(shape)...), ndims:-1:1)（この操作は自分自身の逆）。0 次元は 0 次元。"""
function _to_julia(data, shape)
    sh = Int[Int(x) for x in shape]
    v = Float64.(collect(data))::Vector{Float64}
    isempty(sh) && return fill(v[1])
    return Array(permutedims(reshape(v, reverse(sh)...), length(sh):-1:1))
end

"_to_rowmajor: Julia の配列 → 行優先の Vector（負の対照 (ix) のため）。"
_to_rowmajor(a::AbstractArray) = vec(permutedims(a, length(size(a)):-1:1))

"load_tensor(d): dtype が int* なら Int の配列、それ以外は F32 の配列（行優先の data を直す）。"
function load_tensor(d::AbstractDict)
    if startswith(String(get(d, "dtype", "float32")), "int")
        v = Int[Int(round(Float64(x))) for x in d["data"]]
        sh = Int[Int(x) for x in d["shape"]]
        isempty(sh) && return fill(v[1])
        return Int.(permutedims(reshape(v, reverse(sh)...), length(sh):-1:1))
    end
    return _to_julia(d["data"], d["shape"])
end

"""load_fixture(path) → (config, state（名前 → 配列）, rope, inputs, steps, mixed_reset, intermediates, env)。
state・rope・入力・intermediates の data は行優先なので _to_julia で直す。"""
function load_fixture(path::AbstractString)
    obj = JSON.parsefile(path)
    cfg = _named(obj["config"])
    state = Dict(k => load_tensor(v) for (k, v) in obj["state_dict"])
    rope = haskey(obj, "rope") && obj["rope"] isa AbstractDict ?
           Dict{String,Any}(k => load_tensor(v) for (k, v) in obj["rope"]) : Dict{String,Any}()
    inputs = Dict{String,Any}()
    for (k, v) in obj["inputs"]
        inputs[k] = Dict{String,Any}("inputs" => load_tensor(v["inputs"]),
                                     "puzzle_identifiers" => load_tensor(v["puzzle_identifiers"]))
    end
    inter = obj["intermediates"]
    if inter isa AbstractDict
        inter = Dict{String,Any}(k => (v isa AbstractDict && haskey(v, "data") ? load_tensor(v) : v)
                                 for (k, v) in inter)
    end
    return (config = cfg, state = state, rope = rope, inputs = inputs, steps = obj["steps"],
            mixed_reset = get(obj, "mixed_reset", nothing), intermediates = inter, env = obj["env"])
end

function _named(d::AbstractDict)
    return (names = Symbol.(collect(keys(d))), values = Any[d[k] for k in keys(d)])
end

end # module