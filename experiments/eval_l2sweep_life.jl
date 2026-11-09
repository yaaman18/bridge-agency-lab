# Item 86 validation VQ5: body_org with L2's system (scripted raising, bin3 + idle_first + core gate) + sed_fade, KC 0.003 for
# the whole life, seeds 1-10, 10 000 steps, the worlds of eval_grow.jl. Usage: julia --project=.. eval_l2sweep_life.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LC = LabCore
base = (U = 0.02, MCOST = 0.004, STEPS = 10000, KC = parse(Float64, get(ENV, "KCLIFE", "0.003")), CONTRAST = "bin3", IDLE = true, GATE = true, SEDFADE = true)
res = Dict{String,Any}()
for (wn, wo) in [("seasons", (;)), ("heldout", (SCHED = "heldout",)), ("random", (SCHED = "random",))]
    rs = [LC.body_org_run("ORG", seed, merge(base, wo, (PHASE = (seed - 1) * 100,), wn == "random" ? (SCHEDSEED = seed,) : (;))) for seed in 1:10]
    res[wn] = [Dict("death" => r["death"], "meanCount" => r["meanCount"], "kept" => r["kept"]) for r in rs]
    println(rpad(wn, 8), " survived ", count(r -> r["death"] === nothing, rs), "/10  deaths ", [r["death"] for r in rs if r["death"] !== nothing],
            "  body mean ", round(sum(r["meanCount"] for r in rs) / 10; digits = 1), "  kept/step ", round(sum(r["kept"] for r in rs) / 10; digits = 1))
end
write(joinpath(@__DIR__, get(ENV, "KCLIFE", "0.003") == "0.003" ? "results-l2sweep-life.json" : "results-l2sweep-life-$(ENV["KCLIFE"]).json"), JSON.json(LC.jsonable(res), 2)); println("written")
