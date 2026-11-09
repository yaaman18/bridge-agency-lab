# Item 83 (user 2026-11-03 "bridge-agency-labの開発に続いをやって"): item 81's inference 2 tested without changing anything.
# Random world, raised with the body (FEED), seeds 1-10, 10 000 steps. A = L2's rule KC 0.002, B = L2's rule KC 0,
# C = GREEDY KC 0.0065 (4 kept = 0.026/step, L2's load), D = GREEDY KC 0.002. Read-only observer (ON_STEP).
# Predictions: predictions-upkeep.md (freeze-upkeep.txt). Usage: julia --project=.. eval_upkeep.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LC = LabCore
base = (U = 0.02, MCOST = 0.004, STEPS = 10000, FEED = true, SCHED = "random")
L2 = (RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)
runs = [("A", "ORG", merge(L2, (KC = 0.002,))), ("B", "ORG", merge(L2, (KC = 0,))), ("C", "GREEDY", (KC = 0.0065,)), ("D", "GREEDY", (KC = 0.002,))]
blocktot(t, o) = (g = LC.bo_world(t - 800 + o.PHASE, o); g[1] + g[2])
res = Dict{String,Any}()
for (name, cond, co) in runs
    rs = Any[]
    for seed in 1:10
        o = merge(base, co, (PHASE = (seed - 1) * 100, SCHEDSEED = seed))
        kept = Int[]; harv = Float64[]; act = Int[]
        obs(x) = if x.alive
            push!(kept, cond == "ORG" ? count(k -> x.circuit.q[k] >= 1 || x.circuit.sg[k] >= 1, eachindex(x.circuit.q)) : 4)
            push!(harv, isempty(x.acting) ? 0.0 : 0.02 * (max(x.d[1], 0) + max(x.d[2], 0))); push!(act, length(x.acting))
        end
        r = LC.body_org_run(cond, seed, merge(o, (ON_STEP = obs,)))
        n = length(kept); dth = r["death"]
        late = 801:n
        e = Dict{String,Any}("death" => dth, "meanCount" => r["meanCount"], "alive_steps" => n,
            "harvest_per_step_after800" => isempty(late) ? 0.0 : sum(harv[late]) / length(late))
        if dth !== nothing
            w2 = max(1, n - 199):n; w3 = max(1, n - 299):n
            e["kept_last200"] = sum(kept[w2]) / length(w2)
            e["upkeep_last300"] = co.KC * sum(kept[w3]); e["actcost_last300"] = 0.004 * sum(act[w3])
            e["harvest_last300"] = sum(harv[w3])
            e["block_total_death"] = blocktot(dth, o); e["block_total_before"] = dth - 300 >= 800 ? blocktot(dth - 300, o) : nothing
            e["world_at_death"] = LC.bo_world(dth - 800 + o.PHASE, o)
        end
        push!(rs, e)
    end
    res[name] = rs
    alive = count(x -> x["death"] === nothing, rs)
    println(name, " survived ", alive, "/10  deaths ", [x["death"] for x in rs if x["death"] !== nothing], "  body mean ", round(sum(x["meanCount"] for x in rs) / 10; digits = 1))
end
println("\nper seed (A vs D harvest/step after 800; A deaths: kept_last200, upkeep/actcost/harvest last300, block totals death/before, world)")
for s in 1:10
    a = res["A"][s]; d = res["D"][s]
    ratio = a["harvest_per_step_after800"] / d["harvest_per_step_after800"]
    line = "seed $(lpad(s,2))  harvest A $(round(a["harvest_per_step_after800"]; digits=4))  D $(round(d["harvest_per_step_after800"]; digits=4))  ratio $(round(ratio; digits=2))"
    if a["death"] !== nothing
        line *= "  | death $(a["death"]) kept $(round(a["kept_last200"]; digits=1)) upkeep $(round(a["upkeep_last300"]; digits=2)) act $(round(a["actcost_last300"]; digits=2)) harv $(round(a["harvest_last300"]; digits=2)) blocks $(a["block_total_death"])/$(a["block_total_before"]) $(a["world_at_death"])"
    end
    println(line)
end
write(joinpath(@__DIR__, "results-upkeep.json"), JSON.json(LC.jsonable(res), 2)); println("written")
