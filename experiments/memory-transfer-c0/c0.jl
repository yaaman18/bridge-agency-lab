# memory-transfer-c0: the local-product memory candidate read only (C0-like) on AUE's synthetic world (predictions.toml,
# frozen in ../freeze-memory-transfer-c0.txt). An independent pilot: no closed loop, no TRM, no change to S57's code.
# S57's construction (draw_conf_grid.jl: step_draw_conf!, body_org_run_draw_conf, the Drawer, run_arm) is loaded from its
# source without its run block ("if MODE in (") into a module of its own; the source files are checked against
# freeze-draw-conf-code.txt (G0). The bits of the UNI drawer follow S55's rule gen_bits(u), in memory only.
# Usage (from experiments/):  julia --project=.. -t 8 memory-transfer-c0/c0.jl <outdir>     (out, then out-rerun)
using SHA, JSON, Printf

const HERE = @__DIR__
const EXP = normpath(joinpath(HERE, ".."))
const OUT = joinpath(HERE, length(ARGS) >= 1 ? ARGS[1] : "out")
sha(f) = bytes2hex(open(sha256, f))
const LOG = String[]
say(x...) = (s = string(x...); println(s); push!(LOG, s); flush(stdout))

# ---------------- G7: the frozen predictions ----------------
function read_sums(f)
    ref = Dict{String,String}()
    for l in eachline(f)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    return ref
end
const FREEZE = read_sums(joinpath(EXP, "freeze-memory-transfer-c0.txt"))
const G7 = get(FREEZE, "memory-transfer-c0/predictions.toml", "") == sha(joinpath(HERE, "predictions.toml"))
G7 || error("G7: predictions.toml differs from the freeze; not run")

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

# ---------------- design (predictions.toml, fixed before the runs) ----------------
const T0 = S57.T0
const TRAIN = collect(52001:52012); const EVAL = collect(52101:52124); const OOD = collect(52201:52212)
const FAM_IN = (P = 1000, sigma = 1, L = 300, M = 2.5); const FAM_OOD = (P = 600, sigma = 1, L = 300, M = 2.5)
const LO = 1 / 200; const HI = 199 / 200
const RATE_K = 8   # P_DECAY
@assert RATE_K == S57.LabCore.P_DECAY
const ETA = 1.0; const ITERS = 4000; const MINOBS = 30; const MINNT = 16
clip(p) = clamp(p, LO, HI)
sig(s) = 1 / (1 + exp(-s))
leak(m, y) = m + (y - m) / RATE_K

# ---------------- records ----------------
struct World
    seed::Int; fam::String
    ex_t::Vector{Int}; ex_a::Vector{Int}; ex_Y::Vector{Bool}; ex_y::Vector{Vector{Float64}}
    st_t::Vector{Int}; st_acts::Vector{Vector{Int}}; st_ans::Vector{Vector{Bool}}   # every step from T0 (acts and their answers)
    death::Any
end
function run_world(u, fam)
    col = Dict{Int,Any}()
    sched = S57.synth_sched(u, fam.P, fam.sigma, fam.L, fam.M)
    r = S57.run_arm("L2", "UNI", u; bits = S57.gen_bits(u),
                    extra = (SCHED = sched, ON_STEP = x -> (x.t >= T0 && (col[x.t] = (acting = copy(x.acting), y = copy(x.y), alive = x.alive))),))
    d = r["drawer"]
    ix = [i for i in eachindex(d.lt) if length(d.lcs[i]) >= 2 && d.lt[i] >= T0]
    ts = sort(collect(keys(col)))
    acts = [[p for p in col[t].acting if p <= 2] for t in ts]
    ans = [[col[t].y[p] > 0 for p in acts[k]] for (k, t) in enumerate(ts)]
    w = World(u, fam == FAM_IN ? "in" : "ood", d.lt[ix], d.lch[ix], d.lans[ix], d.ly[ix], ts, acts, ans, r["death"])
    return w, col, d
end
# G2: at every example, the step's acts are [a] and the answer is y[a] > 0; shifted by one step must mismatch
function g2(w, col)
    bad(sh) = count(i -> (c = get(col, w.ex_t[i] + sh, nothing); c === nothing || c.acting != [w.ex_a[i]] || w.ex_Y[i] != (c.y[w.ex_a[i]] > 0)), eachindex(w.ex_t))
    return (n = length(w.ex_t), bad = bad(0), badsh = bad(1))
end

# ---------------- replay of one world: traces and the features at each example ----------------
# Order at step t: predict (examples at t read the traces before t's update) -> update with t's acts and answers.
function replay(w; flip = 0)
    m = [0.5, 0.5]; ctx = Vector{NTuple{3,Float64}}(undef, length(w.ex_t))
    Y = copy(w.ex_Y); flip > 0 && (Y[flip] = !Y[flip])
    k = 1
    for (j, t) in enumerate(w.st_t)
        while k <= length(w.ex_t) && w.ex_t[k] == t
            ctx[k] = (m[1], m[2], 0.0); k += 1
        end
        for (q, p) in enumerate(w.st_acts[j])
            yv = w.st_ans[j][q]
            (flip > 0 && t == w.ex_t[flip] && p == w.ex_a[flip]) && (yv = Y[flip])
            m[p] = leak(m[p], yv ? 1.0 : 0.0)
        end
    end
    k == length(w.ex_t) + 1 || error("replay: examples not on recorded steps")
    return ctx, Y
end
fcode(a) = a == 1 ? 1.0 : -1.0
function feats(a, m1, m2; mem = true)
    c = mem ? (1.0, 2m1 - 1, 2m2 - 1) : (1.0, 0.0, 0.0)
    f = fcode(a)
    return (c[1], c[2], c[3], f * c[1], f * c[2], f * c[3])
end
score(w6, h) = sum(w6[i] * h[i] for i in 1:6)

# ---------------- predictors ----------------
mutable struct Trainer; w::Vector{Float64}; it::Int; lastgrad::Vector{Float64}; m_end::Vector{Float64}; end
struct Ind; w::Vector{Float64}; end   # the transferred individual: the coupling only (traces start at 1/2 in each world)
transfer(tr::Trainer) = Ind(copy(tr.w))
function train(worlds; mem = true)
    H = NTuple{6,Float64}[]; Yv = Float64[]; mlast = [0.5, 0.5]
    for w in worlds
        ctx, Y = replay(w)
        for i in eachindex(w.ex_t)
            push!(H, feats(w.ex_a[i], ctx[i][1], ctx[i][2]; mem = mem)); push!(Yv, Y[i] ? 1.0 : 0.0)
        end
        isempty(ctx) || (mlast = [ctx[end][1], ctx[end][2]])
    end
    n = length(Yv); wv = zeros(6); g = zeros(6)
    for it in 1:ITERS
        fill!(g, 0.0)
        for k in 1:n
            e = sig(score(wv, H[k])) - Yv[k]
            for i in 1:6; g[i] += e * H[k][i]; end
        end
        for i in 1:6; wv[i] -= ETA * g[i] / n; end
    end
    return Trainer(wv, ITERS, g ./ n, mlast), n
end
function rates(worlds)
    na = [0, 0]; ny = [0, 0]
    for w in worlds, i in eachindex(w.ex_t); na[w.ex_a[i]] += 1; ny[w.ex_a[i]] += w.ex_Y[i]; end
    return [(ny[a] + 1) / (na[a] + 2) for a in 1:2], na, ny
end
# per-example probabilities of every predictor on one world
function predict(w, rate, ind::Ind, ind0::Ind; flip = 0)
    ctx, Y = replay(w; flip = flip)
    P = Dict(k => Float64[] for k in ("RATE", "B1", "LP", "LP0", "INIT", "LEAK"))
    for i in eachindex(w.ex_t)
        a = w.ex_a[i]; m1, m2 = ctx[i][1], ctx[i][2]
        push!(P["RATE"], clip(rate[a])); push!(P["B1"], clip(a == 1 ? m1 : m2))
        push!(P["LP"], clip(sig(score(ind.w, feats(a, m1, m2)))))
        push!(P["LP0"], clip(sig(score(ind0.w, feats(a, m1, m2; mem = false)))))
        push!(P["INIT"], clip(0.5)); push!(P["LEAK"], clip(Y[i] ? 1.0 : 0.0))   # LEAK: negative control of G3 only
    end
    return P, Y
end
ll(p, y) = y ? -log(p) : -log(1 - p)

# ---------------- scoring ----------------
const PRED = ("RATE", "B1", "LP", "LP0", "INIT")
function seedscores(w, P, Y)
    out = Dict{String,Any}()
    na = [count(==(a), w.ex_a) for a in 1:2]; nneg = [count(i -> w.ex_a[i] == a && !Y[i], eachindex(Y)) for a in 1:2]
    out["n"] = na; out["neg"] = nneg; out["excluded"] = minimum(na) < MINOBS
    for k in PRED
        L = [na[a] == 0 ? NaN : sum(ll(P[k][i], Y[i]) for i in eachindex(Y) if w.ex_a[i] == a) / na[a] for a in 1:2]
        out[k] = (L = L, s = (L[1] + L[2]) / 2)
    end
    return out
end
function signtest(wins, losses)
    n = wins + losses; n == 0 && return 1.0
    k = min(wins, losses)
    p = 2 * sum(binomial(big(n), big(i)) for i in 0:k) / big(2)^n
    return Float64(min(big(1), p))
end
function compare(S, x, yk; minnt = MINNT)
    inc = [s for s in S if !s["excluded"]]
    d = [s[x].s - s[yk].s for s in inc]
    wins = count(<(0), d); losses = count(>(0), d); ties = count(==(0), d)
    p = signtest(wins, losses)
    verdict = (wins + losses) < minnt ? "undetectable" : (p < 0.05 && wins > losses) ? "superior" : (p < 0.05 && losses > wins) ? "inferior" : "not superior"
    sd = sort(d)
    return (x = x, y = yk, nseeds = length(inc), wins = wins, losses = losses, ties = ties, p = p, verdict = verdict,
            med = isempty(sd) ? NaN : (sd[(length(sd)+1)÷2] + sd[length(sd)÷2+1]) / 2, lo = isempty(sd) ? NaN : sd[1], hi = isempty(sd) ? NaN : sd[end])
end

# ---------------- main ----------------
function tmapv(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads for i in eachindex(xs); out[i] = f(xs[i]); end
    return out
end
function main()
    mkpath(joinpath(OUT, "records"))
    say("memory-transfer-c0, threads ", Threads.nthreads(), ", out ", relpath(OUT, EXP))
    say("G7 predictions.toml = freeze: ", G7, "   G0 S57 code = freeze-draw-conf-code.txt: ", G0)
    # G5
    G5 = isempty(intersect(TRAIN, EVAL)) && isempty(intersect(TRAIN, OOD)) && isempty(intersect(EVAL, OOD)) && all(>(885), vcat(TRAIN, EVAL, OOD))
    say("G5 seed sets disjoint and outside 1..885: ", G5)
    # G1: reproduce S57's stored pilot record of L2 UNI u686 (read only)
    _, _, d686 = run_world(686, FAM_IN)
    J6 = JSON.parsefile(joinpath(EXP, "draw-conf-out", "pilot", "L2_UNI_u686.json"))["draws"]
    J7 = JSON.parsefile(joinpath(EXP, "draw-conf-out", "pilot", "L2_UNI_u687.json"))["draws"]
    eqj(J) = J["t"] == d686.lt && J["chosen"] == d686.lch && J["ans"] == d686.lans && [Float64.(v) for v in J["y"]] == d686.ly
    G1 = eqj(J6) && !eqj(J7)
    say("G1 u686 L2 UNI = S57's pilot record (", length(d686.lt), " draws): ", eqj(J6), "   neg: = u687's record (must be false): ", eqj(J7))
    # worlds
    jobs = vcat([(u, FAM_IN) for u in TRAIN], [(u, FAM_IN) for u in EVAL], [(u, FAM_OOD) for u in OOD])
    R = tmapv(j -> run_world(j...), jobs)
    W = Dict(j[1] => R[i][1] for (i, j) in enumerate(jobs))
    g2s = [g2(R[i][1], R[i][2]) for i in eachindex(jobs)]
    G2 = all(x -> x.n > 0 && x.bad == 0 && x.badsh > 0, g2s)
    say("G2 examples: acts = [a] and Y = y[a] > 0 at every example: ", G2, " (examples ", sum(x.n for x in g2s), ", mismatches ", sum(x.bad for x in g2s),
        ", neg shifted by one step mismatches ", sum(x.badsh for x in g2s), ")")
    for w in values(W)
        open(joinpath(OUT, "records", "$(w.fam)_u$(w.seed).tsv"), "w") do io
            println(io, "t\ta\tY\ty1\ty2")
            for i in eachindex(w.ex_t); println(io, w.ex_t[i], "\t", w.ex_a[i], "\t", Int(w.ex_Y[i]), "\t", w.ex_y[i][1], "\t", w.ex_y[i][2]); end
        end
    end
    # training on the training worlds only
    tw = [W[u] for u in TRAIN]
    rate, na, ny = rates(tw)
    tr, ntr = train(tw); tr0, _ = train(tw; mem = false)
    ind = transfer(tr); ind0 = transfer(tr0)
    say("train: examples ", ntr, ", per action ", na, ", answered ", ny, ", answer share ", @sprintf("%.4f", sum(ny) / sum(na)),
        ", deaths ", count(w -> w.death !== nothing, tw), "/", length(tw))
    say("RATE ", rate, "   LP w ", round.(tr.w; digits = 4), "   LP0 w ", round.(tr0.w; digits = 4))
    # G4: the trainer's untransferred state does not reach the predictions; neg: one sign of w
    trx = deepcopy(tr); trx.it = -1; trx.lastgrad .= 1e6; trx.m_end .= [0.0, 1.0]
    neg = Ind(copy(tr.w)); neg.w[2] = -neg.w[2]
    g4 = [(predict(W[u], rate, transfer(trx), ind0)[1]["LP"] == predict(W[u], rate, ind, ind0)[1]["LP"],
           predict(W[u], rate, neg, ind0)[1]["LP"] != predict(W[u], rate, ind, ind0)[1]["LP"]) for u in EVAL[1:4]]
    G4 = all(x -> x[1] && x[2], g4)
    say("G4 transfer: untransferred trainer state perturbed, predictions equal: ", all(first, g4), "   neg: w[2] sign flipped, predictions differ: ", all(last, g4))
    # G3: flipping Y_u leaves p_u; B1's next p of the same action changes; LEAK must change
    g3 = Bool[]; g3next = Bool[]; g3leak = Bool[]
    for u in EVAL[1:4]
        w = W[u]; P, _ = predict(w, rate, ind, ind0)
        for i in unique(round.(Int, range(1, length(w.ex_t) - 50; length = 25)))
            Q, _ = predict(w, rate, ind, ind0; flip = i)
            push!(g3, all(k -> Q[k][i] == P[k][i], ("RATE", "B1", "LP", "LP0", "INIT")))
            push!(g3leak, Q["LEAK"][i] != P["LEAK"][i])
            nx = findnext(==(w.ex_a[i]), w.ex_a, i + 1)
            nx === nothing || push!(g3next, Q["B1"][nx] != P["B1"][nx] || (P["B1"][nx] in (LO, HI)))
        end
    end
    G3 = all(g3) && all(g3next) && all(g3leak)
    say("G3 leak: p_u unchanged by flipping Y_u at ", length(g3), " examples: ", all(g3), ", B1's next p of the action changed (or clipped): ", all(g3next),
        "   neg: LEAK changed (must be true): ", all(g3leak))
    # scoring
    rows = String["set\tseed\tpredictor\tn1\tn2\tneg1\tneg2\texcluded\tL1\tL2\tscore"]
    sets = Dict("eval" => EVAL, "ood" => OOD, "train" => TRAIN)
    SS = Dict{String,Vector{Any}}()
    for set in ("train", "eval", "ood")
        SS[set] = Any[]
        for u in sets[set]
            w = W[u]; P, Y = predict(w, rate, ind, ind0)
            s = seedscores(w, P, Y); s["seed"] = u; push!(SS[set], s)
            for k in PRED
                push!(rows, join([set, u, k, s["n"][1], s["n"][2], s["neg"][1], s["neg"][2], s["excluded"],
                                  @sprintf("%.12f", s[k].L[1]), @sprintf("%.12f", s[k].L[2]), @sprintf("%.12f", s[k].s)], "\t"))
            end
        end
    end
    push!(rows, "comparison\tset\tx\ty\tnseeds\twins\tlosses\tties\tp\tverdict\tmedian_diff\tmin_diff\tmax_diff")
    CMP = [("eval", "B1", "RATE"), ("eval", "LP", "RATE"), ("eval", "LP", "B1"), ("eval", "LP", "LP0"), ("eval", "INIT", "RATE"),
           ("ood", "B1", "RATE"), ("ood", "LP", "RATE"), ("ood", "LP", "B1"), ("ood", "LP", "LP0"), ("ood", "INIT", "RATE")]
    C = Dict{Tuple{String,String,String},Any}()
    for (set, x, yk) in CMP
        c = compare(SS[set], x, yk; minnt = set == "eval" ? MINNT : 0); C[(set, x, yk)] = c
        push!(rows, join(["cmp", set, x, yk, c.nseeds, c.wins, c.losses, c.ties, @sprintf("%.6g", c.p), c.verdict,
                          @sprintf("%.6g", c.med), @sprintf("%.6g", c.lo), @sprintf("%.6g", c.hi)], "\t"))
    end
    write(joinpath(OUT, "results.tsv"), join(rows, "\n") * "\n")
    for set in ("eval", "ood")
        S = SS[set]; ex = count(s -> s["excluded"], S)
        say(set, ": seeds ", length(S), ", excluded ", ex, " (", join([s["seed"] for s in S if s["excluded"]], " "), "), examples ", sum(sum(s["n"]) for s in S),
            ", unanswered ", sum(sum(s["neg"]) for s in S), ", deaths ", count(u -> W[u].death !== nothing, sets[set]))
        for k in PRED
            v = [s[k].s for s in S if !s["excluded"]]
            say("  ", rpad(k, 5), " mean seed score ", @sprintf("%.5f", sum(v) / length(v)))
        end
    end
    for (set, x, yk) in CMP
        c = C[(set, x, yk)]
        say("cmp ", set, " ", x, " vs ", yk, ": wins ", c.wins, " losses ", c.losses, " ties ", c.ties, " (seeds ", c.nseeds, "), p ", @sprintf("%.4g", c.p),
            " -> ", c.verdict, ", score diff median ", @sprintf("%.5f", c.med), " [", @sprintf("%.5f", c.lo), ", ", @sprintf("%.5f", c.hi), "]")
    end
    trshare = sum(ny) / sum(na); negEval = sum(sum(s["neg"]) for s in SS["eval"])
    V1 = trshare >= 0.95 && negEval >= 200
    pr = Dict("V1" => V1, "P1" => C[("eval", "B1", "RATE")].verdict == "superior", "P2" => C[("eval", "LP", "RATE")].verdict == "superior",
              "P3" => C[("eval", "LP", "B1")].verdict == "superior", "P4" => C[("eval", "LP", "LP0")].verdict == "superior",
              "P5" => C[("eval", "INIT", "RATE")].losses == C[("eval", "INIT", "RATE")].nseeds,
              "P6" => all(k -> (c = C[("ood", "LP", k)]; c.wins > c.nseeds / 2), ("RATE", "B1")))
    gates = Dict("G0" => G0, "G1" => G1, "G2" => G2, "G3" => G3, "G4" => G4, "G5" => G5, "G7" => G7)
    say("gates ", JSON.json(gates))
    say("predictions (P7 needs G6 = the rerun) ", JSON.json(pr))
    say("results.tsv sha256 ", sha(joinpath(OUT, "results.tsv")))
    write(joinpath(OUT, "results.out"), join(LOG, "\n") * "\n")
end
main()
