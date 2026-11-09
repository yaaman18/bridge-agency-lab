# S24 evaluation (predictions-long.md): the S7 part (SP1-SP7 as frozen, pooled over H 392/784, with per-H description) from
# results-selfmaint-long.json, and the S17 part (AH1-AH4 per H) from results-agent2-long{392,784}.json.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
f = JSON.parsefile(joinpath(LAB, "experiments", "results-selfmaint-long.json")); runs = f["runs"]
println("S7 part: runs $(length(runs)) seeds $(f["seeds"]) horizons $(f["horizons"]) controls_ok $(get(f, "controls_ok", nothing))")
function sp(runs)
    ev = [e for x in runs for e in x["events"]]
    frac(g) = isempty(ev) ? NaN : count(g, ev) / length(ev)
    aliveH = [x for x in runs if x["alive_at_H"]]
    (n = length(ev), sp1 = all(e -> e["conf_X"] == 0 && e["conf_Y"] == 0, ev), sp2 = all(e -> e["b1"] == "holds", ev),
     sp3 = all(e -> e["death_X"] !== nothing, ev), sp4 = all(e -> e["death_Y"] == e["death_X"], ev),
     nalive = frac(e -> e["death_N"] === nothing), afrac = frac(e -> e["a"] == "holds"),
     sp6b = all(x -> any(e -> e["T"] == "holds", x["events"]), aliveH), sp7 = all(e -> e["T_core"] == e["T"], ev),
     T = count(e -> e["T"] == "holds", ev), aliveH = length(aliveH), nruns = length(runs))
end
show(r, label) = println("$label: points $(r.n) runs $(r.nruns) (alive at H $(r.aliveH)) SP1 $(r.sp1) SP2 $(r.sp2) SP3 $(r.sp3) SP4 $(r.sp4) SP5 $(r.nalive >= 0.9) (N alive $(round(r.nalive; digits = 3))) ",
                     "SP6 $(r.afrac >= 0.5 && r.sp6b) ((a) $(round(r.afrac; digits = 3)), T in every run alive at H $(r.sp6b)) SP7 $(r.sp7)  T holds $(r.T)")
show(sp(runs), "pooled (the frozen judgement)")
for H in f["horizons"]; show(sp([x for x in runs if x["H"] == H]), "  H=$H (description)"); end
for H in (392, 784)
    g = JSON.parsefile(joinpath(LAB, "experiments", "results-agent2-long$H.json")); o = g["objects"]
    ah1 = count(x -> x["trajectory_matches_tab"], o); ah2 = count(x -> x["builds"], o); ah3 = count(x -> x["dc"]["dc"], o); ah4 = count(x -> x["needed_julia"], o)
    println("S17 part H=$H: objects $(length(o)) AH1 $(ah1 == length(o)) ($ah1) AH2 $(ah2 >= 15) ($ah2, Julia; Lean by agent_lean.sh) AH3 $(ah3 >= 18) ($ah3) AH4 $(ah4 >= 15) ($ah4)",
            "  missing: ", [(x["seed"], x["arm"], [k for k in ("self", "smc", "act", "bound") if !x["dc"][k]], x["needed_julia"]) for x in o if !x["builds"]])
end
