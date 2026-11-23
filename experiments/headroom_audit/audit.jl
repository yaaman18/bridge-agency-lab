# S63 headroom audit (C0's move 0): the room an (a, Y)-history predictor has over the single trace B1, measured against the
# exact sequential Bayes filter of the synthetic world (discussion/specs/S63-headroom-audit.md r3; predictions.toml, frozen in
# ../freeze-headroom-audit.txt). Two tracks: exo (actions drawn from gen_bits(u), independent of the world; every step acts and
# is scored) and obs (the canonical L2 UNI body's trajectory, S57's construction). Two world families: stat (S57's synth_table)
# and rev (the same table with patches 1 and 2 swapped from s_rev(u) = 300 b_rev(u)). No change to S57's code, core/ or rust/.
# S57's construction is loaded from its source without its run block into a module of its own (as memory-transfer-c0/c0.jl).
# Usage (from the lab root):  julia --project=. -t 8 experiments/headroom_audit/audit.jl out     (then -t 1 ... out-rerun)
using SHA, JSON, Printf, TOML

const HERE = @__DIR__
const EXP = normpath(joinpath(HERE, ".."))
const OUTNAME = length(ARGS) >= 1 ? ARGS[1] : "out"
const OUT = joinpath(HERE, OUTNAME)
sha(f) = bytes2hex(open(sha256, f))
const LOG = String[]
say(x...) = (s = string(x...); println(s); push!(LOG, s); flush(stdout))
gate(name, ok) = (ok || (write_log(); error("$name failed; no evaluation")); ok)
write_log() = (mkpath(OUT); write(joinpath(OUT, "results.out"), join(LOG, "\n") * "\n"))

function read_sums(f)
    ref = Dict{String,String}()
    for l in eachline(f)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    return ref
end

# ---------------- G7: the spec and the predictions = the freeze ----------------
const FREEZE = read_sums(joinpath(EXP, "freeze-headroom-audit.txt"))
const G7FILES = ["../discussion/specs/S63-headroom-audit.md", "headroom_audit/predictions.toml"]
const G7 = all(f -> get(FREEZE, f, "") == sha(normpath(joinpath(EXP, f))), G7FILES)
G7 || error("G7: the spec or predictions.toml differs from the freeze; not run")

# ---------------- G0: S57's code, unchanged, loaded without its run block ----------------
const S57FILES = ["draw_conf_grid.jl", "check_draw_conf.jl", "check_draw.jl", "synth_world.jl", "../core/circuit.jl", "../core/body_org.jl"]
const S57REF = read_sums(joinpath(EXP, "freeze-draw-conf-code.txt"))
const G0 = all(f -> get(S57REF, f, "") == sha(normpath(joinpath(EXP, f))), S57FILES)
G0 || error("G0: S57's code differs from freeze-draw-conf-code.txt")
const S57 = Module(:S57)
Core.eval(S57, :(include(x) = Base.include($S57, x)))
let src = read(joinpath(EXP, "draw_conf_grid.jl"), String)
    i = findfirst("\nif MODE in (", src); i === nothing && error("anchor: run block")
    pre = src[1:i[1]]
    a = "const MODE = length(ARGS) >= 1 ? ARGS[1] : error(\"mode gates | freeze | pilot | eval\")"
    length(findall(a, pre)) == 1 || error("anchor: MODE")
    include_string(S57, replace(pre, a => "const MODE = \"lib\""), joinpath(EXP, "draw_conf_grid.jl"))
end

# ---------------- design (predictions.toml, fixed before the runs; checked against the file) ----------------
const PT = TOML.parsefile(joinpath(HERE, "predictions.toml"))
const DEV = collect(1006:1009); const TRAIN = collect(1010:1021); const EVAL = collect(1022:1045)
const T0 = 800; const STEPS = 10000; const NS = STEPS - T0
const WP = (P = 1000, sigma = 1.0, L = 300, M = 2.5)
const BMIN = 6; const BMAX = 24
const LO = 1 / 200; const HI = 199 / 200; const EPS = 1e-12
const KDEC = 8; const W4 = 4; const ALPHA = 1.0
const DALL = 0.002; const DWIN = 0.010; const KWIN = 200; const SHIFT = 9
const MINALL = 30; const MINWIN = 15; const MINSEEDS = 16
const BOOTB = 5000; const BOOTSEED = 630001
const QSTOP = (0.025, 0.975); const QPRO = (0.05 / 12, 1 - 0.05 / 12); const SIGNA = 0.05 / 6
let s = PT["seeds"], w = PT["world"], p = PT["predictors"], e = PT["evaluation"]
    ok = s["dev"] == DEV && (s["train_start"]:s["train_end"]) == TRAIN && (s["eval_start"]:s["eval_end"]) == EVAL && s["next_unused_main_seed"] == 1046 &&
         w["law"] == "L2" && w["arm"] == "UNI" && w["T0"] == T0 == S57.T0 && w["STEPS"] == STEPS == S57.STEPS && w["P"] == WP.P && w["sigma"] == WP.sigma &&
         w["L"] == WP.L && w["M"] == WP.M && (S57.WP.P, S57.WP.sigma, S57.WP.L, S57.WP.M) == (WP.P, WP.sigma, WP.L, WP.M) &&
         w["rev_block_min"] == BMIN && w["rev_block_max"] == BMAX && w["rev_seed_mul"] == 1_000_003 && w["rev_seed_add"] == 63 &&
         p["clip_lo"] == LO && p["clip_hi"] == HI && p["bayes_raw_eps"] == EPS && p["b1_decay_k"] == KDEC == S57.LabCore.P_DECAY &&
         p["tab4_window"] == W4 && p["tab4_alpha"] == ALPHA && e["delta_all"] == DALL && e["delta_win"] == DWIN && e["win_k"] == KWIN &&
         e["shuf_block_shift"] == SHIFT && e["min_obs_all_per_action"] == MINALL && e["min_obs_win_per_action"] == MINWIN &&
         e["min_eligible_seeds"] == MINSEEDS && e["bootstrap_B"] == BOOTB && e["bootstrap_seed"] == BOOTSEED && e["stop_ci_level"] == 0.95 &&
         e["proceed_ci_level"] == 1 - 0.05 / 6 && e["proceed_sign_alpha"] == SIGNA && S57.SW_NS == NS && S57.SW_A == 2.5
    ok || error("design constants differ from predictions.toml")
end
clip(p) = clamp(p, LO, HI)
brev(u) = BMIN + floor(Int, (BMAX - BMIN + 1) * S57.LabCore.Mulberry(1_000_003 * u + 63)())
bctrl(u) = BMIN + ((brev(u) - BMIN + SHIFT) % (BMAX - BMIN + 1))

# ---------------- the standard normal: Φ and Q = 1 - Φ, each with its own relative accuracy ----------------
# erfc for y >= 0: the series erf(y) = 2/√π e^{-y²} Σ (2y²)^n y / (2n+1)!! below 2, the continued fraction (Lentz) above.
function erfc_pos(y::Float64)
    y >= 0 || error("erfc_pos: negative")
    if y < 2.0
        t = y; s = y; n = 0; y2 = 2.0 * y * y
        while true
            n += 1; t *= y2 / (2n + 1); s += t
            t <= 1e-17 * s && break
        end
        return 1.0 - 2.0 / sqrt(pi) * exp(-y * y) * s
    end
    tiny = 1e-300; f = y; C = f; D = 0.0
    for n in 1:100000
        an = n / 2
        D = y + an * D; D == 0 && (D = tiny); D = 1 / D
        C = y + an / C; C == 0 && (C = tiny)
        dl = C * D; f *= dl
        abs(dl - 1) < 1e-16 && return exp(-y * y) / sqrt(pi) / f
    end
    error("erfc_pos: no convergence")
end
Qn(x::Float64) = x == Inf ? 0.0 : x == -Inf ? 1.0 : x >= 0 ? 0.5 * erfc_pos(x / sqrt(2.0)) : 1.0 - 0.5 * erfc_pos(-x / sqrt(2.0))
Phin(x::Float64) = x == -Inf ? 0.0 : x == Inf ? 1.0 : x <= 0 ? 0.5 * erfc_pos(-x / sqrt(2.0)) : 1.0 - 0.5 * erfc_pos(x / sqrt(2.0))
# mass of (l, u] from the stored Φ and Q of its ends: the two small tails are differenced on the side where they are small
@inline function nmass(l, u, pl, ql, pu, qu)
    l >= u && return 0.0
    u <= 0 && return pu - pl
    l >= 0 && return ql - qu
    return 1.0 - pl - qu
end

# ---------------- the exact sequential Bayes filter (spec §2) ----------------
struct World; P::Int; sigma::Float64; L::Int; M::Float64; ns::Int; rev::Bool; end
# thresholds c(n, k) = (0.5 - M - 2.5 sin(2π n / P + φ_k)) / σ at n = s + θ, with Φ and Q; the deterministic part is the
# generator's own expression (synth_world.jl:29), so Y = 1 <=> z > c up to rounding of the last bit.
struct Thr; c::Matrix{Float64}; pc::Matrix{Float64}; qc::Matrix{Float64}; end
function thresholds(w::World)
    nn = w.ns + w.P; c = Matrix{Float64}(undef, nn, 2); pc = similar(c); qc = similar(c); phi = (0.0, pi)
    for n in 0:nn-1, k in 1:2
        x = w.M + S57.SW_A * sin(2.0 * pi * n / w.P + phi[k])
        c[n+1, k] = (0.5 - x) / w.sigma; pc[n+1, k] = Phin(c[n+1, k]); qc[n+1, k] = Qn(c[n+1, k])
    end
    return Thr(c, pc, qc)
end
mutable struct BayesOut
    p1::Vector{Float64}; p0::Vector{Float64}   # at the examples, in order
    infeasible::Int                             # first step at which every hypothesis had zero mass (-1 if never)
    maxsumdev::Float64                          # max over steps of |Σ posterior weights - 1|
end
@inline function lse(v)
    m = maximum(v); m == -Inf && return -Inf
    s = 0.0
    @inbounds for x in v; s += exp(x - m); end
    return m + log(s)
end
# act[s+1] in 0:2 (0 = no act), Y[s+1], isex[s+1]; order at each s: block boundary -> predict (example) -> update (act).
# allow_infeasible: G3's flipped histories only (the predictions after the first empty step are NaN).
function bayes(w::World, T::Thr, act, Y, isex; allow_infeasible = false, trace = nothing, hazard = b -> 1.0 / (BMAX + 1 - b))
    P = w.P; R = w.rev ? 2 : 1; H = P * R
    lwe = fill(-Inf, H); for th in 1:P; lwe[th] = -log(P); end
    lo = fill(-Inf, 2, H); hi = fill(Inf, 2, H); plo = zeros(2, H); qlo = ones(2, H); phi_ = ones(2, H); qhi = zeros(2, H)
    lm = zeros(2, H); lws = zeros(H); s1 = zeros(H); s0 = zeros(H)
    out = BayesOut(Float64[], Float64[], -1, 0.0); dead = false
    for s in 0:w.ns-1
        if s > 0 && s % w.L == 0 && !dead   # block boundary b-1 -> b: commit once, hazard (rev), reset the intervals
            b = s ÷ w.L
            @inbounds for h in 1:H; lws[h] = lwe[h] + lm[1, h] + lm[2, h]; end
            z = lse(lws)
            @inbounds for h in 1:H; lwe[h] = lws[h] - z; end
            if w.rev && BMIN <= b <= BMAX
                hz = hazard(b)
                @inbounds for th in 1:P
                    w0 = lwe[th]; w1 = lwe[P+th]
                    lwe[th] = hz == 1.0 ? -Inf : w0 + log1p(-hz)
                    a1 = w0 + log(hz); m = max(w1, a1)
                    lwe[P+th] = m == -Inf ? -Inf : m + log(exp(w1 - m) + exp(a1 - m))
                end
            end
            fill!(lo, -Inf); fill!(hi, Inf); fill!(plo, 0.0); fill!(qlo, 1.0); fill!(phi_, 1.0); fill!(qhi, 0.0); fill!(lm, 0.0)
        end
        a = act[s+1]
        if isex[s+1]
            if dead
                push!(out.p1, NaN); push!(out.p0, NaN)
            else
                @inbounds for h in 1:H
                    th = (h - 1) % P; r = (h - 1) ÷ P; k = r == 0 ? a : 3 - a; n = s + th + 1
                    lws[h] = lwe[h] + lm[1, h] + lm[2, h]
                    c = T.c[n, k]; l = lo[k, h]; u = hi[k, h]
                    mt = nmass(l, u, plo[k, h], qlo[k, h], phi_[k, h], qhi[k, h])
                    if c <= l; s1[h] = 1.0; s0[h] = 0.0
                    elseif c >= u; s1[h] = 0.0; s0[h] = 1.0
                    else
                        s1[h] = nmass(c, u, T.pc[n, k], T.qc[n, k], phi_[k, h], qhi[k, h]) / mt
                        s0[h] = nmass(l, c, plo[k, h], qlo[k, h], T.pc[n, k], T.qc[n, k]) / mt
                    end
                end
                m = maximum(lws); S1 = 0.0; S0 = 0.0; SW = 0.0
                @inbounds for h in 1:H
                    e = exp(lws[h] - m); SW += e; S1 += e * s1[h]; S0 += e * s0[h]
                end
                out.maxsumdev = max(out.maxsumdev, abs((S1 + S0) / SW - 1.0))
                push!(out.p1, S1 / (S1 + S0)); push!(out.p0, S0 / (S1 + S0))
                if trace !== nothing   # G4 only: the normalized weights sum
                    zz = lse(lws); sw = 0.0
                    for h in 1:H; sw += exp(lws[h] - zz); end
                    push!(trace, abs(sw - 1.0))
                end
            end
        end
        if a != 0 && !dead
            yv = Y[s+1]
            @inbounds for h in 1:H
                th = (h - 1) % P; r = (h - 1) ÷ P; k = r == 0 ? a : 3 - a; n = s + th + 1
                c = T.c[n, k]
                if yv
                    c > lo[k, h] && (lo[k, h] = c; plo[k, h] = T.pc[n, k]; qlo[k, h] = T.qc[n, k])
                else
                    c < hi[k, h] && (hi[k, h] = c; phi_[k, h] = T.pc[n, k]; qhi[k, h] = T.qc[n, k])
                end
                mt = nmass(lo[k, h], hi[k, h], plo[k, h], qlo[k, h], phi_[k, h], qhi[k, h])
                lm[k, h] = mt > 0 ? log(mt) : -Inf
            end
            @inbounds for h in 1:H; lws[h] = lwe[h] + lm[1, h] + lm[2, h]; end
            if maximum(lws) == -Inf
                allow_infeasible || error("bayes: every hypothesis has zero mass at s = $s (a = $a, Y = $yv)")
                dead = true; out.infeasible = s
            end
        end
    end
    return out
end

# ---------------- G4: brute force on the reduced world (explicit b_rev, bisection on the generator, Simpson integrals) ----------------
function simpson_phi(a, b)
    a = max(a, -10.0); b = min(b, 10.0); a >= b && return 0.0
    n = max(2, 2 * ceil(Int, (b - a) / 2e-3 / 2)); h = (b - a) / n
    f(z) = exp(-z * z / 2) / sqrt(2pi)
    s = f(a) + f(b)
    for i in 1:n-1; s += (isodd(i) ? 4 : 2) * f(a + i * h); end
    return s * h / 3
end
# the boundary z* of {z : clamp(round(M + 2.5 sin(..) + σ z), 0, 5) > 0}, found on the generator's own expression
function zstar(w::World, s, th, k)
    phi = (0.0, pi)
    g(z) = clamp(round(w.M + S57.SW_A * sin(2.0 * pi * (s + th) / w.P + phi[k]) + w.sigma * z), 0.0, 5.0) > 0
    lo, hi = -30.0, 30.0
    (g(hi) && !g(lo)) || error("zstar: no boundary")
    for _ in 1:200; m = (lo + hi) / 2; g(m) ? (hi = m) : (lo = m); end
    return (lo + hi) / 2
end
function brute(w::World, act, Y)
    hyps = w.rev ? [(th, bv) for th in 0:w.P-1 for bv in BMIN:BMAX] : [(th, -1) for th in 0:w.P-1]
    lprior = w.rev ? -log(w.P) - log(BMAX - BMIN + 1) : -log(w.P)
    LL = zeros(length(hyps), w.ns); PJ = zeros(length(hyps), w.ns)   # log P(history < s | hyp), P(Y_s = 1 | history < s, hyp)
    for (j, (th, bv)) in enumerate(hyps)
        lat(t) = (w.rev && t >= w.L * bv) ? 3 - act[t+1] : act[t+1]   # the latent z_k the act at t reads under this hypothesis
        done = lprior; iv = [(-Inf, Inf), (-Inf, Inf)]
        for s in 0:w.ns-1
            if s > 0 && s % w.L == 0   # the finished block's two integrals, once
                for k in 1:2; m = simpson_phi(iv[k]...); done += m > 0 ? log(m) : -Inf; end
                iv = [(-Inf, Inf), (-Inf, Inf)]
            end
            k = lat(s); zs = zstar(w, s, th, k); l, u = iv[k]
            cur = 0.0
            for kk in 1:2; m = simpson_phi(iv[kk]...); cur += m > 0 ? log(m) : -Inf; end
            mt = simpson_phi(l, u)
            LL[j, s+1] = done + cur; PJ[j, s+1] = mt > 0 ? simpson_phi(max(l, zs), u) / mt : 0.0
            iv[k] = Y[s+1] ? (max(l, zs), u) : (l, min(u, zs))
        end
    end
    p = zeros(w.ns)
    for s in 0:w.ns-1
        z = lse(LL[:, s+1]); p[s+1] = sum(exp(LL[j, s+1] - z) * PJ[j, s+1] for j in eachindex(hyps))
    end
    return p
end
function rev_table(g, sr)
    g2 = copy(g)
    for s in sr:size(g, 1)-1; g2[s+1, 1] = g[s+1, 2]; g2[s+1, 2] = g[s+1, 1]; end
    return g2
end

# ---------------- the streams (exo and obs) ----------------
struct Stream
    track::String; fam::String; seed::Int
    act::Vector{Int}; Y::Vector{Bool}; isex::Vector{Bool}   # indexed by s + 1, s in 0:NS-1
    nupd::Int; maxacts::Int; g2bad::Int; g2badsh::Int; nex::Int; death::Any
end
function world_table(u, fam)
    g = S57.synth_table(u, WP.P, WP.sigma, WP.L, WP.M)
    return fam == "stat" ? g : rev_table(g, WP.L * brev(u))
end
function exo_stream(u, fam)
    g = world_table(u, fam); bits = S57.gen_bits(u)
    act = [bits[s+1] == 0 ? 1 : 2 for s in 0:NS-1]
    Y = [g[s+1, act[s+1]] > 0 for s in 0:NS-1]
    return Stream("exo", fam, u, act, Y, fill(true, NS), NS, 1, 0, 1, NS, nothing)
end
function obs_stream(u, fam)
    g = world_table(u, fam)
    acting = Vector{Vector{Int}}(undef, STEPS); ys = Vector{Vector{Float64}}(undef, STEPS); seen = falses(STEPS)
    obs = x -> (x.t >= T0 && (acting[x.t+1] = copy(x.acting); ys[x.t+1] = copy(x.y); seen[x.t+1] = true))
    ext = fam == "stat" ? (ON_STEP = obs,) : (SCHED = (s, k) -> g[s+1, k], ON_STEP = obs)
    r = S57.run_arm("L2", "UNI", u; bits = S57.gen_bits(u), extra = ext)
    all(seen[T0+1:STEPS]) || error("obs: a step from T0 was not observed")
    d = r["drawer"]
    ix = [i for i in eachindex(d.lt) if length(d.lcs[i]) >= 2 && d.lt[i] >= T0]
    act = zeros(Int, NS); Y = falses(NS); isex = falses(NS); maxacts = 0; nupd = 0
    for t in T0:STEPS-1
        ac = acting[t+1]; maxacts = max(maxacts, length(ac))
        if length(ac) == 1
            act[t-T0+1] = ac[1]; Y[t-T0+1] = ys[t+1][ac[1]] > 0; nupd += 1
        end
    end
    for i in ix; isex[d.lt[i]-T0+1] = true; end
    # G2: at every example the step's acts are [a] and Y = y[a] > 0 = the drawer's record; shifted by one step must mismatch
    bad(sh) = count(i -> (t = d.lt[i] + sh; t > STEPS - 1 || acting[t+1] != [d.lch[i]] || (ys[t+1][d.lch[i]] > 0) != d.lans[i] ||
                          ys[t+1] != d.ly[i]), ix)
    return Stream("obs", fam, u, act, Collect(Y), isex, nupd, maxacts, bad(0), bad(1), length(ix), r["death"])
end
Collect(x) = collect(Bool, x)

# ---------------- the predictors other than BAYES ----------------
code(st, j) = (j < 0 || st.act[j+1] == 0) ? 0 : 2 * (st.act[j+1] - 1) + Int(st.Y[j+1]) + 1
function tabkey(st, s, a)
    k = 0
    for j in s-W4:s-1; k = 5 * k + code(st, j); end
    return 2 * k + a   # 1..1250
end
struct Trained; rate::Vector{Float64}; n::Vector{Int}; n1::Vector{Int}; tn::Vector{Int}; tn1::Vector{Int}; end
function train(streams)
    n = [0, 0]; n1 = [0, 0]; tn = zeros(Int, 2 * 5^W4); tn1 = zeros(Int, 2 * 5^W4)
    for st in streams, s in 0:NS-1
        st.isex[s+1] || continue
        a = st.act[s+1]; y = st.Y[s+1]; n[a] += 1; n1[a] += y
        k = tabkey(st, s, a); tn[k] += 1; tn1[k] += y
    end
    return Trained([(n1[a] + 1) / (n[a] + 2) for a in 1:2], n, n1, tn, tn1)
end
const PREDS = ("RATE", "B1", "B1_raw", "TAB4", "BAYES_raw", "BAYES_clip")
struct Preds; s::Vector{Int}; a::Vector{Int}; Y::Vector{Bool}; p::Dict{String,Vector{Float64}}; q::Dict{String,Vector{Float64}}; bayes::BayesOut; end
const WFULL = World(WP.P, WP.sigma, WP.L, WP.M, NS, false)
const WREV = World(WP.P, WP.sigma, WP.L, WP.M, NS, true)
const TFULL = Ref{Thr}()
# p = P(Y = 1), q = P(Y = 0) (BAYES gives both from its two sums; the others q = 1 - p)
function predict(st::Stream, tr::Trained; flip = 0, allow_infeasible = false)
    Y = copy(st.Y); flip > 0 && (Y[flip] = !Y[flip])
    stf = Stream(st.track, st.fam, st.seed, st.act, Y, st.isex, st.nupd, st.maxacts, st.g2bad, st.g2badsh, st.nex, st.death)
    p = Dict(k => Float64[] for k in (PREDS..., "LEAK")); q = Dict(k => Float64[] for k in (PREDS..., "LEAK"))
    m = [0.5, 0.5]; ss = Int[]; aa = Int[]; YY = Bool[]
    for s in 0:NS-1
        a = st.act[s+1]
        if st.isex[s+1]
            push!(ss, s); push!(aa, a); push!(YY, Y[s+1])
            k = tabkey(stf, s, a)
            v = Dict("RATE" => clip(tr.rate[a]), "B1" => clip(m[a]), "B1_raw" => m[a],
                     "TAB4" => clip((tr.tn1[k] + ALPHA * tr.rate[a]) / (tr.tn[k] + ALPHA)), "LEAK" => clip(Y[s+1] ? 1.0 : 0.0))
            for (kk, x) in v; push!(p[kk], x); push!(q[kk], 1 - x); end
        end
        a != 0 && (m[a] += ((Y[s+1] ? 1.0 : 0.0) - m[a]) / KDEC)
    end
    bo = bayes(st.fam == "stat" ? WFULL : WREV, TFULL[], st.act, Y, st.isex; allow_infeasible = allow_infeasible)
    p["BAYES_raw"] = bo.p1; q["BAYES_raw"] = bo.p0
    p["BAYES_clip"] = clip.(bo.p1); q["BAYES_clip"] = 1 .- clip.(bo.p1)
    return Preds(ss, aa, YY, p, q, bo)
end
function b1after(st::Stream, sflip, flip)
    m = [0.5, 0.5]
    for s in 0:sflip-1
        a = st.act[s+1]; a == 0 && continue
        y = st.Y[s+1]; (flip && s + 1 == sflip) && (y = !y)
        m[a] += ((y ? 1.0 : 0.0) - m[a]) / KDEC
    end
    return m[st.act[sflip]]
end
function loss(name, p, q, y)
    if name in ("B1_raw", "BAYES_raw")
        return y ? -log(max(p, EPS)) : -log(max(q, EPS))
    end
    return y ? -log(p) : -log(q)
end

# ---------------- scoring ----------------
# window: s in [from, to); per-action mean loss averaged over the two actions
function winscore(pr::Preds, from, to)
    na = [0, 0]; L = Dict(k => [0.0, 0.0] for k in PREDS); nout = 0; ndef = 0
    for i in eachindex(pr.s)
        (from <= pr.s[i] < to) || continue
        a = pr.a[i]; na[a] += 1
        for k in PREDS; L[k][a] += loss(k, pr.p[k][i], pr.q[k][i], pr.Y[i]); end
        x = pr.p["BAYES_raw"][i]; isnan(x) || (ndef += 1); (x < LO || x > HI) && (nout += 1)
    end
    sc = Dict(k => (na[1] == 0 || na[2] == 0) ? NaN : (L[k][1] / na[1] + L[k][2] / na[2]) / 2 for k in PREDS)
    return (n = na, sc = sc, nout = nout, ndef = ndef)
end
function seedrec(pr::Preds, u)
    sr = WP.L * brev(u); sc = WP.L * bctrl(u)
    return Dict("all" => winscore(pr, 0, NS), "wtrue" => winscore(pr, sr, sr + KWIN), "wshuf" => winscore(pr, sc, sc + KWIN))
end
function signtest(wins, losses)
    n = wins + losses; n == 0 && return 1.0
    k = min(wins, losses)
    return Float64(min(big(1), 2 * sum(binomial(big(n), big(i)) for i in 0:k) / big(2)^n))
end
function qtl(sv, p)   # type 7 on sorted values
    h = (length(sv) - 1) * p + 1; lo = floor(Int, h); hi = min(lo + 1, length(sv))
    return sv[lo] + (h - lo) * (sv[hi] - sv[lo])
end
function boot(d)
    n = length(d); r = S57.LabCore.Mulberry(BOOTSEED); mb = Vector{Float64}(undef, BOOTB)
    for b in 1:BOOTB
        s = 0.0
        for _ in 1:n; s += d[1+floor(Int, n * r())]; end
        mb[b] = s / n
    end
    sort!(mb)
    return (ci95 = (qtl(mb, QSTOP[1]), qtl(mb, QSTOP[2])), cipro = (qtl(mb, QPRO[1]), qtl(mb, QPRO[2])))
end
function axisstat(d)
    n = length(d)
    n == 0 && return Dict{String,Any}("n" => 0, "detectable" => false, "defined" => true)
    nu = count(isnan, d)
    nu > 0 && return Dict{String,Any}("n" => n, "detectable" => false, "defined" => false, "n_undefined" => nu)
    b = boot(d); w = count(>(0), d); l = count(<(0), d)
    return Dict{String,Any}("n" => n, "detectable" => n >= MINSEEDS, "defined" => true, "mean" => sum(d) / n, "ci95" => collect(b.ci95), "ci9917" => collect(b.cipro),
                            "wins" => w, "losses" => l, "ties" => n - w - l, "p_sign" => signtest(w, l), "min" => minimum(d), "max" => maximum(d))
end

# ---------------- main ----------------
function tmapv(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads for i in eachindex(xs); out[i] = f(xs[i]); end
    return out
end
# the threaded jobs are top-level functions (no capture of main's locals)
function g4one((u, fam))
    wr = World(4, WP.sigma, 4, WP.M, 104, fam == "rev")
    g = S57.synth_table(u, 4, WP.sigma, 4, WP.M; ns = 104)
    fam == "rev" && (g = rev_table(g, 4 * brev(u)))
    bits = S57.gen_bits(u); act = [bits[s+1] == 0 ? 1 : 2 for s in 0:103]; Y = [g[s+1, act[s+1]] > 0 for s in 0:103]
    tr = Float64[]
    bo = bayes(wr, thresholds(wr), act, Y, fill(true, 104); trace = tr)
    pb = brute(wr, act, Y)
    dif = abs.(bo.p1 .- pb)
    neg = fam == "rev" ? maximum(abs.(bayes(wr, thresholds(wr), act, Y, fill(true, 104); hazard = b -> 1.0 / 19).p1 .- pb)) : NaN
    (u = u, fam = fam, mid = maximum(dif[s+1] for s in 0:103 if s % 4 != 0), b6 = maximum(dif[25:28]), b24 = maximum(dif[97:100]),
     all = maximum(dif), sumdev = maximum(tr), brev = brev(u), nY0 = count(!, Y), neg = neg)
end
# B1's trace of the flipped example's action after every later update of that action: (s, state) for the flipped and the original history
function b1trail(st::Stream, sflip)
    m0 = [0.5, 0.5]; m1 = [0.5, 0.5]; a0 = st.act[sflip]; out = Tuple{Int,Float64,Float64}[]
    for s in 0:NS-1
        a = st.act[s+1]; a == 0 && continue
        y = st.Y[s+1] ? 1.0 : 0.0; yf = s + 1 == sflip ? 1.0 - y : y
        m0[a] += (y - m0[a]) / KDEC; m1[a] += (yf - m1[a]) / KDEC
        (s + 1 >= sflip && a == a0) && push!(out, (s, m1[a], m0[a]))
    end
    return out
end
function g3one((tk, fam, u), ST, TR)
    st = ST[(tk, fam, u)]; tr = TR[(tk, fam)]; P0 = predict(st, tr; allow_infeasible = tk == "obs")
    tot = 0; same = 0; lk = 0; b1tot = 0; b1n = 0; b1xt = 0; b1xn = 0; b1an = 0; bydef = 0; bysame = 0; byund = 0; byinf = 0
    # BAYES after t, over the later examples j > i: (a) finite in both histories (comparable), and whether p changed there;
    # (b) finite in the original, NaN in the flipped (exit from the domain: zero mass under every hypothesis), with or without a finite
    # change before the exit; (c) no comparable later example (the finite change is unverified); NaN in the original, finite in the flipped
    bboth = 0; bchg = 0; bexit = 0; bexitchg = 0; bexitonly = 0; bunv = 0; benter = 0
    b1miss = Dict{String,Any}[]
    exs = findall(st.isex); n = length(P0.s)
    for i in unique(round.(Int, range(1, length(exs) - 50; length = 25)))
        sflip = exs[i]   # index s + 1 of the flipped example
        Q = predict(st, tr; flip = sflip, allow_infeasible = true); tot += 1
        same += all(k -> Q.p[k][i] === P0.p[k][i] && Q.q[k][i] === P0.q[k][i], ("RATE", "B1", "B1_raw", "TAB4"))
        if isnan(P0.p["BAYES_raw"][i])
            byund += 1   # obs only: the unflipped filter is already undefined at t (zero mass under every hypothesis)
        else
            bydef += 1; bysame += all(k -> Q.p[k][i] === P0.p[k][i] && Q.q[k][i] === P0.q[k][i], ("BAYES_raw", "BAYES_clip"))
        end
        lk += Q.p["LEAK"][i] != P0.p["LEAK"][i]
        b1tot += 1; b1n += b1after(st, sflip, true) != b1after(st, sflip, false)
        anyb1 = any(j -> Q.p["B1_raw"][j] != P0.p["B1_raw"][j], i+1:n); b1an += anyb1
        nx = findnext(==(P0.a[i]), P0.a, i + 1)
        if nx !== nothing
            b1xt += 1; nxd = Q.p["B1_raw"][nx] != P0.p["B1_raw"][nx]; b1xn += nxd
            if !nxd   # P3: the next example of the action shows no difference; where did the difference in the trace end
                tl = b1trail(st, sflip); k = findfirst(x -> x[2] == x[3], tl)
                push!(b1miss, Dict{String,Any}("seed" => u, "s_flip" => P0.s[i], "s_next_example" => P0.s[nx], "later_examples" => n - i,
                    "any_later_example_B1_raw_differs" => anyb1, "updates_of_action_after_flip" => length(tl) - 1,
                    "updates_until_equal" => k === nothing ? nothing : k - 1, "s_equal" => k === nothing ? nothing : tl[k][1],
                    "updates_before_next_example" => count(x -> P0.s[i] < x[1] < P0.s[nx], tl),
                    "last_diff" => k === nothing ? nothing : (k > 1 ? tl[k-1][2] - tl[k-1][3] : nothing), "state_equal" => k === nothing ? nothing : tl[k][2]))
            end
        end
        byinf += Q.bayes.infeasible >= 0
        p0 = P0.p["BAYES_raw"]; p1 = Q.p["BAYES_raw"]
        both = [j for j in i+1:n if !isnan(p0[j]) && !isnan(p1[j])]
        chg = any(j -> p1[j] != p0[j], both)
        ex = any(j -> !isnan(p0[j]) && isnan(p1[j]), i+1:n)
        isempty(both) ? (bunv += 1) : (bboth += 1; bchg += chg)
        ex && (bexit += 1; chg ? (bexitchg += 1) : (bexitonly += 1))
        benter += any(j -> isnan(p0[j]) && !isnan(p1[j]), i+1:n)
    end
    (tk = tk, fam = fam, u = u, tot = tot, same = same, lk = lk, b1tot = b1tot, b1n = b1n, b1xt = b1xt, b1xn = b1xn, b1an = b1an, bydef = bydef, bysame = bysame,
     byund = byund, byinf = byinf, bboth = bboth, bchg = bchg, bexit = bexit, bexitchg = bexitchg, bexitonly = bexitonly, bunv = bunv, benter = benter, b1miss = b1miss)
end
function evalone((tk, fam, u), ST, TR)
    pr = predict(ST[(tk, fam, u)], TR[(tk, fam)]; allow_infeasible = tk == "obs")
    (rec = seedrec(pr, u), sumdev = pr.bayes.maxsumdev, nex = length(pr.s), inf = pr.bayes.infeasible)
end
f12(x) = @sprintf("%.12f", x)
nonan(x) = x isa AbstractDict ? Dict(k => nonan(v) for (k, v) in x) : x isa AbstractVector ? [nonan(v) for v in x] :
           x isa Tuple ? [nonan(v) for v in x] : (x isa AbstractFloat && isnan(x)) ? nothing : x   # NaN (undefined) -> null
function main()
    mkpath(OUT)
    say("S63 headroom audit, threads ", Threads.nthreads(), ", out ", relpath(OUT, EXP))
    say("G7 spec and predictions.toml = freeze-headroom-audit.txt: ", G7, "   G0 S57 code = freeze-draw-conf-code.txt: ", G0)
    # G5
    allseeds = vcat(DEV, TRAIN, EVAL)
    G5 = length(unique(allseeds)) == length(allseeds) && all(>(1005), allseeds) && !any(u -> 52000 <= u <= 52999, allseeds) && maximum(allseeds) == 1045
    say("G5 dev/train/eval disjoint, outside 1..1005 and 52xxx: ", G5); gate("G5", G5)
    # G1: S57's pilot record of L2 UNI u686 (read only), negative control u687
    d686 = S57.run_arm("L2", "UNI", 686; bits = S57.gen_bits(686))["drawer"]
    J6 = JSON.parsefile(joinpath(EXP, "draw-conf-out", "pilot", "L2_UNI_u686.json"))["draws"]
    J7 = JSON.parsefile(joinpath(EXP, "draw-conf-out", "pilot", "L2_UNI_u687.json"))["draws"]
    eqj(J) = J["t"] == d686.lt && J["chosen"] == d686.lch && J["ans"] == d686.lans && [Float64.(v) for v in J["y"]] == d686.ly
    G1 = eqj(J6) && !eqj(J7) && length(d686.lt) == 4983
    say("G1 u686 L2 UNI stat = S57's pilot record (", length(d686.lt), " draws): ", eqj(J6), "   neg: = u687's record (must be false): ", eqj(J7))
    gate("G1", G1)
    # the threshold table of the full world, its range and Φ against Simpson at a spread of thresholds
    TFULL[] = thresholds(WFULL)
    crange = extrema(TFULL[].c)
    phichk = maximum(abs(Phin(x) - simpson_phi(-Inf, x)) for x in range(crange[1], crange[2]; length = 41))
    say("thresholds c over the full world: [", @sprintf("%.6f", crange[1]), ", ", @sprintf("%.6f", crange[2]), "], max |Φ - Simpson| at 41 points ", @sprintf("%.3g", phichk))
    # G4: reduced world (P = 4, L = 4, ns = 104) through the real synth_table, exo actions of the dev seeds
    g4 = tmapv(g4one, [(u, fam) for u in DEV for fam in ("stat", "rev")])
    for x in g4
        say("G4 ", x.fam, " u", x.u, " (b_rev ", x.brev, ", Y=0 ", x.nY0, "/104): max |closed - brute| mid-block ", @sprintf("%.3g", x.mid), ", block 6 ",
            @sprintf("%.3g", x.b6), ", block 24 ", @sprintf("%.3g", x.b24), ", all steps ", @sprintf("%.3g", x.all), "; max |Σw - 1| ", @sprintf("%.3g", x.sumdev),
            x.fam == "rev" ? "   neg: constant hazard 1/19, max |diff| (must be > 1e-5) " * @sprintf("%.3g", x.neg) : "")
    end
    G4 = all(x -> x.mid <= 1e-5 && x.b6 <= 1e-5 && x.b24 <= 1e-5 && x.all <= 1e-5 && x.sumdev <= 1e-12 && (x.fam == "stat" || x.neg > 1e-5), g4) && any(x -> x.nY0 > 0, g4)
    say("G4 closed form = brute force within 1e-5 in all three phases, weights sum 1 ± 1e-12: ", G4); gate("G4", G4)
    # streams: exo and obs, stat and rev, dev + train + eval
    jobs = [(tk, fam, u) for tk in ("exo", "obs") for fam in ("stat", "rev") for u in allseeds]
    SR = tmapv(j -> j[1] == "exo" ? exo_stream(j[3], j[2]) : obs_stream(j[3], j[2]), jobs)
    ST = Dict((j[1], j[2], j[3]) => SR[i] for (i, j) in enumerate(jobs))
    # G2
    obsS = [s for s in SR if s.track == "obs"]
    revok = all(u -> (g = world_table(u, "stat"); h = world_table(u, "rev"); sr = WP.L * brev(u);
                      h[1:sr, :] == g[1:sr, :] && h[sr+1:end, 1] == g[sr+1:end, 2] && h[sr+1:end, 2] == g[sr+1:end, 1] && h != g), allseeds)
    G2 = all(s -> s.maxacts <= 1 && s.nex > 0 && s.g2bad == 0 && s.g2badsh > 0, obsS) && revok
    say("G2 obs: update steps from T0 ", sum(s.nupd for s in obsS), ", max acts per step ", maximum(s.maxacts for s in obsS), ", examples ", sum(s.nex for s in obsS),
        ", mismatches ", sum(s.g2bad for s in obsS), ", neg shifted by one step mismatches ", sum(s.g2badsh for s in obsS),
        "; rev = stat before s_rev and swapped from s_rev (and differs): ", revok, " -> ", G2)
    say("   deaths obs: stat ", count(s -> s.fam == "stat" && s.death !== nothing, obsS), ", rev ", count(s -> s.fam == "rev" && s.death !== nothing, obsS),
        " of ", length(allseeds), " each")
    gate("G2", G2)
    # obs: Y = y[a] > 0 against the world table's g[s+1, a] > 0 (a fact about the track, reported; not a gate)
    for fam in ("stat", "rev")
        mm = 0; nn = 0
        for u in allseeds
            st = ST[("obs", fam, u)]; g = world_table(u, fam)
            for s in 0:NS-1; st.act[s+1] == 0 && continue; nn += 1; st.Y[s+1] != (g[s+1, st.act[s+1]] > 0) && (mm += 1); end
        end
        say("   obs ", fam, ": update steps where Y = y[a] > 0 (the body's pool) differs from g[s, a] > 0 (the table): ", mm, " of ", nn)
    end
    # training (per track and family, train seeds only)
    TR = Dict((tk, fam) => train([ST[(tk, fam, u)] for u in TRAIN]) for tk in ("exo", "obs") for fam in ("stat", "rev"))
    for tk in ("exo", "obs"), fam in ("stat", "rev")
        t = TR[(tk, fam)]
        say("train ", tk, " ", fam, ": examples ", t.n, ", answered ", t.n1, ", RATE ", round.(t.rate; digits = 6), ", TAB4 keys seen ", count(>(0), t.tn), "/", length(t.tn))
    end
    # G3: flipping Y_t leaves every p_t; B1's and BAYES's later predictions change; LEAK changes (dev seeds, 25 examples each)
    g3jobs = [(tk, fam, u) for tk in ("exo", "obs") for fam in ("stat", "rev") for u in DEV]
    G3R = tmapv(j -> g3one(j, ST, TR), g3jobs)
    G3S = Dict{String,Any}()
    for tk in ("exo", "obs"), fam in ("stat", "rev")
        R = [x for x in G3R if x.tk == tk && x.fam == fam]; sm(f) = sum(f(x) for x in R)
        say("G3 ", tk, " ", fam, ": p_t unchanged (RATE B1 B1_raw TAB4, bitwise) ", sm(x -> x.same), "/", sm(x -> x.tot),
            "; BAYES_raw BAYES_clip p_t unchanged ", sm(x -> x.bysame), "/", sm(x -> x.bydef), " where defined (undefined at t: ", sm(x -> x.byund), ")",
            "; B1 state at the next step changed ", sm(x -> x.b1n), "/", sm(x -> x.b1tot), " (diagnostic: at the next example of the action ", sm(x -> x.b1xn), "/",
            sm(x -> x.b1xt), ", at some later example ", sm(x -> x.b1an), "/", sm(x -> x.tot), ")   neg: LEAK changed ", sm(x -> x.lk), "/", sm(x -> x.tot))
        say("   BAYES later (j > t): (a) comparable (finite in both) ", sm(x -> x.bboth), "/", sm(x -> x.tot), ", finite p changed ", sm(x -> x.bchg), "/", sm(x -> x.bboth),
            "; (b) exit from the domain (finite -> NaN, zero mass under every hypothesis) ", sm(x -> x.bexit), " (finite change before the exit ", sm(x -> x.bexitchg),
            ", exit only ", sm(x -> x.bexitonly), "); (c) no comparable later example, finite change UNVERIFIED ", sm(x -> x.bunv),
            "; NaN -> finite ", sm(x -> x.benter), "; flipped history with zero mass somewhere ", sm(x -> x.byinf))
        say("   per seed (seed: comparable/changed/exit/exit_only/unverified): ", join(["u$(x.u) $(x.bboth)/$(x.bchg)/$(x.bexit)/$(x.bexitonly)/$(x.bunv)" for x in R], "  "))
        for x in R, d in x.b1miss
            say("   P3 B1 diagnostic miss u", d["seed"], ": flipped s = ", d["s_flip"], ", next example of the action s = ", d["s_next_example"], " (non-example updates of the action between: ",
                d["updates_before_next_example"], "); B1_raw differs at some later example (of ", d["later_examples"], "): ", d["any_later_example_B1_raw_differs"],
                "; the trace equals the original's after ", d["updates_until_equal"], " later updates of the action (s = ", d["s_equal"], ", state ", d["state_equal"],
                ", last difference ", d["last_diff"], ") of ", d["updates_of_action_after_flip"])
        end
        G3S["$tk $fam"] = Dict{String,Any}("tot" => sm(x -> x.tot), "p_t_same" => sm(x -> x.same), "bayes_p_t_defined" => sm(x -> x.bydef), "bayes_p_t_same" => sm(x -> x.bysame),
            "bayes_p_t_undefined" => sm(x -> x.byund), "b1_next_state_changed" => sm(x -> x.b1n), "b1_next_example_total" => sm(x -> x.b1xt), "b1_next_example_changed" => sm(x -> x.b1xn),
            "b1_some_later_example_changed" => sm(x -> x.b1an), "leak_changed" => sm(x -> x.lk),
            "bayes_later" => Dict("by_both_tot" => sm(x -> x.bboth), "by_both_chg" => sm(x -> x.bchg), "by_exit" => sm(x -> x.bexit), "by_exit_after_finite_change" => sm(x -> x.bexitchg),
                                  "by_exit_only" => sm(x -> x.bexitonly), "unverified" => sm(x -> x.bunv), "nan_to_finite" => sm(x -> x.benter), "flipped_zero_mass" => sm(x -> x.byinf)),
            "per_seed" => [Dict("seed" => x.u, "by_both_tot" => x.bboth, "by_both_chg" => x.bchg, "by_exit" => x.bexit, "by_exit_only" => x.bexitonly, "unverified" => x.bunv) for x in R],
            "b1_next_example_misses" => reduce(vcat, [x.b1miss for x in R]; init = Dict{String,Any}[]))
    end
    exo0 = [(x.fam, x.u) for x in G3R if x.tk == "exo" && x.bboth == 0]
    isempty(exo0) || (say("G3 STOP: exo with no comparable later BAYES example (by_both_tot = 0) at ", exo0); write_log(); error("G3: exo by_both_tot = 0 at $exo0"))
    G3 = all(x -> x.tot == 25 && x.same == x.tot && x.lk == x.tot && x.b1n == x.b1tot && x.bysame == x.bydef && x.bchg == x.bboth &&
                  (x.tk == "obs" || (x.byund == 0 && x.bydef == x.tot && x.bboth > 0)), G3R)
    say("G3: ", G3); gate("G3", G3)
    say("gates before the evaluation: G0 G1 G2 G3 G4 G5 G7 all true (G6 = the rerun, G8 = core/check and bridge-protocol, outside this run)")
    # evaluation
    ejobs = [(tk, fam, u) for tk in ("exo", "obs") for fam in ("stat", "rev") for u in EVAL]
    ER = tmapv(j -> evalone(j, ST, TR), ejobs)
    REC = Dict(ejobs[i] => ER[i].rec for i in eachindex(ejobs))
    INF = Dict(ejobs[i] => ER[i].inf for i in eachindex(ejobs))
    say("eval: max |Σw - 1| over all BAYES runs (defined steps) ", @sprintf("%.3g", maximum(x.sumdev for x in ER)))
    for tk in ("exo", "obs"), fam in ("stat", "rev")
        v = [INF[(tk, fam, u)] for u in EVAL]
        say("eval ", tk, " ", fam, ": BAYES with zero mass under every hypothesis in ", count(>=(0), v), "/", length(EVAL), " seeds",
            count(>=(0), v) > 0 ? ", first such step s: " * join(v, " ") : "")
    end
    tk0 = [ejobs[i] for i in eachindex(ejobs) if ER[i].inf >= 0 && ejobs[i][1] == "exo"]
    isempty(tk0) || error("exo: the filter had zero mass under every hypothesis at $tk0")
    rows = String[join(["record_type", "track", "fam", "seed", "b_rev", "b_ctrl", "bayes_zero_mass_s", "window", "n1", "n2", "bayes_defined", "bayes_outside_clip", PREDS...], "\t")]
    for (tk, fam, u) in ejobs, wn in ("all", "wtrue", "wshuf")
        x = REC[(tk, fam, u)][wn]
        push!(rows, join(["seed", tk, fam, u, brev(u), bctrl(u), INF[(tk, fam, u)], wn, x.n[1], x.n[2], x.ndef, x.nout, [f12(x.sc[k]) for k in PREDS]...], "\t"))
    end
    S = Dict{String,Any}()
    elig_all(r) = minimum(r["all"].n) >= MINALL
    elig_rev(r) = elig_all(r) && minimum(r["wtrue"].n) >= MINWIN && minimum(r["wshuf"].n) >= MINWIN
    D(r, w) = r[w].sc["B1"] - r[w].sc["BAYES_raw"]
    for tk in ("exo", "obs")
        T = Dict{String,Any}()
        rs = [REC[(tk, "stat", u)] for u in EVAL]; rr = [REC[(tk, "rev", u)] for u in EVAL]
        es = [elig_all(r) for r in rs]; er = [elig_rev(r) for r in rr]; ep = [elig_rev(r) for r in rs]
        T["stat_all"] = axisstat([D(r, "all") for (r, e) in zip(rs, es) if e])
        T["rev_all"] = axisstat([D(r, "all") for (r, e) in zip(rr, er) if e])
        T["rev_win_spec"] = axisstat([D(r, "wtrue") - D(r, "wshuf") for (r, e) in zip(rr, er) if e])
        T["rev_win_true"] = axisstat([D(r, "wtrue") for (r, e) in zip(rr, er) if e])
        T["rev_win_shuf"] = axisstat([D(r, "wshuf") for (r, e) in zip(rr, er) if e])
        T["shuf_reset_diag"] = axisstat([D(r, "wshuf") - D(r, "all") for (r, e) in zip(rr, er) if e])
        T["stat_pseudo"] = axisstat([D(r, "wtrue") - D(r, "wshuf") for (r, e) in zip(rs, ep) if e])
        T["excluded"] = Dict("stat_all" => [EVAL[i] for i in eachindex(EVAL) if !es[i]], "rev" => [EVAL[i] for i in eachindex(EVAL) if !er[i]],
                             "stat_pseudo" => [EVAL[i] for i in eachindex(EVAL) if !ep[i]])
        # B1 vs RATE (P-S63-2): d = L(RATE) - L(B1), wins = B1 better
        T["B1_vs_RATE_stat_all"] = axisstat([r["all"].sc["RATE"] - r["all"].sc["B1"] for (r, e) in zip(rs, es) if e])
        T["B1_vs_RATE_rev_all"] = axisstat([r["all"].sc["RATE"] - r["all"].sc["B1"] for (r, e) in zip(rr, er) if e])
        # means of every predictor and the clip share
        mp = Dict{String,Any}()
        for (nm, R, E, w) in (("stat_all", rs, es, "all"), ("rev_all", rr, er, "all"), ("rev_wtrue", rr, er, "wtrue"), ("rev_wshuf", rr, er, "wshuf"))
            sel = [r for (r, e) in zip(R, E) if e]
            mp[nm] = Dict{String,Any}(k => isempty(sel) ? NaN : sum(r[w].sc[k] for r in sel) / length(sel) for k in PREDS)
            nd = sum((r[w].ndef for r in sel); init = 0)
            mp[nm]["frac_outside_clip"] = nd == 0 ? NaN : sum(r[w].nout for r in sel) / nd
        end
        T["predictor_means"] = mp
        T["stat_pseudo_pass"] = haskey(T["stat_pseudo"], "ci95") && T["stat_pseudo"]["ci95"][1] < DWIN
        T["bayes_zero_mass_seeds"] = Dict(fam => [u for u in EVAL if INF[(tk, fam, u)] >= 0] for fam in ("stat", "rev"))
        S[tk] = T
    end
    # decision (spec §3)
    axes = (("stat_all", DALL), ("rev_all", DALL), ("rev_win_spec", DWIN))
    stopax(T, ax, dl) = T[ax]["defined"] && T[ax]["detectable"] && T[ax]["ci95"][2] < dl && (ax != "rev_win_spec" || T["stat_pseudo_pass"])
    proax(T, ax, dl) = T[ax]["defined"] && T[ax]["detectable"] && T[ax]["ci9917"][1] > dl && T[ax]["p_sign"] < SIGNA && T[ax]["wins"] > T[ax]["losses"] && T["stat_pseudo_pass"]
    verdict(tks) = all(tk -> all(x -> stopax(S[tk], x...), axes), tks) ? "STOP" : any(tk -> any(x -> proax(S[tk], x...), axes), tks) ? "PROCEED" : "UNDECIDED"
    dec = Dict{String,Any}("overall" => verdict(("exo", "obs")), "exo_only" => verdict(("exo",)), "obs_only" => verdict(("obs",)),
                           "axes" => Dict(tk * " " * ax => Dict("defined" => S[tk][ax]["defined"], "stop_ok" => stopax(S[tk], ax, dl), "proceed_ok" => proax(S[tk], ax, dl))
                                          for tk in ("exo", "obs") for (ax, dl) in axes))
    S["decision"] = dec
    # predictions (P-S63-1 also needs G6 and G8, outside this run)
    sgn(T, k) = T[k]["p_sign"] < 0.05 && T[k]["wins"] > T[k]["losses"]
    tri(parts) = any(==(false), parts) ? false : any(==("undefined"), parts) ? "undefined" : true
    df(T, k, f) = T[k]["defined"] ? f(T[k]) : "undefined"
    PRD = Dict{String,Any}()
    for tk in ("exo", "obs")
        T = S[tk]
        PRD["P_S63_2 " * tk] = sgn(T, "B1_vs_RATE_stat_all") && sgn(T, "B1_vs_RATE_rev_all")
        PRD["P_S63_3 " * tk] = tri([df(T, "stat_all", a -> a["mean"] >= 0), df(T, "rev_all", a -> a["mean"] >= 0)])
        PRD["P_S63_4_stat_small " * tk] = df(T, "stat_all", a -> a["mean"] <= 0.01)
        PRD["P_S63_4_rev_spec_positive_mean " * tk] = df(T, "rev_win_spec", a -> a["mean"] > 0)
        PRD["P_S63_5 " * tk] = T["stat_pseudo"]["defined"] ? T["stat_pseudo_pass"] : "undefined"
    end
    for k in ("P_S63_2", "P_S63_3", "P_S63_4_stat_small", "P_S63_4_rev_spec_positive_mean", "P_S63_5")
        PRD[k] = tri([PRD[k * " exo"], PRD[k * " obs"]])
    end
    S["predictions"] = PRD
    S["g3"] = G3S
    S["gates"] = Dict("G0" => G0, "G1" => G1, "G2" => G2, "G3" => G3, "G4" => G4, "G5" => G5, "G7" => G7)
    S["g4"] = [Dict("seed" => x.u, "fam" => x.fam, "mid" => x.mid, "block6" => x.b6, "block24" => x.b24, "all" => x.all, "sumdev" => x.sumdev, "neg_const_hazard" => x.neg) for x in g4]
    S["train"] = Dict("$tk $fam" => Dict("n" => TR[(tk, fam)].n, "n1" => TR[(tk, fam)].n1, "rate" => TR[(tk, fam)].rate) for tk in ("exo", "obs") for fam in ("stat", "rev"))
    S["brev"] = Dict(string(u) => (brev(u), bctrl(u)) for u in EVAL)
    push!(rows, join(["record_type", "track", "axis", "n", "detectable", "mean", "ci95_lo", "ci95_hi", "ci9917_lo", "ci9917_hi", "wins", "losses", "ties", "p_sign", "min", "max"], "\t"))
    for tk in ("exo", "obs"), ax in ("stat_all", "rev_all", "rev_win_spec", "rev_win_true", "rev_win_shuf", "shuf_reset_diag", "stat_pseudo", "B1_vs_RATE_stat_all", "B1_vs_RATE_rev_all")
        a = S[tk][ax]
        push!(rows, a["n"] == 0 ? join(["axis", tk, ax, 0], "\t") : !a["defined"] ? join(["axis", tk, ax, a["n"], "undefined", "n_undefined", a["n_undefined"]], "\t") :
              join(["axis", tk, ax, a["n"], a["detectable"], f12(a["mean"]), f12(a["ci95"][1]), f12(a["ci95"][2]), f12(a["ci9917"][1]), f12(a["ci9917"][2]),
                    a["wins"], a["losses"], a["ties"], @sprintf("%.6g", a["p_sign"]), f12(a["min"]), f12(a["max"])], "\t"))
    end
    push!(rows, join(["record_type", "track", "axis", PREDS..., "frac_outside_clip"], "\t"))
    for tk in ("exo", "obs"), nm in ("stat_all", "rev_all", "rev_wtrue", "rev_wshuf")
        m = S[tk]["predictor_means"][nm]
        push!(rows, join(["mean", tk, nm, [f12(m[k]) for k in PREDS]..., f12(m["frac_outside_clip"])], "\t"))
    end
    push!(rows, join(["decision", dec["overall"], "exo_only", dec["exo_only"], "obs_only", dec["obs_only"]], "\t"))
    write(joinpath(OUT, "results.tsv"), join(rows, "\n") * "\n")
    open(joinpath(OUT, "summary.json"), "w") do io; JSON.print(io, nonan(S), 1); end
    # log
    for tk in ("exo", "obs")
        T = S[tk]
        say("== ", tk, " (excluded stat_all ", T["excluded"]["stat_all"], ", rev ", T["excluded"]["rev"], ", stat_pseudo ", T["excluded"]["stat_pseudo"], ")")
        for nm in ("stat_all", "rev_all", "rev_wtrue", "rev_wshuf")
            m = T["predictor_means"][nm]
            say("   means ", rpad(nm, 9), join([" $k " * @sprintf("%.6f", m[k]) for k in PREDS]), "  frac_outside_clip ", @sprintf("%.4f", m["frac_outside_clip"]))
        end
        for ax in ("stat_all", "rev_all", "rev_win_spec", "rev_win_true", "rev_win_shuf", "shuf_reset_diag", "stat_pseudo", "B1_vs_RATE_stat_all", "B1_vs_RATE_rev_all")
            a = T[ax]
            a["n"] == 0 && (say("   ", ax, ": no eligible seeds"); continue)
            a["defined"] || (say("   ", rpad(ax, 20), " n ", a["n"], " UNDEFINED (BAYES zero mass in ", a["n_undefined"], " seeds)"); continue)
            say("   ", rpad(ax, 20), " n ", a["n"], " mean ", @sprintf("%+.6f", a["mean"]), " CI95 [", @sprintf("%+.6f", a["ci95"][1]), ", ", @sprintf("%+.6f", a["ci95"][2]),
                "] CI99.17 [", @sprintf("%+.6f", a["ci9917"][1]), ", ", @sprintf("%+.6f", a["ci9917"][2]), "] wins ", a["wins"], " losses ", a["losses"], " ties ", a["ties"],
                " p ", @sprintf("%.4g", a["p_sign"]))
        end
        say("   STAT_PSEUDO pass (CI95 lo < delta_win): ", T["stat_pseudo"]["defined"] ? T["stat_pseudo_pass"] : "undefined")
    end
    say("decision ", JSON.json(dec))
    say("predictions (P-S63-1 needs G6 and G8 as well) ", JSON.json(PRD))
    say("results.tsv sha256 ", sha(joinpath(OUT, "results.tsv")), "   summary.json sha256 ", sha(joinpath(OUT, "summary.json")))
    other = joinpath(HERE, OUTNAME == "out" ? "out-rerun" : "out")
    if isfile(joinpath(other, "results.tsv")) && isfile(joinpath(other, "summary.json"))
        g6 = sha(joinpath(other, "results.tsv")) == sha(joinpath(OUT, "results.tsv")) && sha(joinpath(other, "summary.json")) == sha(joinpath(OUT, "summary.json"))
        say("G6 results.tsv and summary.json = ", relpath(other, EXP), "'s: ", g6)
    end
    write_log()
end
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
