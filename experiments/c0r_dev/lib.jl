# S71 dev library: the pieces of c0_trm/c0_trm.jl that the dev experiments need (copied, not changed; S64 files are not touched).
# Loads S57's synthetic world (frozen files, as c0_trm.jl), TrmC0, the obs streams, the 47-token input, training, prediction, controls.
using SHA, Printf, TOML, LinearAlgebra, Statistics

const HERE = @__DIR__
const EXP = normpath(joinpath(HERE, ".."))
const LAB = normpath(joinpath(EXP, ".."))
BLAS.set_num_threads(1)

const S57 = Module(:S57)
Core.eval(S57, :(include(x) = Base.include($S57, x)))
let src = read(joinpath(EXP, "draw_conf_grid.jl"), String)
    i = findfirst("\nif MODE in (", src); i === nothing && error("anchor: run block")
    pre = src[1:i[1]]
    a = "const MODE = length(ARGS) >= 1 ? ARGS[1] : error(\"mode gates | freeze | pilot | eval\")"
    length(findall(a, pre)) == 1 || error("anchor: MODE")
    include_string(S57, replace(pre, a => "const MODE = \"lib\""), joinpath(EXP, "draw_conf_grid.jl"))
end
include(joinpath(EXP, "trm", "TrmPort.jl"))
include(joinpath(EXP, "trm", "det", "TrmDet.jl"))
include(joinpath(EXP, "c0_trm", "TrmC0.jl"))
using .TrmC0: S, V, H, NH, HD, IM, NL, Cfg, CFG_TRM, CFG_1X1
const Mulberry = S57.LabCore.Mulberry

# S64 constants (unchanged); the S64 seed sets are reused only for dev (TRAIN, VAL); fresh seeds from 1110 are for the confirmatory run
const TRAIN = collect(1050:1061); const VAL = collect(1062:1067)
const T0 = 800; const STEPS = 10000; const NS = STEPS - T0
const WP = (P = 1000, sigma = 1.0, L = 300, M = 2.5); const BMIN = 6; const BMAX = 24
const LO = 1 / 200; const HI = 199 / 200
const W4 = 4; const ALPHA = 1.0; const ALPHA_R1 = 1.0
const BATCH = 64; const INITSEED = 640001; const BATCHSEED = 640100
const CE = 1.0
const CHUNK = 64
clip(p) = clamp(p, LO, HI)
const ROPE = TrmPort.RotaryEmbedding(HD, S, 10000.0)
brev(u) = BMIN + floor(Int, (BMAX - BMIN + 1) * Mulberry(1_000_003 * u + 63)())
function rev_table(g, sr)
    g2 = copy(g)
    for s in sr:size(g, 1)-1; g2[s+1, 1] = g[s+1, 2]; g2[s+1, 2] = g[s+1, 1]; end
    return g2
end
function world_table(u, fam)
    g = S57.synth_table(u, WP.P, WP.sigma, WP.L, WP.M)
    return fam == "stat" ? g : rev_table(g, WP.L * brev(u))
end
function tmapv(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads :greedy for i in eachindex(xs); out[i] = f(xs[i]); end
    return out
end

struct Stream
    fam::String; seed::Int
    r::BitMatrix
    act::Vector{Int8}; Y::Vector{Bool}; isex::Vector{Bool}
end
function run_body(u, fam; observe = nothing)
    g = world_table(u, fam)
    ext = Dict{Symbol,Any}()
    fam == "stat" || (ext[:SCHED] = (s, k) -> g[s+1, k])
    observe === nothing || (ext[:ON_STEP] = observe)
    return S57.run_arm("L2", "UNI", u; bits = S57.gen_bits(u), extra = (; ext...))
end
function obs_stream(u, fam)
    acting = Vector{Vector{Int}}(undef, STEPS); ys = Vector{Vector{Float64}}(undef, STEPS); seen = falses(STEPS)
    rec = falses(8, NS)
    function observe(x)
        x.t >= T0 || return
        acting[x.t+1] = copy(x.acting); ys[x.t+1] = copy(x.y); seen[x.t+1] = true
        for k in 1:8; rec[k, x.t-T0+1] = x.circuit.active[k]; end
    end
    r = run_body(u, fam; observe = observe)
    all(seen[T0+1:STEPS]) || error("obs: a step from T0 was not observed")
    d = r["drawer"]
    ix = [i for i in eachindex(d.lt) if length(d.lcs[i]) >= 2 && d.lt[i] >= T0]
    act = zeros(Int8, NS); Y = falses(NS); isex = falses(NS)
    for t in T0:STEPS-1
        ac = acting[t+1]
        if length(ac) == 1; act[t-T0+1] = ac[1]; Y[t-T0+1] = ys[t+1][ac[1]] > 0; end
    end
    for i in ix; isex[d.lt[i]-T0+1] = true; end
    return Stream(fam, u, rec, act, collect(Bool, Y), collect(Bool, isex))
end

# the 47-token input (S64 §1.2); recept = false puts PAD in the receptor slots (obs-ay)
function encode!(tok, col, st::Stream, s::Int, recept::Bool)
    tok[1, col] = 0x00
    for f in 1:W4
        j = s - W4 - 1 + f; base = 1 + (f - 1) * 11
        if j < 0
            for q in 1:11; tok[base+q, col] = 0x00; end
        else
            for k in 1:8; tok[base+k, col] = recept ? (st.r[k, j+1] ? 0x02 : 0x01) : 0x00; end
            tok[base+9, col] = 0x00
            a = st.act[j+1]
            tok[base+10, col] = a == 0 ? 0x03 : a == 1 ? 0x04 : 0x05
            tok[base+11, col] = st.act[j+1] == 0 ? 0x06 : st.Y[j+1] ? 0x08 : 0x07
        end
    end
    tok[46, col] = 0x09; tok[47, col] = 0x0a
    return tok
end
struct ExSet; seed::Int; tok::Matrix{UInt8}; act::Vector{Int8}; Y::Vector{Bool}; s::Vector{Int}; end
function exset(st::Stream, recept::Bool)
    ss = [s for s in 0:NS-1 if st.isex[s+1]]
    tok = Matrix{UInt8}(undef, S, length(ss))
    for (c, s) in enumerate(ss); encode!(tok, c, st, s, recept); end
    return ExSet(st.seed, tok, st.act[ss.+1], st.Y[ss.+1], ss)
end
function catsets(v::Vector{ExSet})
    return ExSet(-1, reduce(hcat, [e.tok for e in v]), reduce(vcat, [e.act for e in v]), reduce(vcat, [e.Y for e in v]),
                 reduce(vcat, [e.s for e in v]))
end

# input masks for the dev experiments (a mask only writes PAD = 0 over the 47-token input; positions are 1-based columns)
const R1POS = [34 + k for k in (1, 2, 3, 4, 7, 8)]      # frame 4 (s-1): receptors r1 r2 r3 r4 r7 r8 (TAB_R1's six)
const R8POS = [34 + k for k in 1:8]
const RALLPOS = [1 + (f - 1) * 11 + k for f in 1:W4 for k in 1:8]
# full: unchanged; ay: the receptor slots are already PAD (built with exset(st, false)); r1 / r8 / rall: keep only those positions
const KEEP = Dict("r1" => R1POS, "r8" => R8POS, "rall" => RALLPOS)
function applymask(es::ExSet, mode::String)
    mode in ("full", "ay") && return es
    keep = Set(vcat(get(KEEP, mode) do; error("mask mode $mode"); end, [46, 47]))
    tok = copy(es.tok)
    for q in 1:S; q in keep || (tok[q, :] .= 0x00); end
    return ExSet(es.seed, tok, es.act, es.Y, es.s)
end
# the controls (RATE, TAB_R1) of S64 for reference
const R1IDX = (1, 2, 3, 4, 7, 8)
function r1key(st, s, a)
    s == 0 && return 2 * 64 + a
    k = 0
    for (i, m) in enumerate(R1IDX); st.r[m, s] && (k += 1 << (i - 1)); end
    return 2 * k + a
end
# the tables are counts over the train streams only (no randomness): build once, score each val stream
struct Ctrl; rate::Vector{Float64}; rn::Vector{Int}; rn1::Vector{Int}; end
function ctrl_train(train::Vector{Stream})
    n = [0, 0]; n1 = [0, 0]; rn = zeros(Int, 130); rn1 = zeros(Int, 130)
    for t in train, s in 0:NS-1
        t.isex[s+1] || continue
        a = t.act[s+1]; y = t.Y[s+1]; n[a] += 1; n1[a] += y
        k = r1key(t, s, a); rn[k] += 1; rn1[k] += y
    end
    return Ctrl([(n1[a] + 1) / (n[a] + 2) for a in 1:2], rn, rn1)
end
function ctrl_scores(c::Ctrl, st::Stream)
    ss = [s for s in 0:NS-1 if st.isex[s+1]]
    pr = Float64[]; pt = Float64[]
    for s in ss
        a = st.act[s+1]; k = r1key(st, s, a)
        push!(pr, clip(c.rate[a])); push!(pt, clip((c.rn1[k] + ALPHA_R1 * c.rate[a]) / (c.rn[k] + ALPHA_R1)))
    end
    act = st.act[ss.+1]; Y = st.Y[ss.+1]
    return (RATE = score(pr, act, Y).sc, TAB_R1 = score(pt, act, Y).sc)
end

function train_model(pool::ExSet, cfg::Cfg, lr, wd, nsteps; ce = CE, seed = BATCHSEED, log = nothing)
    p = TrmC0.init_params(Mulberry(INITSEED))
    w = TrmC0.WorkSet{Float32}(cfg.Lc + 1, ROPE...)
    g = TrmC0.Params{Float32}(); o = TrmC0.Opt(p)
    r = Mulberry(seed); n = size(pool.tok, 2)
    tok = Matrix{UInt8}(undef, S, BATCH); act = Vector{Int}(undef, BATCH); Y = Vector{Bool}(undef, BATCH)
    trace = Float64[]
    for t in 1:nsteps
        for b in 1:BATCH
            i = 1 + floor(Int, n * r())
            for q in 1:S; tok[q, b] = pool.tok[q, i]; end
            act[b] = pool.act[i]; Y[b] = pool.Y[i]
        end
        L = TrmC0.train_step!(p, g, o, w, cfg, tok, act, Y, lr, wd; ce = ce)
        push!(trace, L[1])
        log !== nothing && t % 100 == 0 && log(t, mean(trace[end-99:end]))
    end
    return p, trace
end
function predict_set(p, cfg::Cfg, es::ExSet)
    n = size(es.tok, 2)
    ids = Dict{Vector{UInt8},Int}(); uniq = Int[]; idx = Vector{Int}(undef, n)
    for c in 1:n
        k = es.tok[:, c]
        j = get(ids, k, 0)
        if j == 0; push!(uniq, c); j = length(uniq); ids[k] = j; end
        idx[c] = j
    end
    nu = length(uniq)
    P = zeros(2, nu)
    w = TrmC0.Work{Float32}(CHUNK, 0, ROPE...)
    tokc = Matrix{UInt8}(undef, S, CHUNK); pp = zeros(2, CHUNK); ee = zeros(2, CHUNK); zq = zeros(Float32, H, 2, CHUNK)
    for c0 in 0:CHUNK:nu-1
        m = min(CHUNK, nu - c0)
        for b in 1:CHUNK, q in 1:S; tokc[q, b] = es.tok[q, uniq[c0+min(b, m)]]; end
        TrmC0.predict!(pp, ee, zq, w, p, cfg, tokc)
        for b in 1:m; P[:, c0+b] .= pp[:, b]; end
    end
    return (p = [P[es.act[c], idx[c]] for c in 1:n], nuniq = nu, P = P, idx = idx)
end
function score(p::Vector{Float64}, act, Y)
    L = [0.0, 0.0]; n = [0, 0]
    for i in eachindex(p)
        a = act[i]; q = Y[i] ? p[i] : 1 - p[i]
        L[a] += -log(q); n[a] += 1
    end
    sc = (n[1] == 0 || n[2] == 0) ? NaN : (L[1] / n[1] + L[2] / n[2]) / 2
    return (sc = sc, n = n)
end
