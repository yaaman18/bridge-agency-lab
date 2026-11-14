# S47b re-grid of the crossing (discussion/specs/S47b-regrid.md r1; predictions-pa-regrid.md, freeze-pa-regrid.txt).
# Arms ORG, ORG-FIX, GREEDY, GREEDY-KC built as in pa_grid.jl (S47 r3 §4); pa_grid.jl runs on its ARGS when included,
# so the functions used here are copied from it (gate R1 checks the copies against results-pa-grid-main.json).
# Usage (from experiments/):
#   julia --project=.. -t 16 pa_regrid.jl gates   gates R0 (shas), R1, R2, R3 (seeds 601-602; R1 regression 565-576)
#   julia --project=.. -t 16 pa_regrid.jl smoke   timing only (seeds 601-602, 6 points), writes the estimate of the main run
#   julia --project=.. -t 16 pa_regrid.jl main    evaluation 603-614, 20 points x K (none, 2000, 1000) x laws (run once)
# Results: results-pa-regrid-<mode>.json (one JSON object per line, one per task; a stopped run resumes from it) and .out.
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
include(joinpath(@__DIR__, "synth_world.jl"))

const LAB = normpath(joinpath(@__DIR__, ".."))
const MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode gates | smoke | main")
const T0 = 800; const STEPS = 10000
const TAUS = (2000, 4000, 9200)
const COUNTAT = [T0 + x for x in TAUS]
const BASE = (U = 0.02, MCOST = 0.004, STEPS = STEPS, FEED = true, KC = 0.002, RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)
const LAWS = ("L2", "L2+SF")
law_opts(law) = law == "L2" ? BASE : merge(BASE, (SEDFADE = true,))
const NOISES = ((0, nothing), (1, 1), (1, 300), (2, 1), (2, 300))
const KS = (nothing, 2000, 1000)
# The 60 point-K in a fixed order: the 20 points (P, sigma, L, M) of S47 r3 x K.
const POINTS = [(P = P, sigma = s, L = L, M = M, K = K) for P in (1000, 250) for (s, L) in NOISES for M in (1.5, 2.5) for K in KS]
ptkey(p) = "P$(p.P) s$(p.sigma) L$(p.L === nothing ? "-" : p.L) M$(p.M) K$(p.K === nothing ? "-" : p.K)"
ptdict(p) = Dict("P" => p.P, "sigma" => p.sigma, "L" => p.L, "M" => p.M, "K" => p.K)
world_opts(p, u) = merge((SCHED = synth_sched(u, p.P, p.sigma, p.L, p.M),), p.K === nothing ? (;) : (REVRK = p.K,))
rec_opts(countat) = (KEPTS = true, COUNTAT = countat, REPORT = true)

# copied from pa_grid.jl
function holdlast(ks, death)
    death === nothing && return copy(ks)
    h = copy(ks); last = death >= 1 ? ks[death] : 0
    for t in death+1:length(h); h[t] = last; end
    return h
end
snaptype(s) = string(hash(repr(s)); base = 16)
function summ(r)
    Dict{String,Any}("death" => r["death"], "countAt" => r["countAt"], "final" => r["final"], "rep" => r["rep"],
                     "kept" => r["kept"], "upkeep" => r["upkeep"], "spent" => r["spent"], "nActs" => r["nActs"])
end
const TLOCK = ReentrantLock()
function timed!(times, arm, f)
    t = @elapsed r = f()
    lock(TLOCK) do; x = get!(times, arm, [0.0, 0]); x[1] += t; x[2] += 1; end
    return r
end

# A read-only observer of the run's receptor permutation (the ORG body aliases the run's perm, body_org.jl:85-88):
# the steps t at which the permutation differs from the one seen at the end of step t - 1.
function cross_observer()
    steps = Int[]; prev = Ref{Any}(nothing)
    f = s -> begin
        s.b === nothing && return
        pv = prev[]
        if pv === nothing
            s.b.perm == collect(1:length(s.b.perm)) || push!(steps, s.t)
        elseif s.b.perm != pv
            push!(steps, s.t)
        end
        prev[] = copy(s.b.perm)
    end
    return f, steps
end
# crossings before the reading step R (the count at R is taken at the end of step R - 1)
ncross(steps, R) = count(t -> t < R, steps)
# GREEDY has no body circuit to observe: the count is the copy of the rule of body_org.jl:101
ncross_formula(K, R) = K === nothing ? 0 : count(t -> t > T0 && (t - T0) % K == 0, 0:R-1)

# The four arms of one window. ORG and ORG-FIX carry the observed crossing steps.
function run_org(p, law, u, countat, times)
    lo = law_opts(law)
    f1, s1 = cross_observer()
    o = timed!(times, "ORG", () -> body_org_run("ORG", u, merge(lo, world_opts(p, u), rec_opts(countat), (SNAPAT = T0, ON_STEP = f1))))
    f2, s2 = cross_observer()
    x = timed!(times, "ORG-FIX", () -> body_org_run("ORG", u, merge(lo, world_opts(p, u), rec_opts(countat), (FIXAT = T0, ON_STEP = f2))))
    bill = holdlast(o["keptSeries"], o["death"])
    k = timed!(times, "GREEDY-KC", () -> body_org_run("GREEDY", u, merge(BASE, world_opts(p, u), rec_opts(countat), (KCBILL = bill,))))
    return o, s1, x, s2, k
end
run_greedy(p, u, countat, times) = timed!(times, "GREEDY", () -> body_org_run("GREEDY", u, merge(BASE, world_opts(p, u), rec_opts(countat))))

function run_task(p, law, evals)
    times = Dict{String,Vector{Any}}()
    out = Dict{String,Any}("key" => ptkey(p) * " | " * law, "point" => ptdict(p), "law" => law, "evals" => collect(evals), "countAtSteps" => COUNTAT)
    if law == "GREEDY"
        out["GREEDY"] = Dict(string(u) => merge(summ(run_greedy(p, u, COUNTAT, times)), Dict("crossBefore" => [ncross_formula(p.K, R) for R in COUNTAT])) for u in evals)
    else
        O = Dict{String,Any}(); F = Dict{String,Any}(); KCd = Dict{String,Any}()
        for u in evals
            o, s1, x, s2, k = run_org(p, law, u, COUNTAT, times)
            O[string(u)] = merge(summ(o), Dict("type" => snaptype(o["snap"]), "crossSteps" => s1, "crossBefore" => [ncross(s1, R) for R in COUNTAT]))
            F[string(u)] = merge(summ(x), Dict("crossSteps" => s2, "crossBefore" => [ncross(s2, R) for R in COUNTAT]))
            KCd[string(u)] = merge(summ(k), Dict("crossBefore" => [ncross_formula(p.K, R) for R in COUNTAT]))
        end
        out["ORG"] = O; out["ORG-FIX"] = F; out["GREEDY-KC"] = KCd
    end
    out["times"] = times
    return out
end

function run_grid(points, evals, file)
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
            r = run_task(p, law, evals)
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

# R0: the shas of the S47 files equal the last entry of freeze-pa-grid.txt (freeze 2)
function r0()
    ref = Dict{String,String}()
    for l in eachline(joinpath(LAB, "experiments", "freeze-pa-grid.txt"))
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    sha(f) = split(read(`shasum -a 256 $(joinpath(LAB, "experiments", f))`, String))[1]
    names = ("../core/body_org.jl", "pa_grid.jl", "check_pa_grid.jl", "synth_world.jl")
    ok = Dict(f => haskey(ref, f) && sha(f) == ref[f] for f in names)
    say("R0 shas equal freeze-pa-grid.txt (freeze 2): ", ok)
    # negative control: a wrong reference sha is detected
    neg = sha("pa_grid.jl") == ref["check_pa_grid.jl"]
    say("R0 neg: pa_grid.jl against the sha of check_pa_grid.jl (must be false): ", neg)
    return all(values(ok)) && !neg
end

# R1: regression against results-pa-grid-main.json (seeds 565-576, K none and 2000, two points, both laws, 4 arms)
const R1_STEPS = [T0 + 500, T0 + 2000, T0 + 4000, T0 + 9200]   # the union of the S47 and S47b reading steps
const R1_IDX = (1, 2, 4)   # T0+500, T0+2000, horizon (the S47 countAt)
function r1()
    ref = Dict{String,Any}()
    for l in eachline(joinpath(LAB, "experiments", "results-pa-grid-main.json"))
        d = JSON.parse(l); ref[d["key"]] = d
    end
    pts = [(P = 1000, sigma = 1, L = 300, M = 2.5), (P = 250, sigma = 2, L = 1, M = 1.5)]
    seeds = 565:576
    jobs = [(merge(q, (K = K,)), law, u) for q in pts for K in (nothing, 2000) for law in LAWS for u in seeds]
    gjobs = [(merge(q, (K = K,)), u) for q in pts for K in (nothing, 2000) for u in seeds]
    res = Vector{Any}(undef, length(jobs)); gres = Vector{Any}(undef, length(gjobs))
    Threads.@threads for i in eachindex(jobs)
        p, law, u = jobs[i]; o, _, x, _, k = run_org(p, law, u, R1_STEPS, Dict{String,Vector{Any}}())
        res[i] = (p, law, u, Dict("ORG" => o, "ORG-FIX" => x, "GREEDY-KC" => k))
    end
    Threads.@threads for i in eachindex(gjobs)
        p, u = gjobs[i]; gres[i] = (p, u, run_greedy(p, u, R1_STEPS, Dict{String,Vector{Any}}()))
    end
    # the new runs as (key, arm, seed) -> (countAt at the S47 steps, death)
    new = Dict{Tuple{String,String,String},Any}()
    for (p, law, u, d) in res, (arm, r) in d
        new[(ptkey(p) * " | " * law, arm, string(u))] = ([r["countAt"][i] for i in R1_IDX], r["death"])
    end
    for (p, u, r) in gres
        new[(ptkey(p) * " | GREEDY", "GREEDY", string(u))] = ([r["countAt"][i] for i in R1_IDX], r["death"])
    end
    cmp(refget) = Dict(string(k) => (v[1] == refget(k)[1] && isequal(v[2], refget(k)[2])) for (k, v) in new)
    getref(k) = (x = ref[k[1]][k[2]][k[3]]; (Int.(x["countAt"]), x["death"]))
    eq = cmp(getref)
    nOK = count(values(eq)); say("R1 regression: ", nOK, "/", length(eq), " (key, arm, seed) equal in countAt (T0+500, T0+2000, horizon) and death; ",
        "arms ", sort(unique([k[2] for k in keys(new)])), ", point-K ", length(unique([split(k[1], " | ")[1] for k in keys(new)])))
    # R3 (R1 side): the reference with one countAt shifted by 1 is detected
    kk = sort(collect(keys(new)))[1]
    shifted(k) = (r = getref(k); k == kk ? ([r[1][1] + 1; r[1][2:end]], r[2]) : r)
    eqn = cmp(shifted)
    say("R3 neg (R1): reference countAt[1] of ", kk, " shifted by 1 -> mismatches ", count(!, values(eqn)), " (must be 1)")
    return nOK == length(eq) && count(!, values(eqn)) == 1
end

# R2: crossings before the reading step, counted from the runs (ORG, ORG-FIX observed; GREEDY, GREEDY-KC by the rule)
const CANDS = (("C1", 2000, T0 + 4000, 1), ("C2", 2000, T0 + 9200, 4), ("C3", 1000, T0 + 2000, 1))
function r2()
    q = (P = 250, sigma = 1, L = 300, M = 1.5); seeds = 601:602
    obs = Dict{Any,Any}()
    jobs = [(K, law, u) for K in KS for law in LAWS for u in seeds]
    out = Vector{Any}(undef, length(jobs))
    Threads.@threads for i in eachindex(jobs)
        K, law, u = jobs[i]; _, s1, _, s2, _ = run_org(merge(q, (K = K,)), law, u, COUNTAT, Dict{String,Vector{Any}}())
        out[i] = (K, law, u, s1, s2)
    end
    ok = true; okn = true
    for (K, law, u, s1, s2) in out
        steps_ok = s1 == s2 && s1 == (K === nothing ? Int[] : collect(T0+K:K:STEPS-1))
        say("R2 K=", K === nothing ? "none" : K, " ", law, " seed ", u, ": ORG crossing steps ", s1, "  ORG-FIX same: ", s1 == s2, "  = T0+K, T0+2K, ...: ", steps_ok)
        ok &= steps_ok
        if K === nothing
            c = [ncross(s1, R) for R in COUNTAT]; say("   K none: crossings before ", COUNTAT, " = ", c, " (must be all 0)"); ok &= all(==(0), c)
        else
            for (name, k, R, want) in CANDS
                k == K || continue
                c = ncross(s1, R); cf = ncross_formula(K, R); cn = ncross(s1, T0 + K)
                say("   ", name, ": crossings before ", R, " = ", c, " (want ", want, "; GREEDY rule copy ", cf, ")   neg: before T0+K = ", cn, " (must be 0, so the gate fails there)")
                ok &= c == want && cf == want
                okn &= cn == 0 && cn != want
            end
        end
    end
    return ok, okn
end

function gates()
    res = Dict{String,Any}()
    say("== R0"); res["R0"] = r0()
    say("== R1 / R3 (R1 side)"); res["R1+R3"] = r1()
    say("== R2 / R3 (R2 side)"); a, b = r2(); res["R2"] = a; res["R3 (R2 side)"] = b
    say("== summary ", JSON.json(res))
    write(joinpath(LAB, "experiments", "results-pa-regrid-gates.out"), join(GL, "\n") * "\n")
    write(joinpath(LAB, "experiments", "results-pa-regrid-gates.json"), JSON.json(res, 2))
end

# ---------------- smoke: timing and the estimate of the main run ----------------
const SMOKE_POINTS = [(P = 1000, sigma = 0, L = nothing, M = 1.5, K = nothing), (P = 250, sigma = 0, L = nothing, M = 2.5, K = 2000),
    (P = 1000, sigma = 2, L = 300, M = 2.5, K = 1000), (P = 250, sigma = 1, L = 1, M = 1.5, K = nothing),
    (P = 1000, sigma = 1, L = 300, M = 1.5, K = 2000), (P = 250, sigma = 2, L = 1, M = 2.5, K = 1000)]
function smoke()
    file = joinpath(LAB, "experiments", "results-pa-regrid-smoke.json")
    wall = run_grid(SMOKE_POINTS, 601:602, file)
    tm = Dict{String,Vector{Float64}}()
    for l in eachline(file)
        d = JSON.parse(l)
        for (a, x) in d["times"]; y = get!(tm, a, [0.0, 0.0]); y[1] += x[1]; y[2] += x[2]; end
    end
    per = Dict(a => x[1] / x[2] for (a, x) in tm)
    n = 12; nth = Threads.nthreads(); npt = length(POINTS)
    cnt = Dict("ORG" => 2n, "ORG-FIX" => 2n, "GREEDY-KC" => 2n, "GREEDY" => n)
    cpu = sum(cnt[a] * per[a] for a in keys(cnt)) * npt
    est = cpu / nth / 3600
    lines = String[]
    push!(lines, "# S47b smoke (seeds 601-602; 6 point-K x (L2, L2+SF, GREEDY)). Timing only; no effect, survival or p value is read.")
    push!(lines, "threads $(nth); smoke wall time $(round(wall; digits = 1)) s; Julia $(VERSION)")
    push!(lines, "seconds per run (measured under $(nth) threads, mean over the smoke runs):")
    for a in sort(collect(keys(per))); push!(lines, "  $(rpad(a, 12)) $(round(per[a]; digits = 3)) s  ($(Int(tm[a][2])) runs)"); end
    push!(lines, "main run per point-K: " * join(["$(a) $(cnt[a])" for a in sort(collect(keys(cnt)))], ", ") * "  = $(sum(values(cnt))) runs")
    push!(lines, "main run: $(npt) point-K x $(sum(values(cnt))) = $(npt * sum(values(cnt))) runs; CPU $(round(cpu / 3600; digits = 2)) h; wall estimate with $(nth) threads $(round(est; digits = 2)) h")
    push!(lines, "stop rule (instruction, 6 h): estimate $(round(est; digits = 2)) h -> " * (est > 6 ? "EXCEEDS: do not start the main run" : "within"))
    write(joinpath(LAB, "experiments", "results-pa-regrid-smoke.out"), join(lines, "\n") * "\n")
    foreach(println, lines)
end

if MODE == "gates"
    gates()
elseif MODE == "smoke"
    smoke()
elseif MODE == "main"
    file = joinpath(LAB, "experiments", "results-pa-regrid-main.json")
    wall = run_grid(POINTS, 603:614, file)
    open(joinpath(LAB, "experiments", "results-pa-regrid-main.out"), "a") do io; println(io, "main: wall $(round(wall; digits = 1)) s, threads $(Threads.nthreads())"); end
else
    error("mode gates | smoke | main")
end
