# Item 78 A (user 2026-11-02 "おすすめで実装していって"): world variation for body_org, L2's system (bin3 + idle_first + core
# gate, items 75/77), against the rule of stage 42 and the fixed rule GREEDY. Worlds: the frozen seasons, the held-out
# seasons of sense/heldout.js, and random 300-step blocks (core/body_org.jl SCHED). 10 000 steps, seeds 1-10 (the random
# world's draw = the seed). Predictions: experiments/predictions-worldvar.md (freeze-worldvar.txt).
# Usage: julia --project=. experiments/eval_worldvar.jl   (EXTRA=1: the extra receptors of item 78 B; SEENBOTH=1: item 79)
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
const EXTRA = get(ENV, "EXTRA", "0") == "1"
const SEENBOTH = get(ENV, "SEENBOTH", "0") == "1"   # item 79
base = (U = 0.02, MCOST = 0.004, STEPS = 10000, SEEN = true)
rules = [("L2", (CONTRAST = "bin3", IDLE = true, GATE = true, EXTRA = EXTRA, SEENBOTH = SEENBOTH)), ("stage42", (EXTRA = EXTRA,))]
worlds = [("seasons", (;)), ("heldout", (SCHED = "heldout",)), ("random", (SCHED = "random",))]
"""Among the living steps where both seen yields are positive and differ and one patch is acted on: the share on the
larger seen yield."""
function richer(r)
    n = 0; k = 0; last = r["death"] === nothing ? length(r["acts"]) : r["death"]
    for t in 1:last   # the circuit is raised before the body (RAISE pre), so every body step is in the world
        y = r["seen"][t]; a = r["acts"][t]
        (y[1] > 0 && y[2] > 0 && y[1] != y[2] && length(a) == 1) || continue
        n += 1; k += a[1] == (y[1] > y[2] ? 1 : 2)
    end
    n == 0 ? NaN : k / n
end
res = Dict{String,Any}()
for (wn, wo) in worlds, (cn, co) in vcat(rules, [("GREEDY", (;)), ("NONE", (;))])
    rs = Any[]
    for seed in 1:10
        o = merge(base, wo, wn == "random" ? (SCHEDSEED = seed,) : (;), cn in ("GREEDY", "NONE") ? (;) : co)
        r = body_org_run(cn in ("GREEDY", "NONE") ? cn : "ORG", seed, o)
        push!(rs, Dict("death" => r["death"], "meanCount" => r["meanCount"], "answered" => r["answered"], "richer" => richer(r), "nActs" => r["nActs"]))
    end
    res["$wn $cn"] = rs
    rr = [x["richer"] for x in rs]
    println(rpad("$wn $cn", 20), " survived ", count(x -> x["death"] === nothing, rs), "/10  richer ", round.(rr; digits = 2),
            "  body mean ", round(sum(x["meanCount"] for x in rs) / 10; digits = 1), "  answered ", round(sum(x["answered"] for x in rs) / 10; digits = 3))
end
out = joinpath(LAB, "experiments", "results-worldvar" * (EXTRA ? "-extra" : "") * (SEENBOTH ? "-seenboth" : "") * ".json")
write(out, JSON.json(jsonable(res), 2)); println("written ", relpath(out, LAB))
