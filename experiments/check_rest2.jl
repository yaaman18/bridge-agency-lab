# S34: reads results-rest2.json; gates first (no verdicts if one fails), then QX1, QA1, QA2, QB0, QBd, QB1
# (predictions-rest2.md) and the description.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(get(ENV, "IN", joinpath(LAB, "experiments", "results-rest2.json")))
g5 = all(x -> x["same"], r["raising"])
println("G2 repeat $(r["G2_repeat"])  G3 reversal leaves the main run $(r["G3_flip_does_not_touch_main"])  G4 natural clamp = nothing $(r["G4_clamp_natural_equals_nothing"])  G5 raising copies = BodyOrg $g5 ($(length(r["raising"])))  gseed $(r["gseed"]) seeds $(first(r["seeds"]))..$(last(r["seeds"]))")
ok = r["G2_repeat"] && r["G3_flip_does_not_touch_main"] && r["G4_clamp_natural_equals_nothing"] && g5
get(ENV, "NEGTEST", "0") == "1" && (ok = false)
ok || (println("GATE FAILED: no verdicts"); exit(1))
v(b) = b ? "的中" : "外れ"
live(xs) = [st for x in xs for st in x["steps"] if st !== nothing]
RAs = live(r["RA"]); RBs = live(r["RB"])
RAr = [st for x in r["raising"] if x["lineage"] == "RA" for st in x["steps"]]; RBr = [st for x in r["raising"] if x["lineage"] == "RB" for st in x["steps"]]
bx = count(st -> !st["exempt_ok"], vcat(RAs, RBs, RAr, RBr))
println("QX1 exempt edges keep q = 1: ", v(bx == 0), " ($bx of $(length(RAs) + length(RBs) + length(RAr) + length(RBr)))")
ba = count(st -> st["m0_cand"], vcat(RAs, RAr))
println("QA1 RA: m0 is never a candidate: ", v(ba == 0), " ($ba of $(length(RAs) + length(RAr)))")
na = count(st -> st["m0_act"], RAs)
println("QA2 RA: no m0 act in the trials: ", v(na == 0), " ($na)")
b0 = count(st -> !st["m0_cand"], RBs)
println("QB0 RB: m0 is a candidate at every living trial step: ", v(b0 == 0), " ($b0 of $(length(RBs)))")
dd = [x["death"] for x in r["RB"]]
println("QBd RB: every run dies before H: ", v(all(d -> d !== nothing && d < r["H"], dd)), " ($(count(d -> d !== nothing && d < r["H"], dd)) of $(length(dd)); death times $(sort(unique(filter(!isnothing, dd)))))")
ev = [st for st in RBs if st["rev"] !== nothing]; fl = count(st -> (st["rev"][1] == "m0") != (st["rev"][2] == "m0"), ev)
println("QB1 RB: reversals < 5% of evaluated steps: ", isempty(ev) ? "未判定" : v(fl < 0.05 * length(ev)), " ($fl of $(length(ev)); true->m0 $(count(st -> st["rev"][1] == "m0" && st["rev"][2] != "m0", ev)), false->m0 $(count(st -> st["rev"][1] != "m0" && st["rev"][2] == "m0", ev)); winner pairs $(Dict(k => count(st -> (st["rev"][1], st["rev"][2]) == k, ev) for k in unique((st["rev"][1], st["rev"][2]) for st in ev))))")
# description
on = [st for st in RBs if st["rb_old"]]; off = [st for st in RBs if !st["rb_old"]]
rate(xs) = isempty(xs) ? NaN : round(count(st -> st["m0_act"], xs) / length(xs); digits = 3)
println("RB rb on $(length(on)) (m0 act rate $(rate(on))), off $(length(off)) (rate $(rate(off)))")
W = [w for x in r["RB"] for w in x["windows"] if !w["dead_at_start"]]
println("RB windows (alive at start) $(length(W)): m0 true > false $(count(w -> w["m0_true"] > w["m0_false"], W)), true < false $(count(w -> w["m0_true"] < w["m0_false"], W)), equal $(count(w -> w["m0_true"] == w["m0_false"], W)); (i) release > actual $(count(w -> w["A_release"] > w["A"], W))")
for L in ("N0", "RA", "RB")
    xs = r[L]; println("$L survived $(count(x -> x["death"] === nothing, xs))/$(length(xs))  A total $(sum(x -> x["A_total"], xs))")
end
