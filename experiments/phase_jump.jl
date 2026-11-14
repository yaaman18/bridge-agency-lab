# S50 phase jump of the yield schedule (discussion/specs/S50-phase-jump.md r3; predictions-phase-jump.md PJ1-PJ5,
# freeze-phase-jump-smoke.txt, freeze-phase-jump.txt). body_org.jl is unchanged: the jump is a SCHED function.
# With FEED true, step t >= 800 reads SCHED at s = t - 800 (body_org.jl:40); the jump run reads bo_season(s + J) for
# t >= Tj and bo_season(s) before. J = 0 is the baseline (shared by both Tj).
# Usage (from experiments/):
#   julia --project=.. -t 16 phase_jump.jl gates   gates Z0-Z4 with negative controls (seeds 629-630)
#   julia --project=.. -t 16 phase_jump.jl smoke   timing only (seeds 629-630), writes the estimate of the main run
#   julia --project=.. -t 16 phase_jump.jl main    evaluation 631-642 (run once; resumes from results-phase-jump-main.json)
# Records per run: acts (one char per step: '0' none, '1' patch 1, '2' patch 2, '3' both), death, countAt (Tj + 1000),
# kept counts and the read yields for steps [KLO, KHI), the moved amount and the scheduled yield in [Tj, Tj + 1000),
# the T0 snapshot type (ORG) and a fingerprint of the whole run (acts, trace, learning-state hashes, records).
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON

const LAB = normpath(joinpath(@__DIR__, ".."))
const T0 = 800; const STEPS = 10000
const BASE = (U = 0.02, MCOST = 0.004, STEPS = STEPS, FEED = true, KC = 0.002, RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)
const LAWS = ("L2", "L2+SF")
const ARMS = (LAWS..., "GREEDY")
arm_opts(arm) = arm == "L2+SF" ? merge(BASE, (SEDFADE = true,)) : BASE
arm_cond(arm) = arm == "GREEDY" ? "GREEDY" : "ORG"
const TJS = (3800, 4250)
const JUMPS = (100, 300, 500, 700, 1000)
const CELLJ = (100, 300, 500, 700)
const WIN = 100; const NW = 10
const KLO = 3700; const KHI = 5250
const COUNTAT = [Tj + 1000 for Tj in TJS]
const SMOKE_SEEDS = 629:630
const EVAL_SEEDS = 631:642

# the jump schedule: world time s = t - 800
jump_sched(Tj, J) = (s, k) -> (s + T0 >= Tj ? LabCore.bo_season(s + J) : LabCore.bo_season(s))[k]
runkey(Tj, J) = J == 0 ? "J0" : "Tj$(Tj) J$(J)"
snaptype(s) = string(hash(repr(s)); base = 16)

function actcode(a)
    all(p -> p == 1 || p == 2, a) || error("act outside patches 1, 2: $a")
    return Char(48 + (1 in a ? 1 : 0) + (2 in a ? 2 : 0))
end

# One run. sched = nothing is the default (frozen seasons). The observer is read-only: it copies the pool and
# recomputes the take of body_org.jl:164 from the pool at the start of the step (= the pool at the end of t - 1).
function one_run(arm, seed, sched)
    o = merge(arm_opts(arm), (SEEN = true, KEPTS = true, TRACE = true, LSTRACE = true, SNAPAT = T0, COUNTAT = COUNTAT))
    sched === nothing || (o = merge(o, (SCHED = sched,)))
    prev = [0.0, 0.0]; takes = zeros(2, STEPS)
    obs = s -> begin
        if s.alive && !isempty(s.acting)
            for k in 1:2; s.d[k] > 0 && (takes[k, s.t+1] = min(prev[k], s.d[k] * o.U)); end
        end
        prev[1] = s.pool[1]; prev[2] = s.pool[2]
    end
    r = body_org_run(arm_cond(arm), seed, merge(o, (ON_STEP = obs,)))
    r["takes"] = takes; r["opts"] = o
    return r
end
seqsum(takes, ts) = (x = 0.0; for t in ts, k in 1:2; x += takes[k, t+1]; end; x)
moved_ok(r) = seqsum(r["takes"], 0:STEPS-1) == r["moved"]

function fingerprint(r)
    string(hash((r["acts"], r["death"], r["trace"], r["lsHash"], r["keptSeries"], r["billSeries"], r["seen"], r["countAt"],
                 r["final"], r["moved"], r["upkeep"], r["spent"], r["nActs"], r["log"], repr(r["snap"]))); base = 16)
end
function record(r, arm)
    o = r["opts"]
    Dict{String,Any}("acts" => String([actcode(a) for a in r["acts"]]), "death" => r["death"], "countAt" => r["countAt"],
        "kept" => r["keptSeries"][KLO+1:KHI], "y" => [Int(6 * r["seen"][t+1][1] + r["seen"][t+1][2]) for t in KLO:KHI-1],
        "movedWin" => Dict(string(Tj) => seqsum(r["takes"], Tj:Tj+999) for Tj in TJS),
        "schedWin" => Dict(string(Tj) => sum(LabCore.bo_season_at(t, o) for t in Tj:Tj+999) for Tj in TJS),
        "movedOK" => moved_ok(r), "final" => r["final"], "fp" => fingerprint(r),
        "type" => arm == "GREEDY" ? nothing : snaptype(r["snap"]))
end

# all runs of one (seed, arm): the baseline and the 10 jumps
function run_task(seed, arm)
    out = Dict{String,Any}("key" => "$(seed) $(arm)", "seed" => seed, "arm" => arm)
    runs = Dict{String,Any}(); t0 = time()
    runs["J0"] = record(one_run(arm, seed, jump_sched(TJS[1], 0)), arm)
    for Tj in TJS, J in JUMPS; runs[runkey(Tj, J)] = record(one_run(arm, seed, jump_sched(Tj, J)), arm); end
    out["runs"] = runs; out["seconds"] = time() - t0; out["nruns"] = length(runs)
    return out
end

function run_grid(seeds, file)
    done = Set{String}()
    if isfile(file)
        for l in eachline(file)
            d = try JSON.parse(l) catch; nothing end
            d === nothing || push!(done, d["key"])
        end
    end
    tasks = [(u, a) for u in seeds for a in ARMS]
    todo = [x for x in tasks if !("$(x[1]) $(x[2])" in done)]
    println("tasks ", length(tasks), ", done ", length(tasks) - length(todo), ", threads ", Threads.nthreads()); flush(stdout)
    ch = Channel{Any}(length(todo)); for x in todo; put!(ch, x); end; close(ch)
    flock = ReentrantLock(); ndone = Threads.Atomic{Int}(0); t0 = time()
    @sync for _ in 1:Threads.nthreads()
        Threads.@spawn for (u, a) in ch
            r = run_task(u, a)
            lock(flock) do
                open(file, "a") do io; println(io, JSON.json(r)); end
                Threads.atomic_add!(ndone, 1)
                println(ndone[], "/", length(todo), "  ", r["key"], "  ", round(time() - t0; digits = 1), " s"); flush(stdout)
            end
        end
    end
    return time() - t0
end

# ---------------- quantities (shared with check_phase_jump.jl) ----------------
dead_at(death, t) = death !== nothing && t >= death
winsteps(Tj, w) = (Tj + WIN * (w - 1)):(Tj + WIN * w - 1)
# agreement of the acts a at t + oa and b at t + ob over the steps ts; the steps where either is dead are excluded
function agree(a, da, b, db, ts, oa, ob)
    n = 0; m = 0; ex = 0
    for t in ts
        ta = t + oa; tb = t + ob
        (ta < length(a) && tb < length(b)) || error("step outside the horizon")
        if dead_at(da, ta) || dead_at(db, tb)
            ex += 1
            continue
        end
        n += 1
        a[ta+1] == b[tb+1] && (m += 1)
    end
    return (v = n == 0 ? nothing : m / n, n = n, excluded = ex)
end
qA(jmp, dj, base, db, Tj, J, w) = agree(jmp, dj, base, db, winsteps(Tj, w), 0, J)
qB(jmp, dj, base, db, Tj, J, w) = agree(jmp, dj, base, db, winsteps(Tj, w), 0, 0)
qC(base, db, Tj, J, w) = agree(base, db, base, db, winsteps(Tj, w), 0, J)
qD(base, db, Tj, J, w) = agree(base, db, base, db, winsteps(Tj, w), J, J + 1000)

# exact two-sided sign test on the paired differences x (nothing = not verifiable, 0 = tie)
function signtest(x)
    vals = [v for v in x if v !== nothing]
    pos = count(>(0), vals); neg = count(<(0), vals); n = pos + neg
    ties = length(vals) - n; miss = length(x) - length(vals)
    d = Dict{String,Any}("pos" => pos, "neg" => neg, "ties" => ties, "unverified" => miss, "n" => n)
    if isempty(vals)
        d["judge"] = "確かめられず"
        return d
    end
    k = min(pos, neg)
    p = n == 0 ? 1.0 : Float64(min(big(1), 2 * sum(binomial(big(n), i) for i in 0:k) / big(2)^n))
    d["p"] = p
    if n < 8
        d["judge"] = "検出不能"
    elseif p <= 0.05
        d["judge"] = pos > neg ? "乱れあり" : "逆"
    else
        d["judge"] = "検出不能"
    end
    return d
end

# ---------------- gates ----------------
const GL = String[]
say(x...) = (s = string(x...); println(s); push!(GL, s); flush(stdout))
sha(f) = split(read(`shasum -a 256 $(joinpath(LAB, f))`, String))[1]

function z0()
    ref = Dict{String,String}()
    for l in eachline(joinpath(LAB, "experiments", "freeze-phase-jump-smoke.txt"))
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[normpath(joinpath("experiments", m.captures[2]))] = m.captures[1])
    end
    ok = Dict(f => sha(f) == h for (f, h) in ref)
    say("Z0 shas equal freeze-phase-jump-smoke.txt: ", ok)
    neg = sha("core/body_org.jl") == ref["experiments/predictions-phase-jump.md"]
    say("Z0 neg: body_org.jl against the sha of the predictions (must be false): ", neg)
    say("Z0 shas now (circuit.jl, matter.jl for freeze-phase-jump.txt): circuit.jl ", sha("core/circuit.jl"), "  matter.jl ", sha("core/matter.jl"))
    io = IOBuffer()
    okrun = success(pipeline(Cmd(`sh core/check/run.sh`; dir = LAB); stdout = io, stderr = io))
    txt = String(take!(io))
    say("Z0 sh core/check/run.sh: ", okrun ? "exit 0" : "FAILED")
    for l in split(txt, "\n"); isempty(strip(l)) || say("   | ", l); end
    return all(values(ok)) && !neg, okrun
end

same_run(r1, r2) = all(k -> isequal(r1[k], r2[k]), ("acts", "death", "trace", "lsHash", "keptSeries", "billSeries", "seen", "countAt",
    "final", "moved", "upkeep", "spent", "nActs", "log")) && repr(r1["snap"]) == repr(r2["snap"])

function gates(skip_run_sh)
    res = Dict{String,Any}()
    say("== Z0")
    if skip_run_sh
        za = z0_shas_only(); res["Z0 shas"] = za; res["Z0 run.sh"] = "走らせていない"
    else
        za, zb = z0(); res["Z0 shas"] = za; res["Z0 run.sh"] = zb
    end
    jobs = [(u, a) for u in SMOKE_SEEDS for a in ARMS]
    R = Vector{Any}(undef, length(jobs))
    Threads.@threads for i in eachindex(jobs)
        su, sa = jobs[i]
        sd = Dict{String,Any}("none" => one_run(sa, su, nothing), "J0" => one_run(sa, su, jump_sched(TJS[1], 0)))
        for Tj in TJS, J in (100, 1000); sd[runkey(Tj, J)] = one_run(sa, su, jump_sched(Tj, J)); end
        R[i] = (su, sa, sd)
    end
    say("== Z1 (J = 0 with the SCHED function = the default run without SCHED)")
    z1 = true; z1n = true
    for (u, a, d) in R
        s = same_run(d["J0"], d["none"]); n = same_run(d[runkey(3800, 100)], d["none"])
        say("Z1 seed $u $a: J0 = none ", s, "   neg: Tj3800 J100 = none ", n, " (must be false)   death ", d["J0"]["death"])
        z1 &= s; z1n &= !n
    end
    res["Z1"] = z1; res["Z1 neg"] = z1n
    say("== Z2 (J = 1000 = J = 0; J = 100 changes the schedule from Tj on only)")
    z2 = true; z2n = true
    for (u, a, d) in R, Tj in TJS
        s = same_run(d[runkey(Tj, 1000)], d["J0"]); n = same_run(d[runkey(Tj, 100)], d["J0"])
        say("Z2 seed $u $a Tj $Tj: J1000 = J0 ", s, "   neg: J100 = J0 ", n, " (must be false)")
        z2 &= s; z2n &= !n
    end
    for Tj in TJS
        o0 = merge(BASE, (SCHED = jump_sched(Tj, 0),)); o1 = merge(BASE, (SCHED = jump_sched(Tj, 100),)); oK = merge(BASE, (SCHED = jump_sched(Tj, 1000),))
        before = count(t -> LabCore.bo_season_at(t, o0) != LabCore.bo_season_at(t, o1), 0:Tj-1)
        after = count(t -> LabCore.bo_season_at(t, o0) != LabCore.bo_season_at(t, o1), Tj:STEPS-1)
        k = count(t -> LabCore.bo_season_at(t, o0) != LabCore.bo_season_at(t, oK), 0:STEPS-1)
        nd = count(t -> LabCore.bo_season_at(t, o0) != LabCore.bo_season_at(t, BASE), 0:STEPS-1)
        say("Z2 schedule Tj $Tj: J100 differs at $before steps before Tj (must be 0), $after from Tj (must be > 0); J1000 differs at $k (must be 0); J0 vs default $nd (must be 0)")
        z2 &= before == 0 && after > 0 && k == 0 && nd == 0
    end
    res["Z2"] = z2; res["Z2 neg"] = z2n
    if !z2
        say("Z2 FAILED: the construction is wrong; stop.")
    end
    say("== Z3 (the quantities)")
    z3 = true; z3n = true
    for (u, a, d) in R
        r0 = d["J0"]; base = String([actcode(x) for x in r0["acts"]]); db = r0["death"]
        sh = base[2:end] * base[end:end]
        for Tj in TJS
            Aself = [qA(base, db, base, db, Tj, 0, w).v for w in 1:NW]; Bself = [qB(base, db, base, db, Tj, 0, w).v for w in 1:NW]
            Ash = [qA(sh, db, base, db, Tj, 0, w).v for w in 1:NW]
            jk = d[runkey(Tj, 1000)]; jm = String([actcode(x) for x in jk["acts"]]); dj = jk["death"]
            a1 = [qA(jm, dj, base, db, Tj, 1000, w).v for w in 1:NW]; c1 = [qC(base, db, Tj, 1000, w).v for w in 1:NW]
            d0 = [qD(base, db, Tj, 0, w).v for w in 1:NW]
            ok = all(x -> x === nothing || x == 1, Aself) && all(x -> x === nothing || x == 1, Bself) && isequal(a1, c1) && isequal(d0, c1)
            vs = [x for x in Ash if x !== nothing]
            okn = !isempty(vs) && any(<(1), vs)
            say("Z3 seed $u $a Tj $Tj: A(base, base, 0) = B = 1 in all live windows, A_1000 = C_1000, D_0 = C_1000: ", ok,
                "   neg: acts shifted by 1 step, A per window ", [x === nothing ? "-" : round(x; digits = 3) for x in Ash], " (some window must be < 1) ", okn)
            z3 &= ok; z3n &= okn
        end
    end
    mv = all(moved_ok(d[k]) for (_, _, d) in R for k in keys(d))
    r1 = R[1][3]["J0"]; t2 = copy(r1["takes"]); i = findfirst(>(0), t2); i === nothing || (t2[i] = 0.0)
    mvn = seqsum(t2, 0:STEPS-1) == r1["moved"]
    say("Z3 moved: the recomputed takes sum to the run's moved in every run: ", mv, "   neg: one take removed equals moved ", mvn, " (must be false)")
    res["Z3"] = z3 && mv; res["Z3 neg"] = z3n && !mvn
    say("== Z4 (sign test)")
    mk(p, q, t = 0) = vcat(fill(0.1, p), fill(-0.1, q), fill(0.0, t))
    cases = [("n12 10/2", mk(10, 2), "乱れあり"), ("n12 9/3", mk(9, 3), "検出不能"), ("n12 2/10", mk(2, 10), "逆"), ("n8 8/0", mk(8, 0), "乱れあり"),
             ("n8 7/1", mk(7, 1), "検出不能"), ("n7 7/0", mk(7, 0), "検出不能"), ("10/2 + 2 ties", mk(10, 2, 2), "乱れあり"),
             ("8/0 + 4 not verifiable", vcat(mk(8, 0), fill(nothing, 4)), "乱れあり"), ("all not verifiable", fill(nothing, 12), "確かめられず")]
    z4 = true
    for (nm, x, want) in cases
        g = signtest(x); say("Z4 $nm: ", g["judge"], " p ", get(g, "p", "-"), " (want $want)"); z4 &= g["judge"] == want
    end
    # negative control: the same test without the n >= 8 condition judges 7/0 (the gate must catch it)
    broken(x) = (g = signtest(x); n = g["n"]; k = min(g["pos"], g["neg"]); p = 2 * sum(binomial(big(n), i) for i in 0:k) / big(2)^n; p <= 0.05 ? "乱れあり" : "検出不能")
    z4n = broken(mk(7, 0)) != "検出不能"
    say("Z4 neg: the test without n >= 8 on 7/0 -> ", broken(mk(7, 0)), " (differs from the wanted 検出不能, so the gate would fail: ", z4n, ")")
    res["Z4"] = z4; res["Z4 neg"] = z4n
    say("== summary ", JSON.json(res))
    write(joinpath(LAB, "experiments", "results-phase-jump-gates.out"), join(GL, "\n") * "\n")
    write(joinpath(LAB, "experiments", "results-phase-jump-gates.json"), JSON.json(res, 2))
end
function z0_shas_only()
    ref = Dict{String,String}()
    for l in eachline(joinpath(LAB, "experiments", "freeze-phase-jump-smoke.txt"))
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[normpath(joinpath("experiments", m.captures[2]))] = m.captures[1])
    end
    ok = Dict(f => sha(f) == h for (f, h) in ref); say("Z0 shas equal freeze-phase-jump-smoke.txt: ", ok)
    return all(values(ok))
end

# ---------------- smoke: timing and the estimate of the main run ----------------
function smoke()
    file = joinpath(LAB, "experiments", "results-phase-jump-smoke.json")
    wall = run_grid(SMOKE_SEEDS, file)
    secs = Float64[]; nr = 0
    for l in eachline(file); d = JSON.parse(l); push!(secs, d["seconds"]); nr += d["nruns"]; end
    nth = Threads.nthreads(); ntask = length(EVAL_SEEDS) * length(ARMS)
    per = sum(secs) / length(secs)
    cpu = per * ntask; est = cpu / min(nth, ntask) / 3600 * cld(ntask, min(nth, ntask)) / (ntask / min(nth, ntask))
    lines = String[]
    push!(lines, "# S50 smoke (seeds 629-630; L2, L2+SF, GREEDY; J0 + 2 Tj x 5 J per task). Timing only; no effect is read.")
    push!(lines, "threads $(nth); smoke wall $(round(wall; digits = 1)) s; $(length(secs)) tasks, $(nr) runs; Julia $(VERSION)")
    push!(lines, "seconds per task (11 runs, under $(nth) threads): mean $(round(per; digits = 1)), max $(round(maximum(secs); digits = 1))")
    push!(lines, "main run: $(ntask) tasks x 11 = $(ntask * 11) runs; CPU $(round(cpu / 3600; digits = 2)) h; wall estimate (rounds of $(nth) tasks) $(round(est; digits = 3)) h")
    push!(lines, "stop rule (instruction, 6 h): estimate $(round(est; digits = 3)) h -> " * (est > 6 ? "EXCEEDS: do not start the main run" : "within"))
    write(joinpath(LAB, "experiments", "results-phase-jump-smoke.out"), join(lines, "\n") * "\n")
    foreach(println, lines)
end

if abspath(PROGRAM_FILE) == @__FILE__
    MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode gates | smoke | main")
    if MODE == "gates"
        gates(length(ARGS) >= 2 && ARGS[2] == "norunsh")
    elseif MODE == "smoke"
        smoke()
    elseif MODE == "main"
        file = joinpath(LAB, "experiments", "results-phase-jump-main.json")
        wall = run_grid(EVAL_SEEDS, file)
        open(joinpath(LAB, "experiments", "results-phase-jump-main.out"), "a") do io; println(io, "main: seeds $(EVAL_SEEDS), wall $(round(wall; digits = 1)) s, threads $(Threads.nthreads())"); end
    else
        error("mode gates | smoke | main")
    end
end
