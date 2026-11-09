# S32: reads results-activity.json; gates G0-G2 first (no verdicts if one fails), then QP1-QP4 on the trials
# (predictions-activity.md) and the description of the raising (not counted).
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(get(ENV, "IN", joinpath(LAB, "experiments", "results-activity.json")))

steps(xs) = [st for x in xs for st in x["steps"]]
T = steps(r["trials"]); R = steps(r["raising"])
g0 = all(x -> x["G0_same"], r["raising"])
g1v = [st["G1"] for st in vcat(T, R) if st["G1"] !== nothing]
g1 = all(==(true), g1v)
println("G0 raising copy equals BodyOrg: $g0 ($(length(r["raising"])) raisings)")
println("G1 candidates from drove equal step!'s choice: $g1 ($(length(g1v)) updates with two or more candidates)")
println("G2 repeat: $(r["G2_repeat"])   gseed $(r["gseed"]) seeds $(first(r["seeds"]))..$(last(r["seeds"]))")
ok = g0 && g1 && r["G2_repeat"]
get(ENV, "NEGTEST", "0") == "1" && (ok = false)
ok || (println("GATE FAILED: no verdicts"); exit(1))

function tally(S)
    n = length(S)
    c1 = count(st -> !st["cores_on"], S)
    sviol = count(st -> any(m -> st["S"][m] && !(m in st["cand"]), keys(st["S"])), S)
    p2 = count(st -> !isempty(st["cand"]) && st["acting"] != [st["winner"]], S)   # exactly one acting, and it is the rank winner of the pool
    empty = [st for st in S if isempty(st["cand"])]
    q5 = count(st -> !isempty(st["acting"]), empty)   # no candidate, yet a patch motor acted
    a1 = count(st -> all(values(st["A1"])), S)
    scov = count(st -> any(m -> st["S"][m], keys(st["S"])), S)
    candnotS = count(st -> any(m -> m in st["cand"] && !st["S"][m], keys(st["S"])), S)
    cs(f) = count(st -> any(m -> m in st["cand"] && !st["S"][m] && f(st, m), keys(st["S"])), S)
    candnotS_stale = (stale = cs((st, m) -> st["stale"][m]), idle = cs((st, m) -> st["idle"][m]), onset = cs((st, m) -> st["onset"][m]),
                      none = cs((st, m) -> !st["stale"][m] && !st["idle"][m] && !st["onset"][m]))
    (n = n, empty_acting = q5, cores_off = c1, A1_premise_all = a1, S_violations = sviol, P2_violations = p2, empty = length(empty),
     S_any = scov, cand_without_S = candnotS, cand_without_S_stale = candnotS_stale,
     empty_why = [Dict(m => st["why"][m] for m in keys(st["why"])) for st in empty[1:min(5, end)]])
end
t = tally(T); q = tally(R)
println("trials  ", t)
println("raising ", q, "  (description only)")
v(b) = b ? "的中" : "外れ"
println("QP1 cores on at every trial update: ", v(t.cores_off == 0), " ($(t.cores_off) of $(t.n))")
println("QP2 S(m) => candidate: ", v(t.S_violations == 0), " ($(t.S_violations))")
println("QP3 nonempty candidates => exactly one acting, the rank winner: ", v(t.P2_violations == 0), " ($(t.P2_violations))")
println("QP4 no update without a candidate: ", v(t.empty == 0), " ($(t.empty))")
println("QP5 no candidate => no acting patch motor: ", v(t.empty_acting == 0), " ($(t.empty_acting))")
