# Item 84 (user 2026-11-03 "じゃあ今日はそこからスタート"): sed_fade (core/circuit.jl, lab option) in body_org raised with the
# body, KC 0.002, L2's rule, seeds 1-10, 10 000 steps, the three worlds, one-way and PER = 1, with and without SEDFADE.
# Predictions: predictions-sedfade.md (freeze-sedfade.txt). Usage: julia --project=.. eval_sedfade.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LC = LabCore
base = (U = 0.02, MCOST = 0.004, STEPS = 10000, FEED = true, KC = 0.002, RAISE = "body", CONTRAST = "bin3", IDLE = true, GATE = true)
worlds = [("seasons", (;)), ("heldout", (SCHED = "heldout",)), ("random", (SCHED = "random",))]
conds = [("L2", (;)), ("L2+PER1", (PER = 1,)), ("L2+fade", (SEDFADE = true,)), ("L2+fade+PER1", (SEDFADE = true, PER = 1))]
res = Dict{String,Any}()
for (wn, wo) in worlds, (cn, co) in conds
    rs = Any[]
    for seed in 1:10
        o = merge(base, wo, co, (PHASE = (seed - 1) * 100,), wn == "random" ? (SCHEDSEED = seed,) : (;))
        kept = Int[]; sedonly = Int[]
        obs(x) = if x.alive && x.t >= 800
            c = x.circuit; b = x.b
            push!(kept, count(k -> c.q[k] >= 1 || c.sg[k] >= 1, eachindex(c.q)))
            push!(sedonly, count(k -> c.q[k] == 0 && c.sg[k] >= 1 && b.kind[b.edges[k][1]] == 'R', eachindex(c.q)))
        end
        r = LC.body_org_run("ORG", seed, merge(o, (ON_STEP = obs,)))
        push!(rs, Dict("death" => r["death"], "meanCount" => r["meanCount"], "keptAlive" => isempty(kept) ? nothing : sum(kept) / length(kept),
                       "sedOnlyR" => isempty(sedonly) ? nothing : sum(sedonly) / length(sedonly), "lost" => r["lost"], "upkeep" => r["upkeep"]))
    end
    res["$wn $cn"] = rs
    alive = count(x -> x["death"] === nothing, rs)
    ka = [round(x["keptAlive"]; digits = 1) for x in rs]; so = [round(x["sedOnlyR"]; digits = 1) for x in rs]
    println(rpad("$wn $cn", 22), " survived ", alive, "/10  deaths ", [x["death"] for x in rs if x["death"] !== nothing],
            "  body mean ", round(sum(x["meanCount"] for x in rs) / 10; digits = 1), "\n", " "^22, " kept/alive step ", ka, "  sed-only R->M ", so)
end
write(joinpath(@__DIR__, "results-sedfade.json"), JSON.json(LC.jsonable(res), 2)); println("written")
