# S29 evaluation (predictions-grow-world.md): S7 part (SP1-SP7, pooled as frozen, per-H described) on IN7, S17 part (AH1-AH4) on IN17.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
function sp(runs)
    ev = [e for x in runs for e in x["events"]]
    frac(g) = isempty(ev) ? NaN : count(g, ev) / length(ev)
    aliveH = [x for x in runs if x["alive_at_H"]]
    (n = length(ev), sp1 = all(e -> e["conf_X"] == 0 && e["conf_Y"] == 0, ev), sp2 = all(e -> e["b1"] == "holds", ev),
     sp3 = all(e -> e["death_X"] !== nothing, ev), sp4 = all(e -> e["death_Y"] == e["death_X"], ev),
     nalive = frac(e -> e["death_N"] === nothing), afrac = frac(e -> e["a"] == "holds"),
     sp6b = all(x -> any(e -> e["T"] == "holds", x["events"]), aliveH), sp7 = all(e -> e["T_core"] == e["T"], ev),
     T = count(e -> e["T"] == "holds", ev), aliveH = length(aliveH), nruns = length(runs),
     noT = [(x["H"], x["seed"], x["arm"], x["schedule"]) for x in aliveH if !any(e -> e["T"] == "holds", x["events"])])
end
show(r, label) = println("$label: points $(r.n) runs $(r.nruns) (alive at H $(r.aliveH)) SP1 $(r.sp1) SP2 $(r.sp2) SP3 $(r.sp3) SP4 $(r.sp4) SP5 $(r.nalive >= 0.9) (N alive $(round(r.nalive; digits = 3))) ",
                     "SP6 $(r.afrac >= 0.5 && r.sp6b) ((a) $(round(r.afrac; digits = 3)), T in every run alive at H $(r.sp6b)) SP7 $(r.sp7)  T holds $(r.T)  runs alive without T $(r.noT)")
if haskey(ENV, "IN7")
    f = JSON.parsefile(joinpath(LAB, "experiments", ENV["IN7"])); runs = f["runs"]
    na = [x for x in runs if isempty(x["events"])]
    println("S7 part $(ENV["IN7"]): runs $(length(runs)) controls_ok $(get(f, "controls_ok", nothing)); not applicable (no branch point) $(length(na)) ", [(x["H"], x["seed"], x["arm"], x["schedule"]) for x in na])
    app = [x for x in runs if !isempty(x["events"])]
    show(sp(app), "pooled (frozen judgement)")
    for H in f["horizons"], sch in unique([x["schedule"] for x in app]); show(sp([x for x in app if x["H"] == H && x["schedule"] == sch]), "  H=$H $sch"); end
end
if haskey(ENV, "IN17")
    o = JSON.parsefile(joinpath(LAB, "experiments", ENV["IN17"]))["objects"]
    ah1 = count(x -> x["trajectory_matches_tab"], o); ah2 = count(x -> x["builds"], o); ah3 = count(x -> x["dc"]["dc"], o); ah4 = count(x -> x["needed_julia"], o)
    println("S17 part: objects $(length(o)) AH1 $(ah1 == length(o)) ($ah1) AH2 $(ah2 >= 8) ($ah2) AH3 $(ah3 >= 9) ($ah3) AH4 $(ah4 >= 8) ($ah4)")
    for x in o; println("  seed=$(x["seed"]) dc $(x["dc"]) needed $(x["needed_julia"]) witness $(x["witness"]) T_struct $(x["T_struct"]) tab $(x["tab"]) builds $(x["builds"])"); end
end
