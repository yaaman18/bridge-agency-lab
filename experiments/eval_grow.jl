# Item 81 (user 2026-11-02 "じゃあ段階1から進めて"): stage 1 of self-maintenance, the circuit supported by the body.
# body_org raised with the body (FEED, RAISE "body"), paying KC = 0.002 per kept contingency (stages 46-54), the season
# phase (seed - 1) * 100 (stage 47), 10 000 steps, seeds 1-10, with and without the capacity PER = 1 (stage 46), in the
# worlds of item 78 A. Rules: L2's system (bin3 + idle_first + core gate), bin3 (stage 54), GREEDY (pays its 4 kept
# contingencies). Predictions: experiments/predictions-grow81.md (freeze-grow81.txt). Usage: julia --project=. experiments/eval_grow.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
const READCUR = get(ENV, "READCUR", "0") == "1"   # item 82: read the scripted yields while raised with the body
base = (U = 0.02, MCOST = 0.004, STEPS = 10000, FEED = true, KC = 0.002, READCUR = READCUR)
worlds = [("seasons", (;)), ("heldout", (SCHED = "heldout",)), ("random", (SCHED = "random",))]
conds = [("L2", "ORG", (RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)), ("L2+PER1", "ORG", (RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true, PER = 1)),
         ("bin3", "ORG", (RAISE = "body", CONTRAST = "bin3")), ("bin3+PER1", "ORG", (RAISE = "body", CONTRAST = "bin3", PER = 1)),
         ("GREEDY", "GREEDY", (;))]
res = Dict{String,Any}()
for (wn, wo) in worlds, (cn, cond, co) in conds
    rs = Any[]
    for seed in 1:10
        o = merge(base, wo, co, (PHASE = (seed - 1) * 100,), wn == "random" ? (SCHEDSEED = seed,) : (;))
        r = body_org_run(cond, seed, o)
        push!(rs, Dict("death" => r["death"], "meanCount" => r["meanCount"], "keptEnd" => r["keptEnd"], "lost" => r["lost"], "blocked" => r["blocked"],
                       "kept" => r["kept"], "upkeep" => r["upkeep"], "answered" => r["answered"]))
    end
    res["$wn $cn"] = rs
    alive = count(x -> x["death"] === nothing, rs)
    println(rpad("$wn $cn", 20), " survived ", alive, "/10  deaths ", [x["death"] for x in rs if x["death"] !== nothing],
            "  body mean ", round(sum(x["meanCount"] for x in rs) / 10; digits = 1), "  kept/step ", round(sum(x["kept"] for x in rs) / 10; digits = 1),
            "  lost ", [x["lost"] for x in rs])
end
write(joinpath(LAB, "experiments", READCUR ? "results-grow-readcur.json" : "results-grow81.json"), JSON.json(jsonable(res), 2)); println("written")
