# S47 P-A grid (discussion/specs/S47-synth-grid.md r3; predictions-pa-grid.md, freeze-pa-grid-smoke.txt).
# Usage (from experiments/):
#   julia --project=.. -t 16 pa_grid.jl gates   gates G1, G1g, G2, G3, G4, G5, G6 (seeds 561-564; G4 seeds 1-10)
#   julia --project=.. -t 16 pa_grid.jl smoke   timing only (seeds 561-564, 6 points), writes the estimate of the main run
#   julia --project=.. -t 16 pa_grid.jl main    evaluation 565-576, NC donors 577-588, 60 points x 2 laws (run once)
# Results: results-pa-grid-<mode>.json (one JSON object per line, one per task; a stopped run resumes from it) and .out.
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
include(joinpath(@__DIR__, "synth_world.jl"))

const LAB = normpath(joinpath(@__DIR__, ".."))
const MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode gates | smoke | main")
const T0 = 800; const STEPS = 10000
const TAUS = (500, 2000, 9200)
const COUNTAT = [T0 + x for x in TAUS]
const BASE = (U = 0.02, MCOST = 0.004, STEPS = STEPS, FEED = true, KC = 0.002, RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)
const LAWS = ("L2", "L2+SF")
law_opts(law) = law == "L2" ? BASE : merge(BASE, (SEDFADE = true,))
const NOISES = ((0, nothing), (1, 1), (1, 300), (2, 1), (2, 300))
# The 60 points in a fixed order (P, sigma, L, M, K); K = nothing is no crossing.
const POINTS = [(P = P, sigma = s, L = L, M = M, K = K) for P in (1000, 250) for (s, L) in NOISES for M in (1.5, 2.5) for K in (nothing, 250, 2000)]
ptkey(p) = "P$(p.P) s$(p.sigma) L$(p.L === nothing ? "-" : p.L) M$(p.M) K$(p.K === nothing ? "-" : p.K)"
ptdict(p) = Dict("P" => p.P, "sigma" => p.sigma, "L" => p.L, "M" => p.M, "K" => p.K)
world_opts(p, u) = merge((SCHED = synth_sched(u, p.P, p.sigma, p.L, p.M),), p.K === nothing ? (;) : (REVRK = p.K,))
const REC = (KEPTS = true, COUNTAT = COUNTAT, REPORT = true)

# the kept counts of an ORG run held at the last living value after its death (GREEDY-KC's bill, spec §4)
function holdlast(ks, death)
    death === nothing && return copy(ks)
    h = copy(ks); last = death >= 1 ? ks[death] : 0
    for t in death+1:length(h); h[t] = last; end
    return h
end
rle(v) = (r = Any[]; for x in v; (isempty(r) || r[end][1] != x) ? push!(r, Any[x, 1]) : (r[end][2] += 1); end; r)
snaptype(s) = string(hash(repr(s)); base = 16)
function summ(r)
    Dict{String,Any}("death" => r["death"], "countAt" => r["countAt"], "final" => r["final"], "rep" => r["rep"],
                     "kept" => r["kept"], "upkeep" => r["upkeep"], "spent" => r["spent"], "nActs" => r["nActs"])
end
agree(a, b) = count(t -> a[t+1] == b[t+1], T0:STEPS-1) / (STEPS - T0)
# the agreement over the steps where both are alive, [T0, min(both deaths, STEPS)); nothing if that interval is empty
function agree_alive(a, da, b, db)
    e = min(da === nothing ? STEPS : da, db === nothing ? STEPS : db)
    e <= T0 && return nothing
    return count(t -> a[t+1] == b[t+1], T0:e-1) / (e - T0)
end

const TLOCK = ReentrantLock()
function timed!(times, arm, f)
    t = @elapsed r = f()
    lock(TLOCK) do; x = get!(times, arm, [0.0, 0]); x[1] += t; x[2] += 1; end
    return r
end

# One task: (point, law) for the ORG arms and the ORG tables, or (point, "GREEDY") for GREEDY and its tables.
# evals: the windows j (columns); donors: the rows of the NC table.
function run_task(p, law, evals, donors)
    times = Dict{String,Vector{Any}}(); n = length(evals)
    out = Dict{String,Any}("key" => ptkey(p) * " | " * law, "point" => ptdict(p), "law" => law, "evals" => collect(evals), "donors" => collect(donors))
    if law == "GREEDY"
        G = Dict{Int,Any}()
        for u in unique(vcat(collect(evals), collect(donors)))
            G[u] = timed!(times, "GREEDY", () -> body_org_run("GREEDY", u, merge(BASE, world_opts(p, u), REC)))
        end
        out["GREEDY"] = Dict(string(u) => summ(G[u]) for u in keys(G))
        for (name, rows) in (("table", evals), ("nc", donors))
            S = [zeros(Int, n, n) for _ in TAUS]
            for (i, ui) in enumerate(rows), (j, uj) in enumerate(evals)
                r = (name == "table" && i == j) ? G[uj] :
                    timed!(times, "GREEDY cell", () -> body_org_run("GREEDY", uj, merge(BASE, world_opts(p, uj), REC, (REPLAYX = (acts = G[ui]["acts"],),))))
                for x in eachindex(TAUS); S[x][i, j] = r["countAt"][x]; end
            end
            out[name] = [[S[x][i, :] for i in 1:n] for x in eachindex(TAUS)]
        end
    else
        lo = law_opts(law); O = Dict{Int,Any}()
        for u in unique(vcat(collect(evals), collect(donors)))
            O[u] = timed!(times, "ORG", () -> body_org_run("ORG", u, merge(lo, world_opts(p, u), REC, (SNAPAT = T0,))))
        end
        out["ORG"] = Dict(string(u) => merge(summ(O[u]), Dict("type" => snaptype(O[u]["snap"]), "keptRLE" => rle(O[u]["keptSeries"]))) for u in keys(O))
        F = Dict{String,Any}(); Sl = Dict{String,Any}(); KCd = Dict{String,Any}()
        for u in evals
            f = timed!(times, "ORG-FIX", () -> body_org_run("ORG", u, merge(lo, world_opts(p, u), REC, (FIXAT = T0,))))
            ks = f["keptSeries"]; alive = [t for t in T0:STEPS-1 if f["death"] === nothing || t < f["death"]]
            F[string(u)] = merge(summ(f), Dict("agree" => agree(f["acts"], O[u]["acts"]), "agreeAlive" => agree_alive(f["acts"], f["death"], O[u]["acts"], O[u]["death"]), "keptConst" => length(unique(ks[t+1] for t in alive)) <= 1))
            s = timed!(times, "ORG-SIL", () -> body_org_run("ORG", u, merge(lo, world_opts(p, u), REC, (SILAT = T0,))))
            Sl[string(u)] = summ(s)
            bill = holdlast(O[u]["keptSeries"], O[u]["death"])
            k = timed!(times, "GREEDY-KC", () -> body_org_run("GREEDY", u, merge(BASE, world_opts(p, u), REC, (KCBILL = bill,))))
            KCd[string(u)] = summ(k)
        end
        out["ORG-FIX"] = F; out["ORG-SIL"] = Sl; out["GREEDY-KC"] = KCd
        for (name, rows) in (("table", evals), ("nc", donors))
            S = [zeros(Int, n, n) for _ in TAUS]
            for (i, ui) in enumerate(rows), (j, uj) in enumerate(evals)
                r = (name == "table" && i == j) ? O[uj] :
                    timed!(times, "ORG cell", () -> body_org_run("ORG", uj, merge(lo, world_opts(p, uj), REC, (REPLAYX = (acts = O[ui]["acts"], kept = O[ui]["keptSeries"]),))))
                for x in eachindex(TAUS); S[x][i, j] = r["countAt"][x]; end
            end
            out[name] = [[S[x][i, :] for i in 1:n] for x in eachindex(TAUS)]
        end
    end
    out["times"] = times
    return out
end

function run_grid(points, evals, donors, file)
    done = Set{String}()
    if isfile(file)
        for l in eachline(file)
            d = try JSON.parse(l) catch; nothing end
            d === nothing || push!(done, d["key"])
        end
    end
    tasks = [(p, law) for p in points for law in (LAWS..., "GREEDY")]
    todo = [x for x in tasks if !(ptkey(x[1]) * " | " * x[2] in done)]
    sort!(todo; by = x -> x[2] == "GREEDY")   # the heavier ORG tasks first
    println("tasks ", length(tasks), ", done ", length(tasks) - length(todo), ", threads ", Threads.nthreads()); flush(stdout)
    ch = Channel{Any}(length(todo)); for x in todo; put!(ch, x); end; close(ch)
    flock = ReentrantLock(); ndone = Threads.Atomic{Int}(0); t0 = time()
    @sync for _ in 1:Threads.nthreads()
        Threads.@spawn for (p, law) in ch
            r = run_task(p, law, evals, donors)
            lock(flock) do
                open(file, "a") do io; println(io, JSON.json(r)); end
                Threads.atomic_add!(ndone, 1)
                println(ndone[], "/", length(todo), "  ", r["key"], "  ", round(time() - t0; digits = 1), " s"); flush(stdout)
            end
        end
    end
    return time() - t0
end

# ---------------- gates ----------------
const GL = String[]
say(x...) = (s = string(x...); println(s); push!(GL, s); flush(stdout))
trace_eq(a, b) = length(a["trace"]) == length(b["trace"]) && all(isequal(a["trace"][t], b["trace"][t]) for t in eachindex(a["trace"])) &&
    a["acts"] == b["acts"] && isequal(a["death"], b["death"]) && a["log"] == b["log"] && a["spent"] === b["spent"] && a["upkeep"] === b["upkeep"] &&
    a["moved"] === b["moved"] && a["final"] == b["final"] && a["countAt"] == b["countAt"] && a["maxErr"] === b["maxErr"]
function g2_ok(f, snap)
    hs = hash(snap); ks = f["keptSeries"]; alive = [t for t in T0:STEPS-1 if f["death"] === nothing || t < f["death"]]
    return all(f["lsHash"][t+1] == hs for t in T0:STEPS-1) && length(unique(ks[t+1] for t in alive)) == 1
end
g3_ok(r) = all(isempty(r["acts"][t+1]) for t in T0:STEPS-1)
function g6_ok(k, bill)
    alive = [t for t in 0:STEPS-1 if k["death"] === nothing || t < k["death"]]
    return all(k["billSeries"][t+1] === 0.002 * bill[t+1] && k["keptSeries"][t+1] == bill[t+1] for t in alive)
end

function gates()
    seeds = 561:564
    gpts = [(P = 250, sigma = 2, L = 1, M = 1.5, K = 250), (P = 1000, sigma = 0, L = nothing, M = 2.5, K = nothing), (P = 1000, sigma = 1, L = 300, M = 2.5, K = 2000)]
    TR = (TRACE = true, KEPTS = true, COUNTAT = COUNTAT)
    res = Dict{String,Any}()
    for p in gpts
        say("== point ", ptkey(p))
        Gr = Dict(u => body_org_run("GREEDY", u, merge(BASE, world_opts(p, u), TR)) for u in seeds)
        # G1g and its negative control
        g1g = [trace_eq(Gr[u], body_org_run("GREEDY", u, merge(BASE, world_opts(p, u), TR, (REPLAYX = (acts = Gr[u]["acts"],),)))) for u in seeds]
        sh(a) = vcat(a[2:end], [Int[]]); shk(a) = vcat(a[2:end], a[end:end])
        g1gn = [trace_eq(Gr[u], body_org_run("GREEDY", u, merge(BASE, world_opts(p, u), TR, (REPLAYX = (acts = sh(Gr[u]["acts"]),),)))) for u in seeds]
        say("G1g diagonal = GREEDY_j: ", g1g, "   G5 (acts shifted by 1 step, must be false): ", g1gn)
        res[ptkey(p) * " G1g"] = all(g1g) && !any(g1gn)
        # G6 and its negative controls
        for law in LAWS
            lo = law_opts(law)
            Or = Dict(u => body_org_run("ORG", u, merge(lo, world_opts(p, u), TR, (SNAPAT = T0,))) for u in seeds)
            g1 = [trace_eq(Or[u], body_org_run("ORG", u, merge(lo, world_opts(p, u), TR, (REPLAYX = (acts = Or[u]["acts"], kept = Or[u]["keptSeries"]),)))) for u in seeds]
            g1n = [trace_eq(Or[u], body_org_run("ORG", u, merge(lo, world_opts(p, u), TR, (REPLAYX = (acts = sh(Or[u]["acts"]), kept = Or[u]["keptSeries"]),)))) for u in seeds]
            g1nk = [trace_eq(Or[u], body_org_run("ORG", u, merge(lo, world_opts(p, u), TR, (REPLAYX = (acts = Or[u]["acts"], kept = shk(Or[u]["keptSeries"])),)))) for u in seeds]
            say(law, " G1 diagonal = ORG_j: ", g1, "   G5 acts shifted (false): ", g1n, "   kept shifted (false): ", g1nk)
            # an off-diagonal cell runs (row 562, column 561)
            off = body_org_run("ORG", 561, merge(lo, world_opts(p, 561), TR, (REPLAYX = (acts = Or[562]["acts"], kept = Or[562]["keptSeries"]),)))
            say(law, " off-diagonal cell(562, 561) ran; acts after T0 = row's acts while alive: ",
                all(t -> isempty(off["acts"][t+1]) || off["acts"][t+1] == Or[562]["acts"][t+1], T0:STEPS-1))
            # G2
            Fx = Dict(u => body_org_run("ORG", u, merge(lo, world_opts(p, u), (KEPTS = true, LSTRACE = true, FIXAT = T0))) for u in seeds)
            Ol = Dict(u => body_org_run("ORG", u, merge(lo, world_opts(p, u), (KEPTS = true, LSTRACE = true))) for u in seeds)
            g2 = [g2_ok(Fx[u], Or[u]["snap"]) for u in seeds]
            g2n = [g2_ok(Ol[u], Or[u]["snap"]) for u in seeds]
            bad = Dict(u => (f = deepcopy(Fx[u]); f["keptSeries"][T0+2] += 1; f) for u in seeds)
            g2nk = [g2_ok(bad[u], Or[u]["snap"]) for u in seeds]
            g2nw = [g2_ok(Fx[u], Or[u == 564 ? 561 : u + 1]["snap"]) for u in seeds]
            say(law, " G2 ORG-FIX state = saved, kept constant: ", g2, "   neg: ORG not fixed (false): ", g2n, "  kept altered (false): ", g2nk,
                "  another window's snapshot (false unless equal type): ", g2nw)
            # prefix of ORG-FIX = ORG up to T0 (acts)
            say(law, " ORG-FIX acts before T0 = ORG's: ", [Fx[u]["acts"][1:T0] == Or[u]["acts"][1:T0] for u in seeds])
            # G3
            Sx = Dict(u => body_org_run("ORG", u, merge(lo, world_opts(p, u), (SILAT = T0,))) for u in seeds)
            g3 = [g3_ok(Sx[u]) for u in seeds]; g3n = [g3_ok(Or[u]) for u in seeds]
            say(law, " G3 ORG-SIL no act after T0: ", g3, "   neg: ORG (false): ", g3n, "   SIL acts before T0 = ORG's: ", [Sx[u]["acts"][1:T0] == Or[u]["acts"][1:T0] for u in seeds])
            # G6
            bill = Dict(u => holdlast(Or[u]["keptSeries"], Or[u]["death"]) for u in seeds)
            Kx = Dict(u => body_org_run("GREEDY", u, merge(BASE, world_opts(p, u), TR, (KCBILL = bill[u],))) for u in seeds)
            agreeOrg = [all(t -> bill[u][t+1] == Or[u]["keptSeries"][t+1], [t for t in 0:STEPS-1 if Or[u]["death"] === nothing || t < Or[u]["death"]]) for u in seeds]
            g6 = [g6_ok(Kx[u], bill[u]) for u in seeds]
            g6n = [g6_ok(Kx[u], shk(bill[u])) for u in seeds]
            four = [trace_eq(Gr[u], body_org_run("GREEDY", u, merge(BASE, world_opts(p, u), TR, (KCBILL = fill(4, STEPS),)))) for u in seeds]
            b5 = fill(4, STEPS); b5[1001] = 5
            fourn = [trace_eq(Gr[u], body_org_run("GREEDY", u, merge(BASE, world_opts(p, u), TR, (KCBILL = b5,)))) for u in seeds]
            say(law, " G6 bill = ORG kept x KC: ", g6, " (bill = ORG kept while ORG alive: ", agreeOrg, ")   neg: bill shifted (false): ", g6n,
                "   bill 4 = GREEDY: ", four, "   neg: one bill 5 (false): ", fourn)
            res[ptkey(p) * " " * law] = Dict("G1" => all(g1) && !any(g1n) && !any(g1nk), "G2" => all(g2) && !any(g2n) && !any(g2nk),
                "G3" => all(g3) && !any(g3n), "G6" => all(g6) && all(agreeOrg) && !any(g6n) && all(four) && !any(fourn))
        end
    end
    # G4: item 81 reproduced (eval_grow.jl settings, seeds 1-10)
    say("== G4 (item 81, seeds 1-10)")
    ref = JSON.parsefile(joinpath(LAB, "experiments", "results-grow81.json"))
    keysR = ("death", "meanCount", "keptEnd", "lost", "blocked", "kept", "upkeep", "answered")
    g81 = (U = 0.02, MCOST = 0.004, STEPS = 10000, FEED = true, KC = 0.002, READCUR = false)
    L2c = (RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)
    g4 = Dict{String,Any}()
    for (name, cond, wo, co) in (("seasons L2", "ORG", (;), L2c), ("random L2", "ORG", (SCHED = "random",), L2c), ("seasons GREEDY", "GREEDY", (;), (;)))
        rs = Vector{Any}(undef, 10)
        Threads.@threads for seed in 1:10
            o = merge(g81, wo, co, (PHASE = (seed - 1) * 100,), name == "random L2" ? (SCHEDSEED = seed,) : (;))
            r = body_org_run(cond, seed, o); rs[seed] = Dict(k => r[k] for k in keysR)
        end
        same = [all(k -> isequal(JSON.parse(JSON.json(rs[s][k])), ref[name][s][k]), keysR) for s in 1:10]
        other = Dict("seasons L2" => "random L2", "random L2" => "seasons L2", "seasons GREEDY" => "random GREEDY")[name]   # seasons GREEDY is the same for all seeds
        rot = [all(k -> isequal(JSON.parse(JSON.json(rs[s][k])), ref[other][s][k]), keysR) for s in 1:10]
        alive = count(x -> x["death"] === nothing, rs)
        say(name, ": equal to results-grow81.json ", count(same), "/10, alive ", alive, "/10   neg: against the entry of ", other, " (false): ", rot)
        g4[name] = (all(same), alive, !any(rot))
    end
    res["G4"] = g4[ "seasons L2"][1] && g4["random L2"][1] && g4["seasons GREEDY"][1] && g4["seasons L2"][2] == 10 && g4["random L2"][2] == 1 && g4["seasons GREEDY"][2] == 10 &&
        g4["seasons L2"][3] && g4["random L2"][3] && g4["seasons GREEDY"][3]
    say("== summary ", JSON.json(res))
    write(joinpath(LAB, "experiments", "results-pa-grid-gates.out"), join(GL, "\n") * "\n")
    write(joinpath(LAB, "experiments", "results-pa-grid-gates.json"), JSON.json(res, 2))
end

# ---------------- smoke: timing and the estimate of the main run ----------------
const SMOKE_POINTS = [(P = 1000, sigma = 0, L = nothing, M = 1.5, K = nothing), (P = 250, sigma = 0, L = nothing, M = 2.5, K = 250),
    (P = 1000, sigma = 2, L = 300, M = 2.5, K = 2000), (P = 250, sigma = 1, L = 1, M = 1.5, K = nothing),
    (P = 1000, sigma = 1, L = 300, M = 1.5, K = 250), (P = 250, sigma = 2, L = 1, M = 2.5, K = 2000)]
function smoke()
    odir = length(ARGS) >= 2 ? ARGS[2] : joinpath(LAB, "experiments")   # smoke only: another output directory (re-checks)
    file = joinpath(odir, "results-pa-grid-smoke.json")
    evals = 561:564; donors = reverse(561:564)   # smoke only: the NC rows are the same 4 windows reversed (no other seed may be used)
    wall = run_grid(SMOKE_POINTS, evals, donors, file)
    tm = Dict{String,Vector{Float64}}()
    for l in eachline(file)
        d = JSON.parse(l)
        for (a, x) in d["times"]; y = get!(tm, a, [0.0, 0.0]); y[1] += x[1]; y[2] += x[2]; end
    end
    per = Dict(a => x[1] / x[2] for (a, x) in tm)
    n = 12; nth = Threads.nthreads(); npt = length(POINTS)
    # runs of the main run per point (diagonals of the evaluation tables reuse ORG_j / GREEDY_j, gate G1 / G1g)
    cnt = Dict("ORG" => 2 * 2n, "ORG-FIX" => 2n, "ORG-SIL" => 2n, "GREEDY-KC" => 2n, "ORG cell" => 2 * (n * n - n + n * n),
               "GREEDY" => 2n, "GREEDY cell" => (n * n - n) + n * n)
    cpu = sum(cnt[a] * per[a] for a in keys(cnt)) * npt
    lines = String[]
    push!(lines, "# S47 smoke (seeds 561-564; 6 points x (L2, L2+SF, GREEDY); NC rows = the same windows reversed). Timing only; no effect, survival or p value is read.")
    push!(lines, "threads $(nth); smoke wall time $(round(wall; digits = 1)) s; Julia $(VERSION)")
    push!(lines, "seconds per run (measured under $(nth) threads, mean over the smoke runs):")
    for a in sort(collect(keys(per))); push!(lines, "  $(rpad(a, 12)) $(round(per[a]; digits = 3)) s  ($(Int(tm[a][2])) runs)"); end
    push!(lines, "main run per point: " * join(["$(a) $(cnt[a])" for a in sort(collect(keys(cnt)))], ", ") * "  = $(sum(values(cnt))) runs")
    push!(lines, "  (spec §8 Q5 counts 2 x (24 + 36 + 288) + 24 + 288 = 1008 per point; the 12 + 12 + 12 diagonal cells reuse ORG_j / GREEDY_j: $(sum(values(cnt))))")
    push!(lines, "main run: $(npt) points x $(sum(values(cnt))) = $(npt * sum(values(cnt))) runs; CPU $(round(cpu / 3600; digits = 2)) h; wall estimate with $(nth) threads $(round(cpu / nth / 3600; digits = 2)) h (tail of the last tasks not included: at most one task, ~$(round(maximum([2n*per["ORG"] + 2n*(per["ORG-FIX"]+per["ORG-SIL"]) + n*per["GREEDY-KC"] + (2n*n-n)*per["ORG cell"]]) / 60; digits = 1)) min)")
    est = cpu / nth / 3600
    push!(lines, "reduction rule (§8 Q5, threshold 48 h): estimate $(round(est; digits = 2)) h -> " * (est > 48 ? "EXCEEDS: cut in the frozen order" : "no cut"))
    write(joinpath(odir, "results-pa-grid-smoke.out"), join(lines, "\n") * "\n")
    foreach(println, lines)
end

if MODE == "gates"
    gates()
elseif MODE == "smoke"
    smoke()
elseif MODE == "main"
    file = joinpath(LAB, "experiments", "results-pa-grid-main.json")
    wall = run_grid(POINTS, 565:576, 577:588, file)
    open(joinpath(LAB, "experiments", "results-pa-grid-main.out"), "a") do io; println(io, "main: wall $(round(wall; digits = 1)) s, threads $(Threads.nthreads())"); end
else
    error("mode gates | smoke | main")
end
