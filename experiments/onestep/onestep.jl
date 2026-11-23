# S69 (discussion/specs/S69-onestep-contract-julia.md r2): aue_step, the one-step contract of an AUE in Julia.
# A variant of core/one_life.jl's onelife_step (core is NOT changed): the source of core/circuit.jl's step! and of one_life.jl's _live are
# copied with ONE hook added (a draw hook at the choice among candidates, as S55/S57's step_draw_conf!), then evaluated here.
# With no predictor (draw = nothing) the copy must be bit-identical to onelife_step (gate U1).
# Predictors in this stage: NullPred (p = 1/2), TracePred (B1-like single trace, P_DECAY 8). The TRM predictor and the C2 head are NOT here (S69 §1 H-S69-2).
isdefined(Main, :LabCore) || include(joinpath(@__DIR__, "..", "..", "core", "LabCore.jl"))
include(joinpath(@__DIR__, "..", "..", "core", "one_life.jl"))
using SHA

const OS_LAB = normpath(joinpath(@__DIR__, "..", ".."))
function rep1(f, anchor, new)
    n = length(findall(anchor, f)); n == 1 || error("anchor occurs $n times: $anchor")
    return replace(f, anchor => new)
end

# ---- step_aue!: core/circuit.jl's step! with the draw hook (as draw_conf_grid.jl draw_step_source) ----
function _aue_step_source(src)
    i = findfirst("function step!(st::CState, b::Circuit, y;", src); i === nothing && error("anchor: function step!")
    j = findnext("\nend\n", src, i[1]); j === nothing && error("anchor: end")
    f = src[i[1]:j[end]]
    f = rep1(f, "function step!(st::CState, b::Circuit, y;", "function step_aue!(st::CState, b::Circuit, y;")
    f = rep1(f, "rest_off = false, body_flag = nothing)", "rest_off = false, body_flag = nothing, draw = nothing)")
    a = "        for m in cand; m != win && (nw[m] = false); end\n"
    f = rep1(f, a, """
        if draw !== nothing
            dcs = cand
            if idle_first; didl = [m for m in cand if now - st.lastM[m] > FORGET]; isempty(didl) || (dcs = didl); end
            win = draw(cand, dcs, win, key, b, conf, habit, total, y)
        end
""" * a)
    return f
end
Core.eval(LabCore, Meta.parse(_aue_step_source(read(joinpath(OS_LAB, "core", "circuit.jl"), String))))

# ---- _live_aue: one_life.jl's _live calling step_aue! (mutate: a negative-control hook on the source text) ----
function _live_source(name::String; mutate = identity)
    src = read(joinpath(OS_LAB, "core", "one_life.jl"), String)
    i = findfirst("function _live(s::OneLife{L}, g,", src); i === nothing && error("anchor: _live")
    j = findnext("\nend\n", src, i[1]); f = src[i[1]:j[end]]
    f = rep1(f, "function _live(s::OneLife{L}, g,", "function $name(draw, s::OneLife{L}, g,")
    f = rep1(f, "out = step!(circuit, b, [y[1], y[2], 0.0]; noise = noise,", "out = LabCore.step_aue!(circuit, b, [y[1], y[2], 0.0]; draw = draw, noise = noise,")
    return mutate(f)
end
Core.eval(Main, Meta.parse(_live_source("_live_aue")))

# ---- predictors (immutable values; the update returns a new one) ----
abstract type Pred end
struct NullPred <: Pred end
struct TracePred <: Pred; m1::Float64; m2::Float64; end
const K_WIN = 0.002; const P_DECAY = 8.0
TracePred() = TracePred(0.5, 0.5)
# predict(pred, R) -> (pred_eff, p1, p2): the retention (1 slot * K_WIN <= R) is read only; a failing step resets the trace before predicting.
predict(::NullPred, R) = (NullPred(), 0.5, 0.5)
function predict(p::TracePred, R)
    q = (1 * K_WIN <= R) ? p : TracePred()
    return (q, q.m1, q.m2)
end
_clip(x) = min(199 / 200, max(1 / 200, x))
update(p::NullPred, a, ans) = p
function update(p::TracePred, a, ans)
    t = ans ? 1.0 : 0.0
    a == 1 ? TracePred(_clip(p.m1 + (t - p.m1) / P_DECAY), p.m2) : TracePred(p.m1, _clip(p.m2 + (t - p.m2) / P_DECAY))
end
pred_bytes(::NullPred) = UInt8[0x00]
pred_bytes(p::TracePred) = (io = IOBuffer(); write(io, UInt8(1)); write(io, htol(reinterpret(UInt64, p.m1))); write(io, htol(reinterpret(UInt64, p.m2))); take!(io))
pred_from_bytes(b::Vector{UInt8}) = b[1] == 0x00 ? NullPred() :
    TracePred(reinterpret(Float64, ltoh(reinterpret(UInt64, b[2:9])[1])), reinterpret(Float64, ltoh(reinterpret(UInt64, b[10:17])[1])))

# ---- state, input, record ----
struct AueState{L}
    life::OneLife{L}
    pred::Pred
end
aue_birth(seed, law, pred::Pred) = AueState(onelife_birth(seed, law), pred)
struct AueInput
    g1::Int; g2::Int
    rand_u64::UInt64
end
struct AueRecord
    drawn::Bool; p1::Float64; p2::Float64; pi1::Float64; u::Float64
    patch::Int; det_patch::Int; y1::Float64; y2::Float64; ans::Bool
    err::Bool; committed::Bool
end
const NOREC = AueRecord(false, NaN, NaN, NaN, NaN, 0, 0, NaN, NaN, false, false, false)
aue_save(s::AueState) = vcat(onelife_save(s.life), pred_bytes(s.pred))
aue_digest(s::AueState) = bytes2hex(sha256(aue_save(s)))
function aue_load(::Type{L}, bytes::Vector{UInt8}, nlife::Int) where {L}
    AueState(_load(L, bytes[1:nlife]), pred_from_bytes(bytes[nlife+1:end]))
end
body_R(life::OneLife) = (w = life.w; sum((w.B[i] for i in eachindex(w.C) if w.C[i] != 0); init = 0.0))
mapping_pi(p1, p2) = (p1 + p2 == 0.0) ? 0.5 : 1 / 8 + (3 / 4) * (p1 / (p1 + p2))

mutable struct _DrawBox; rec::AueRecord; pred_eff::Pred; end

# the draw hook: predictor -> pi -> one uniform from rand_u64 -> a motor of the chosen patch among the preferred candidates (S66 §1.5, S69 H-S69-1)
function _make_draw(box::_DrawBox, pred::Pred, R::Float64, u::Float64; route_det::Bool = false)
    return function (cand, cs, win, key, b, conf, habit, total, y)
        s = sort([m for m in cs if b.patch[m] <= 2]; by = m -> (b.patch[m], m))
        length(unique(b.patch[m] for m in s)) >= 2 || return win
        pe, p1, p2 = predict(pred, R)
        pi1 = mapping_pi(p1, p2)
        a = u < pi1 ? 1 : 2
        ch = s[findfirst(m -> b.patch[m] == a, s)]
        box.pred_eff = pe
        box.rec = AueRecord(true, p1, p2, pi1, u, a, b.patch[win], Float64(y[1]), Float64(y[2]), y[a] > 0, false, false)
        return route_det ? win : ch      # route_det: negative control only (records the draw, acts as DET)
    end
end
const LAWC = Dict(LawL2 => false, LawL2SF => true)
# aue_step(state, input) -> (state', record). The state is not mutated (deep copies inside _live). Dead: returned as it is, the input is not read.
function aue_step(s::AueState{L}, inp::AueInput; live = _live_aue, use_draw::Bool = true, route_det::Bool = false) where {L}
    life = s.life
    life.dead && return (s, NOREC)
    _empty_body(life) && return (AueState(_detect(life), s.pred), AueRecord(false, NaN, NaN, NaN, NaN, 0, 0, NaN, NaN, false, false, true))
    g = (inp.g1, inp.g2)
    _drive_ok(g) || return (s, AueRecord(false, NaN, NaN, NaN, NaN, 0, 0, NaN, NaN, false, true, false))
    box = _DrawBox(NOREC, s.pred)
    u = Float64(inp.rand_u64 >> 11) * 2.0^-53
    hook = use_draw ? _make_draw(box, s.pred, body_R(life), u; route_det = route_det) : nothing
    nl = Base.invokelatest(live, hook, life, g, 0.02, 0.004, 0.002, :bin3, true, true, LAWC[L])
    r = box.rec
    pred2 = r.drawn ? update(box.pred_eff, r.patch, r.ans) : s.pred
    rec = AueRecord(r.drawn, r.p1, r.p2, r.pi1, r.u, r.patch, r.det_patch, r.y1, r.y2, r.ans, false, true)
    return (AueState(nl, pred2), rec)
end

# ---- audit: input lines (before the step) and commit lines (after), one text chain; replay from the text only ----
input_line(n, inp::AueInput) = "input $n $(inp.g1) $(inp.g2) $(inp.rand_u64)"
function commit_line(n, st::AueState, prev::String)
    d = aue_digest(st)
    h = bytes2hex(sha256("commit $n $d $prev"))
    return ("commit $n $d $prev $h", h)
end
const GENESIS = "0"^64
function run_audited(s0::AueState, inputs::Vector{AueInput}; start_n::Int = 0, prev::String = GENESIS, live = _live_aue, kw...)
    s = s0; lines = String[]; recs = AueRecord[]; states = AueState[]
    for (i, inp) in enumerate(inputs)
        n = start_n + i
        push!(lines, input_line(n, inp))
        s2, r = aue_step(s, inp; live = live, kw...)
        if r.committed
            cl, prev = commit_line(n, s2, prev); push!(lines, cl)
        end
        s = s2; push!(recs, r)
    end
    return (state = s, lines = lines, recs = recs, last_hash = prev)
end
function parse_inputs(lines::Vector{String})
    out = AueInput[]
    for l in lines
        startswith(l, "input ") || continue
        f = split(l)
        push!(out, AueInput(parse(Int, f[3]), parse(Int, f[4]), parse(UInt64, f[5])))
    end
    return out
end
# the first line index where two audit texts differ (0 = identical)
first_diff(a::Vector{String}, b::Vector{String}) = (i = findfirst(k -> k > length(a) || k > length(b) || a[k] != b[k], 1:max(length(a), length(b))); i === nothing ? 0 : i)

# ---- radio row -> input (S68 §2, C4 conversion; binary64, FMA-free order; the same constants as fast_sim.jl) ----
const MU_W = 297.20108758532916; const SD_W = 39.79874519579147; const MU_B = 2.9924794631493694; const SD_B = 0.8134565410732445
const SIN_TABLE_1000 = [sin(2.0 * pi * Float64(idx) / 1000.0) for idx in 0:999]
function c4_yields(step::Int, w_sum::Float64, b_n::Float64, stale::Bool; honor_stale::Bool = true)
    z1, z2 = (stale && honor_stale) ? (0.0, 0.0) : ((w_sum - MU_W) / SD_W, (b_n - MU_B) / SD_B)
    x1 = (2.5 + (2.5 * SIN_TABLE_1000[(step % 1000) + 1])) + z1
    x2 = (2.5 + (2.5 * SIN_TABLE_1000[((step + 500) % 1000) + 1])) + z2
    return (Int(clamp(round(x1, RoundNearest), 0.0, 5.0)), Int(clamp(round(x2, RoundNearest), 0.0, 5.0)))
end
