# S53 the shape of the stake (discussion/specs/S53-stake.md r2; predictions-stake.md, freeze-stake.txt freeze 1).
# World of item 155 (synth_world.jl: P = 1000, A = 2.5, sigma = 1, L = 300, no crossing) with M(s) = 1.0 + 0.5 s,
# s in {0,1,2,3}; from T0 = 800 a levy of lambda * s * KC per step, lambda in {0, 2, 8}, taken from the body by the
# upkeep rule (evenly over the body sites, what can be paid, no carry-over, given to the port), right after the upkeep.
# Arms ORG and ORG-SIL (SILAT = T0) as in pa_grid.jl. Laws L2 and L2+SF.
# The levy is not in core/: body_org_run_stake below is made from the source text of core/body_org.jl's body_org_run
# (renamed; three insertions at anchors that must each occur once) and evaluated into LabCore. core/ is not changed.
# With LEVY = nothing every step is the one of body_org_run (gate K1 checks this bit for bit).
# Usage (from experiments/):
#   julia --project=.. -t 4 stake_grid.jl gates   gates F, K1, K2, K3 (trial windows 643-644)
#   julia --project=.. -t 4 stake_grid.jl smoke   the grid on the trial windows 643-644 (script test and timing only)
#   julia --project=.. -t 4 stake_grid.jl main    evaluation windows 645-656 (run once; needs freeze-stake-code.txt)
# Results: results-stake-<mode>.json (one JSON object per line, one per task; a stopped run resumes from it) and .out.
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
include(joinpath(@__DIR__, "synth_world.jl"))

const LAB = normpath(joinpath(@__DIR__, ".."))
const MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode gates | smoke | main")
const T0 = 800; const STEPS = 10000
const TAUS = (500, 2000, 9200)
const COUNTAT = [T0 + x for x in TAUS]
const KC = 0.002
const BASE = (U = 0.02, MCOST = 0.004, STEPS = STEPS, FEED = true, KC = KC, RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)
const LAWS = ("L2", "L2+SF")
law_opts(law) = law == "L2" ? BASE : merge(BASE, (SEDFADE = true,))
const WP = (P = 1000, sigma = 1, L = 300)
Mof(s) = 1.0 + 0.5 * s
const SS = (0, 1, 2, 3); const LAMS = (0, 2, 8)
# the 10 points: s = 0 once (no levy for any lambda), then s = 1..3 x lambda
const POINTS = vcat([(s = 0, lam = 0)], [(s = s, lam = l) for s in 1:3 for l in LAMS])
ptkey(p) = "s$(p.s) lam$(p.lam)"
levy_amount(p) = p.lam * p.s * KC
world_opts(p, u) = (SCHED = synth_sched(u, WP.P, WP.sigma, WP.L, Mof(p.s)),)
levy_opts(p; from = T0, check = false, leak = false) = (LEVY = (amount = levy_amount(p), from = from, check = check, leak = leak),)
const REC = (COUNTAT = COUNTAT, REPORT = true)
const ARMS = ("ORG", "ORG-SIL")
arm_opts(arm) = arm == "ORG" ? (;) : (SILAT = T0,)

# ---------------- body_org_run_stake: body_org_run with the levy (made from the source text of core/body_org.jl) ----------------
const BODY_ORG_SRC = read(joinpath(LAB, "core", "body_org.jl"), String)
function stake_source(src)
    i = findfirst("function body_org_run(cond::String", src); i === nothing && error("anchor: function")
    j = findnext("\nend\n", src, i[1]); j === nothing && error("anchor: end")
    f = src[i[1]:j[end]]
    function ins(f, anchor, add)
        n = length(findall(anchor, f)); n == 1 || error("anchor occurs $n times: $anchor")
        return replace(f, anchor => anchor * add)
    end
    f = replace(f, "function body_org_run(cond::String" => "function body_org_run_stake(cond::String"; count = 1)
    f = ins(f, "TRACE = _opt(o, :TRACE, false) == true\n",
        "    LEVY = _opt(o, :LEVY); levyReq = Float64[]; levyTaken = Float64[]; levyErr = [0.0, 0.0]   # S53 levy (stake_grid.jl)\n")
    f = ins(f, "            tKept = nk; tBill = cost; tUpkeep = paid\n        end\n", """
        if LEVY !== nothing
            lq = 0.0; lt = 0.0
            if alive && t >= LEVY.from
                lq = Float64(LEVY.amount)
                if LEVY.check; lb0 = sum(w.A) + sum(w.B); lp0 = w.port.reservoir; ls0 = total(w) + pool[1] + pool[2]; end
                for i in body; m = min(w.B[i], lq / length(body)); w.B[i] -= m; lt += m; end
                port_give!(w.port, LEVY.leak ? 0.5 * lt : lt)
                if LEVY.check
                    levyErr[1] = max(levyErr[1], abs((lb0 - sum(w.A) - sum(w.B)) - (w.port.reservoir - lp0)))
                    levyErr[2] = max(levyErr[2], abs(total(w) + pool[1] + pool[2] - ls0))
                end
            end
            push!(levyReq, lq); push!(levyTaken, lt)
        end
""")
    f = ins(f, "\"log\" => logv, \"acts\" => acts, ",
        "(LEVY !== nothing ? (\"levy\" => Dict{String,Any}(\"req\" => levyReq, \"taken\" => levyTaken, \"err\" => levyErr),) : ())..., ")
    return f
end
const STAKE_SRC = stake_source(BODY_ORG_SRC)
Core.eval(LabCore, Meta.parse(STAKE_SRC))
const body_org_run_stake = LabCore.body_org_run_stake

# ---------------- one run and its summary ----------------
deathw(r) = r["death"] === nothing ? 9201 : r["death"] - T0   # world time of death; 9201 = not dead by the horizon
function summ(r)
    lv = r["levy"]; req = lv["req"]; tk = lv["taken"]
    Dict{String,Any}("death" => r["death"], "deathW" => deathw(r), "countAt" => r["countAt"], "final" => r["final"], "rep" => r["rep"],
        "kept" => r["kept"], "upkeep" => r["upkeep"], "spent" => r["spent"], "nActs" => r["nActs"],
        "levyReq" => sum(req), "levyTaken" => sum(tk), "levyTakenBeforeT0" => sum(tk[1:T0]), "levySteps" => count(>(0.0), req))
end
run_arm(p, law, arm, u; kw...) = body_org_run_stake("ORG", u, merge(law_opts(law), world_opts(p, u), REC, arm_opts(arm), levy_opts(p; kw...)))

function run_task(p, law, evals)
    out = Dict{String,Any}("key" => ptkey(p) * " | " * law, "s" => p.s, "lam" => p.lam, "M" => Mof(p.s), "levyAmount" => levy_amount(p),
                           "law" => law, "evals" => collect(evals), "countAtSteps" => COUNTAT)
    t = @elapsed for arm in ARMS
        out[arm] = Dict(string(u) => summ(run_arm(p, law, arm, u)) for u in evals)
    end
    out["time"] = t
    return out
end

function run_grid(evals, file)
    done = Set{String}()
    if isfile(file)
        for l in eachline(file)
            d = try JSON.parse(l) catch; nothing end
            d === nothing || push!(done, d["key"])
        end
    end
    tasks = [(p, law) for p in POINTS for law in LAWS]
    todo = [x for x in tasks if !(ptkey(x[1]) * " | " * x[2] in done)]
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
sha(f) = split(read(`shasum -a 256 $f`, String))[1]
# copied from pa_grid.jl
trace_eq(a, b) = length(a["trace"]) == length(b["trace"]) && all(isequal(a["trace"][t], b["trace"][t]) for t in eachindex(a["trace"])) &&
    a["acts"] == b["acts"] && isequal(a["death"], b["death"]) && a["log"] == b["log"] && a["spent"] === b["spent"] && a["upkeep"] === b["upkeep"] &&
    a["moved"] === b["moved"] && a["final"] == b["final"] && a["countAt"] == b["countAt"] && a["maxErr"] === b["maxErr"]
# the same run up to the start of step T0: the end-of-step trace (acts, costs, pools, hash of the world and port) of steps 0..T0-1, the acts, and the learning state at T0
prefix_eq(a, b) = all(isequal(a["trace"][t], b["trace"][t]) for t in 1:T0) && a["acts"][1:T0] == b["acts"][1:T0] && isequal(a["snap"], b["snap"])

function freeze_ok()
    ref = Dict{String,String}()
    for l in eachline(joinpath(LAB, "experiments", "freeze-stake.txt"))
        startswith(l, "# S53 freeze 1") && empty!(ref)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    ex = joinpath(LAB, "experiments")
    return length(ref) == 2 && all(sha(joinpath(ex, f)) == h for (f, h) in ref), ref
end

function gates()
    seeds = 643:644
    TR = (TRACE = true, COUNTAT = COUNTAT, REPORT = true)
    res = Dict{String,Any}()
    okF, ref = freeze_ok()
    say("F: spec and predictions equal freeze 1 of freeze-stake.txt: ", okF, "  ", ref)
    res["F"] = okF
    res["body_org.jl sha"] = sha(joinpath(LAB, "core", "body_org.jl"))
    k1 = Bool[]; k1n = Bool[]; k2 = Bool[]; k2n = Bool[]; k3 = Bool[]; k3n = Bool[]
    for law in LAWS, arm in ARMS, u in seeds
        lo = merge(law_opts(law), arm_opts(arm))
        base(p) = body_org_run("ORG", u, merge(lo, world_opts(p, u), TR))
        # K1: the levy path with amount 0 (s = 0, or lambda = 0) = body_org_run without it; also LEVY = nothing
        for p in ((s = 0, lam = 0), (s = 0, lam = 8), (s = 3, lam = 0), (s = 1, lam = 0))
            b = base(p)
            a = body_org_run_stake("ORG", u, merge(lo, world_opts(p, u), TR, levy_opts(p)))
            push!(k1, trace_eq(a, b) && sum(a["levy"]["taken"]) == 0.0)
        end
        b3 = base((s = 3, lam = 0))
        push!(k1, trace_eq(body_org_run_stake("ORG", u, merge(lo, world_opts((s = 3, lam = 0), u), TR)), b3))
        # K1 negative control: a point with a levy (s = 1, lambda = 2) must differ from the run without it
        pn = (s = 1, lam = 2)
        push!(k1n, trace_eq(body_org_run_stake("ORG", u, merge(lo, world_opts(pn, u), TR, levy_opts(pn))), base(pn)))
        # K2: the balance of each levy step (checked inside the step); the levy must take something
        for p in ((s = 3, lam = 2), (s = 3, lam = 8))
            a = body_org_run_stake("ORG", u, merge(lo, world_opts(p, u), TR, levy_opts(p; check = true)))
            e = a["levy"]["err"]
            push!(k2, e[1] <= 1e-12 && e[2] <= 1e-12 && sum(a["levy"]["taken"]) > 0.0)
            say(law, " ", arm, " u", u, " ", ptkey(p), " K2 max|body drop - port rise| = ", e[1], ", max|change of body+port+pools| = ", e[2],
                ", taken ", sum(a["levy"]["taken"]), " of requested ", sum(a["levy"]["req"]))
            # K2 negative control: a levy that gives only half to the port
            x = body_org_run_stake("ORG", u, merge(lo, world_opts(p, u), TR, levy_opts(p; check = true, leak = true)))
            ex = x["levy"]["err"]
            push!(k2n, ex[1] <= 1e-12 && ex[2] <= 1e-12)
        end
        # K3: nothing taken before T0, and the state at T0 equals the run without the levy
        p = (s = 3, lam = 8)
        b = body_org_run("ORG", u, merge(lo, world_opts(p, u), TR, (SNAPAT = T0,)))
        a = body_org_run_stake("ORG", u, merge(lo, world_opts(p, u), TR, (SNAPAT = T0,), levy_opts(p)))
        tb = sum(a["levy"]["taken"][1:T0])
        push!(k3, tb == 0.0 && prefix_eq(a, b))
        # K3 negative control: the levy from step 0
        x = body_org_run_stake("ORG", u, merge(lo, world_opts(p, u), TR, (SNAPAT = T0,), levy_opts(p; from = 0)))
        txb = sum(x["levy"]["taken"][1:T0])
        push!(k3n, txb == 0.0 && prefix_eq(x, b))
        say(law, " ", arm, " u", u, " K3 taken before T0 = ", tb, ", state at T0 = no levy: ", prefix_eq(a, b),
            "   neg (levy from 0): taken before T0 = ", txb, ", state at T0 = no levy: ", prefix_eq(x, b))
    end
    say("K1 zero levy = body_org_run (", length(k1), " runs): ", all(k1), "   neg: s1 lam2 = no levy (must be false): ", k1n)
    say("K2 balance <= 1e-12 (", length(k2), " runs): ", all(k2), "   neg: half to the port passes (must be false): ", k2n)
    say("K3 (", length(k3), " runs): ", all(k3), "   neg: levy from 0 passes (must be false): ", k3n)
    res["K1"] = all(k1) && !any(k1n); res["K2"] = all(k2) && !any(k2n); res["K3"] = all(k3) && !any(k3n)
    say("== summary ", JSON.json(res))
    write(joinpath(LAB, "experiments", "results-stake-gates.out"), join(GL, "\n") * "\n")
    write(joinpath(LAB, "experiments", "results-stake-gates.json"), JSON.json(res, 2))
end

# main only after the code freeze: the shas of this file and check_stake.jl must equal freeze-stake-code.txt
function code_frozen()
    fz = joinpath(LAB, "experiments", "freeze-stake-code.txt")
    isfile(fz) || return false
    ref = Dict{String,String}()
    for l in eachline(fz)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    ex = joinpath(LAB, "experiments")
    return all(f -> haskey(ref, f) && sha(joinpath(ex, f)) == ref[f], ("stake_grid.jl", "check_stake.jl"))
end

if MODE == "gates"
    gates()
elseif MODE == "smoke"
    file = joinpath(LAB, "experiments", "results-stake-smoke.json")
    wall = run_grid(643:644, file)
    open(joinpath(LAB, "experiments", "results-stake-smoke.out"), "a") do io; println(io, "smoke: wall $(round(wall; digits = 1)) s, threads $(Threads.nthreads())"); end
elseif MODE == "main"
    code_frozen() || error("main needs freeze-stake-code.txt with the shas of stake_grid.jl and check_stake.jl")
    file = joinpath(LAB, "experiments", "results-stake-main.json")
    wall = run_grid(645:656, file)
    open(joinpath(LAB, "experiments", "results-stake-main.out"), "a") do io; println(io, "main: wall $(round(wall; digits = 1)) s, threads $(Threads.nthreads())"); end
else
    error("mode gates | smoke | main")
end
