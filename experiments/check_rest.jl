# S33: reads results-rest.json; gates first (no verdicts if one fails), then RP1-RP6 (predictions-rest.md) and the
# description (rest intervals, restart, classes, lineages).
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(get(ENV, "IN", joinpath(LAB, "experiments", "results-rest.json")))
g4 = all(x -> x["same"], r["raising"])
println("G2 repeat: $(r["G2_repeat"])  G3 REST_OFF false = nothing: $(r["G3_restoff_false"])  G4 raising copy = BodyOrg: $g4 ($(length(r["raising"])))  gseed $(r["gseed"]) seeds $(first(r["seeds"]))..$(last(r["seeds"]))")
g5 = all(a -> a["replay_ok"], [a for x in r["R"] for a in x["alpha"]])
println("G5 alpha replays equal the main run: $g5")
ok = r["G2_repeat"] && r["G3_restoff_false"] && g4 && g5
get(ENV, "NEGTEST", "0") == "1" && (ok = false)
ok || (println("GATE FAILED: no verdicts"); exit(1))
v(b) = b ? "的中" : "外れ"
RS = [s for x in r["raising"] for s in x["steps"]]
MS = [s for x in r["R"] for s in x["steps"] if s !== nothing]
W = [w for x in r["R"] for w in x["windows"]]
AL = [a for x in r["R"] for a in x["alpha"]]
# RP1
bad1 = count(s -> s["m0_qsg"] != 0 || s["m0_conf"] || s["m0_drop"], vcat(RS, MS)) +
       count(w -> w["release_m0_qsg"] !== nothing && (w["release_m0_qsg"] != 0 || w["release_m0_confdrop"]), W) + count(a -> a["branch_m0_qsg"] != 0 || a["branch_m0_confdrop"], AL)
println("RP1 m0's edges q = sg = 0 everywhere: ", v(bad1 == 0), " ($bad1)")
act = [s for s in MS if s["m0_act"]]
bad2 = count(s -> s["patch_acts"] != 0 || any(!=(0), s["d"]), act)
println("RP2 m0 acts => no patch act, d = 0: ", v(bad2 == 0), " ($bad2 of $(length(act)))")
bad3 = count(s -> !s["m0_cand"], vcat(RS, MS))
println("RP3 m0 is a candidate at every living step: ", v(bad3 == 0), " ($bad3 of $(length(RS) + length(MS)))")
na = count(s -> s["class"] == "a_no_patch_candidate", act)
println("RP4 majority of m0's acts are (a): ", isempty(act) ? "未判定" : v(na > length(act) / 2), " ($na of $(length(act)); b $(count(s -> s["class"] == "b_idle", act)), c $(count(s -> s["class"] == "c_rank", act)))")
ni = count(w -> w["i"], W); nm = count(w -> w["m0_acts"] > 0, W)
println("RP5 windows with (i) < windows with an m0 act: ", nm == 0 ? "未判定" : v(ni < nm), " ($ni vs $nm of $(length(W)))")
p18 = [a for a in AL if a["P18"]]
println("RP6 alpha(m0) = empty at P18 events: ", isempty(p18) ? "未判定" : v(all(a -> a["recep_diff"] == 0, p18)), " ($(length(p18)) P18 events of $(length(AL)); nonzero $(count(a -> a["recep_diff"] != 0, p18)))")
# description
Is = [(x["seed"], x["arm"], x["schedule"], I) for x in r["R"] for I in x["intervals"]]
println("rest intervals: $(length(Is)) in $(length(unique((i[1], i[2], i[3]) for i in Is))) runs; lengths ", sort(unique(I["to"] - I["from"] + 1 for (_, _, _, I) in Is)),
        "; restart ", Dict(k => count(i -> i[4]["restart"] == k, Is) for k in ("restart_observed", "not_observed_within_Hr", "undetermined", "ongoing")))
println("windows: (i) $ni, (ii) $(count(w -> w["ii"], W)), died in window $(count(w -> !w["alive"], W)), of $(length(W))")
println("survival R $(count(x -> x["survived"], r["R"]))/$(length(r["R"]))  N0 $(count(x -> x["survived"], r["N0"]))/$(length(r["N0"]))  A total R $(sum(x -> x["A_total"], r["R"]))  N0 $(sum(x -> x["A_total"], r["N0"]))")
println("alpha events not P18: ", [(a["C_m0_acted"], a["others_same"]) for a in AL if !a["P18"]][1:min(5, end)])
