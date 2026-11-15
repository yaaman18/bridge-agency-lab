# S53b the worth of updating after T0 against the amount of others (discussion/specs/S53b-stake-fix.md r2;
# predictions-stake-fix.md r2; freeze-stake-fix.txt freeze 1).
# World, levy, laws and the 10 points as in stake_grid.jl (S53 r2). Arms ORG and ORG-FIX (FIXAT = T0, as in pa_grid.jl).
# body_org_run_stake is made from the source text of core/body_org.jl exactly as in stake_grid.jl (stake_source copied);
# core/ is not changed. stake_grid.jl is not included (it runs its own mode at load).
# Usage (from experiments/):
#   julia --project=.. -t 4 stake_fix_grid.jl gates   gates F, K1, K2, K3 (both arms), K4 (trial windows 643-644)
#   julia --project=.. -t 4 stake_fix_grid.jl smoke   the grid on the trial windows 643-644 (script test only)
#   julia --project=.. -t 4 stake_fix_grid.jl main    evaluation windows 657-668 (run once; needs freeze-stake-fix-code.txt)
# Results: results-stake-fix-<mode>.json (one JSON object per line, one per task; a stopped run resumes from it) and .out.
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
const LAMS = (0, 2, 8)
const POINTS = vcat([(s = 0, lam = 0)], [(s = s, lam = l) for s in 1:3 for l in LAMS])
ptkey(p) = "s$(p.s) lam$(p.lam)"
levy_amount(p) = p.lam * p.s * KC
world_opts(p, u) = (SCHED = synth_sched(u, WP.P, WP.sigma, WP.L, Mof(p.s)),)
levy_opts(p; from = T0, check = false, leak = false) = (LEVY = (amount = levy_amount(p), from = from, check = check, leak = leak),)
const REC = (COUNTAT = COUNTAT, REPORT = true, KEPTS = true)
const ARMS = ("ORG", "ORG-FIX")
arm_opts(arm) = arm == "ORG" ? (;) : (FIXAT = T0,)
const SMOKE = 643:644; const EVALS = 657:668

# ---------------- body_org_run_stake (copied from stake_grid.jl) ----------------
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
deathw(r) = r["death"] === nothing ? 9201 : r["death"] - T0
# share of steps T0..STEPS-1 with the same acts (as pa_grid.jl agree), and over the steps where both are alive (agree_alive)
agree(a, b) = count(t -> a[t+1] == b[t+1], T0:STEPS-1) / (STEPS - T0)
function agree_alive(a, da, b, db)
    e = min(da === nothing ? STEPS : da, db === nothing ? STEPS : db)
    e <= T0 && return nothing
    return count(t -> a[t+1] == b[t+1], T0:e-1) / (e - T0)
end
alive_steps(r) = [t for t in T0:STEPS-1 if r["death"] === nothing || t < r["death"]]
kept_const(r) = length(unique(r["keptSeries"][t+1] for t in alive_steps(r))) <= 1
function summ(r)
    lv = r["levy"]; req = lv["req"]; tk = lv["taken"]
    Dict{String,Any}("death" => r["death"], "deathW" => deathw(r), "countAt" => r["countAt"], "final" => r["final"], "rep" => r["rep"],
        "kept" => r["kept"], "upkeep" => r["upkeep"], "spent" => r["spent"], "nActs" => r["nActs"],
        "levyReq" => sum(req), "levyTaken" => sum(tk), "levyTakenBeforeT0" => sum(tk[1:T0]), "levySteps" => count(>(0.0), req),
        "keptConst" => kept_const(r), "keptAtT0" => r["keptSeries"][T0+1])
end
run_arm(p, law, arm, u; kw...) = body_org_run_stake("ORG", u, merge(law_opts(law), world_opts(p, u), REC, arm_opts(arm), levy_opts(p; kw...)))

function run_task(p, law, evals)
    out = Dict{String,Any}("key" => ptkey(p) * " | " * law, "s" => p.s, "lam" => p.lam, "M" => Mof(p.s), "levyAmount" => levy_amount(p),
                           "law" => law, "evals" => collect(evals), "countAtSteps" => COUNTAT)
    O = Dict{String,Any}(); F = Dict{String,Any}()
    t = @elapsed for u in evals
        o = run_arm(p, law, "ORG", u); f = run_arm(p, law, "ORG-FIX", u)
        O[string(u)] = summ(o)
        F[string(u)] = merge(summ(f), Dict{String,Any}("agree" => agree(f["acts"], o["acts"]),
            "agreeAlive" => agree_alive(f["acts"], f["death"], o["acts"], o["death"])))
    end
    out["ORG"] = O; out["ORG-FIX"] = F; out["time"] = t
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
trace_eq(a, b) = length(a["trace"]) == length(b["trace"]) && all(isequal(a["trace"][t], b["trace"][t]) for t in eachindex(a["trace"])) &&
    a["acts"] == b["acts"] && isequal(a["death"], b["death"]) && a["log"] == b["log"] && a["spent"] === b["spent"] && a["upkeep"] === b["upkeep"] &&
    a["moved"] === b["moved"] && a["final"] == b["final"] && a["countAt"] == b["countAt"] && a["maxErr"] === b["maxErr"]
prefix_eq(a, b) = all(isequal(a["trace"][t], b["trace"][t]) for t in 1:T0) && a["acts"][1:T0] == b["acts"][1:T0] && isequal(a["snap"], b["snap"])
# pa_grid.jl G2: the learning state at the end of every step from T0 equals the saved one, and the kept count is constant while alive
function g2_ok(f, snap)
    hs = hash(snap); ks = f["keptSeries"]; alive = alive_steps(f)
    return all(f["lsHash"][t+1] == hs for t in T0:STEPS-1) && length(unique(ks[t+1] for t in alive)) == 1
end
departs(r, snap) = any(r["lsHash"][t+1] != hash(snap) for t in T0:STEPS-1)

function freeze_ok()
    ref = Dict{String,String}()
    for l in eachline(joinpath(LAB, "experiments", "freeze-stake-fix.txt"))
        startswith(l, "# S53b freeze 1") && empty!(ref)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    ex = joinpath(LAB, "experiments")
    return length(ref) == 2 && all(sha(joinpath(ex, f)) == h for (f, h) in ref), ref
end

function gates()
    seeds = SMOKE
    TR = (TRACE = true, COUNTAT = COUNTAT, REPORT = true)
    res = Dict{String,Any}()
    okF, ref = freeze_ok()
    say("F: spec and predictions equal freeze 1 of freeze-stake-fix.txt: ", okF, "  ", ref)
    res["F"] = okF
    res["body_org.jl sha"] = sha(joinpath(LAB, "core", "body_org.jl"))
    k1 = Bool[]; k1n = Bool[]; k2 = Bool[]; k2n = Bool[]; k3 = Bool[]; k3n = Bool[]
    for law in LAWS, arm in ARMS, u in seeds
        lo = merge(law_opts(law), arm_opts(arm))
        base(p) = body_org_run("ORG", u, merge(lo, world_opts(p, u), TR))
        for p in ((s = 0, lam = 0), (s = 0, lam = 8), (s = 3, lam = 0), (s = 1, lam = 0))
            b = base(p)
            a = body_org_run_stake("ORG", u, merge(lo, world_opts(p, u), TR, levy_opts(p)))
            push!(k1, trace_eq(a, b) && sum(a["levy"]["taken"]) == 0.0)
        end
        b3 = base((s = 3, lam = 0))
        push!(k1, trace_eq(body_org_run_stake("ORG", u, merge(lo, world_opts((s = 3, lam = 0), u), TR)), b3))
        pn = (s = 1, lam = 2)
        push!(k1n, trace_eq(body_org_run_stake("ORG", u, merge(lo, world_opts(pn, u), TR, levy_opts(pn))), base(pn)))
        for p in ((s = 3, lam = 2), (s = 3, lam = 8))
            a = body_org_run_stake("ORG", u, merge(lo, world_opts(p, u), TR, levy_opts(p; check = true)))
            e = a["levy"]["err"]
            push!(k2, e[1] <= 1e-12 && e[2] <= 1e-12 && sum(a["levy"]["taken"]) > 0.0)
            say(law, " ", arm, " u", u, " ", ptkey(p), " K2 max|body drop - port rise| = ", e[1], ", max|change of body+port+pools| = ", e[2],
                ", taken ", sum(a["levy"]["taken"]), " of requested ", sum(a["levy"]["req"]))
            x = body_org_run_stake("ORG", u, merge(lo, world_opts(p, u), TR, levy_opts(p; check = true, leak = true)))
            ex = x["levy"]["err"]
            push!(k2n, ex[1] <= 1e-12 && ex[2] <= 1e-12)
        end
        p = (s = 3, lam = 8)
        b = body_org_run("ORG", u, merge(lo, world_opts(p, u), TR, (SNAPAT = T0,)))
        a = body_org_run_stake("ORG", u, merge(lo, world_opts(p, u), TR, (SNAPAT = T0,), levy_opts(p)))
        tb = sum(a["levy"]["taken"][1:T0])
        push!(k3, tb == 0.0 && prefix_eq(a, b))
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
    # K4: every point, both laws, the trial windows, with the levy of the point
    combos = [(p, law, u) for p in POINTS for law in LAWS for u in seeds]
    K4 = Vector{Any}(undef, length(combos))
    KR = (TRACE = true, KEPTS = true, LSTRACE = true, SNAPAT = T0, COUNTAT = COUNTAT)
    Threads.@threads for i in eachindex(combos)
        p, law, u = combos[i]
        lo = merge(law_opts(law), world_opts(p, u), KR, levy_opts(p))
        o = body_org_run_stake("ORG", u, lo)
        f = body_org_run_stake("ORG", u, merge(lo, (FIXAT = T0,)))
        bad = deepcopy(f); bad["keptSeries"][T0+2] += 1
        K4[i] = (key = ptkey(p) * " " * law * " u$u", prefix = prefix_eq(f, o), fixed = g2_ok(f, o["snap"]),
                 negDeparts = departs(o, o["snap"]), negG2org = g2_ok(o, o["snap"]), negKept = g2_ok(bad, o["snap"]))
    end
    for k in K4
        say("K4 ", k.key, ": FIX state at T0 = ORG: ", k.prefix, ", FIX state = saved and kept constant after T0: ", k.fixed,
            "   neg: ORG departs from saved (must be true): ", k.negDeparts, ", G2 on ORG (must be false): ", k.negG2org,
            ", kept altered (must be false): ", k.negKept)
    end
    k4 = all(k -> k.prefix && k.fixed, K4)
    k4n = all(k -> k.negDeparts && !k.negG2org && !k.negKept, K4)
    say("K4 (", length(K4), " pairs): ", k4, "   negative controls behave: ", k4n)
    res["K4"] = k4 && k4n
    say("== summary ", JSON.json(res))
    write(joinpath(LAB, "experiments", "results-stake-fix-gates.out"), join(GL, "\n") * "\n")
    write(joinpath(LAB, "experiments", "results-stake-fix-gates.json"), JSON.json(res, 2))
end

# main only after the code freeze: the shas of this file and check_stake_fix.jl must equal freeze-stake-fix-code.txt
function code_frozen()
    fz = joinpath(LAB, "experiments", "freeze-stake-fix-code.txt")
    isfile(fz) || return false
    ref = Dict{String,String}()
    for l in eachline(fz)
        m = match(r"^([0-9a-f]{64})\s+(\S+)$", l)
        m === nothing || (ref[m.captures[2]] = m.captures[1])
    end
    ex = joinpath(LAB, "experiments")
    return all(f -> haskey(ref, f) && sha(joinpath(ex, f)) == ref[f], ("stake_fix_grid.jl", "check_stake_fix.jl"))
end

if MODE == "gates"
    gates()
elseif MODE == "smoke"
    file = joinpath(LAB, "experiments", "results-stake-fix-smoke.json")
    wall = run_grid(SMOKE, file)
    open(joinpath(LAB, "experiments", "results-stake-fix-smoke.out"), "a") do io; println(io, "smoke: wall $(round(wall; digits = 1)) s, threads $(Threads.nthreads())"); end
elseif MODE == "main"
    code_frozen() || error("main needs freeze-stake-fix-code.txt with the shas of stake_fix_grid.jl and check_stake_fix.jl")
    freeze_ok()[1] || error("spec or predictions differ from freeze 1 of freeze-stake-fix.txt")
    file = joinpath(LAB, "experiments", "results-stake-fix-main.json")
    wall = run_grid(EVALS, file)
    open(joinpath(LAB, "experiments", "results-stake-fix-main.out"), "a") do io; println(io, "main: wall $(round(wall; digits = 1)) s, threads $(Threads.nthreads())"); end
else
    error("mode gates | smoke | main")
end
