# S18 check (spec discussion/specs/S18-body-habit3.md r1): exit 0 when the seeds are 101..110, both arms, the 4 schedules each once,
# every candidate point present, and the frozen sha matches. RW1-RW3 printed only.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(joinpath(LAB, "experiments", "results-habit3.json"))
ok = true
fail(m) = (println("FAIL ", m); global ok = false)
r["seeds"] == collect(101:110) || fail("seeds")
kk = [(x["seed"], x["arm"], x["schedule"]) for x in r["runs"]]
Set(kk) == Set((s, a, c) for s in 101:110 for a in ("std", "swap") for c in ("p1-high", "p2-high", "p1-then-p2", "p2-then-p1")) && allunique(kk) || fail("combinations")
all(x -> [p["t"] for p in x["points"]] == collect(64:32:384), r["runs"]) || fail("candidate points")
sha = split(read(joinpath(LAB, "experiments", "freeze-habit3.txt"), String))[1]
sha == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", "predictions-habit3.md"))`, String))[1] || fail("freeze sha")
rw1 = all(x -> x["raising_reproduced"], r["runs"])
cand = [p for x in r["runs"] if x["raising_reproduced"] for p in x["points"] if !haskey(p, "excluded")]
j1 = count(p -> p["j1"] == "holds", cand); det1 = count(p -> p["j1"] != "undetermined", cand)
full = [p for p in cand if p["j1"] != "undetermined" && p["j2"] != "undetermined" && p["j3"] != "undetermined"]
rw3 = isempty(full) ? "not evaluable" : string(count(p -> p["R3b"] == "holds", full) / length(full) <= 0.10)
println("RW1 $rw1  RW2 $(isempty(cand) ? "not evaluable" : j1 / length(cand) >= 0.9) ((1) holds $j1 of $(length(cand)) candidates, determined $det1)  RW3 $rw3 (R3-b' holds $(count(p -> p["R3b"] == "holds", full)) of $(length(full)))")
for k in ("j1", "j2", "j3", "R3b", "G"); println("  $k ", sort([(v, count(p -> p[k] == v, cand)) for v in unique([p[k] for p in cand])])); end
println("  (1) witness phases: ", sort([(v, count(p -> p["j1_witness"] !== nothing && p["j1_witness"][1] == v, cand)) for v in ("raising", "trial")]))
println(ok ? "check_habit3: ok" : "check_habit3: FAILED")
exit(ok ? 0 : 1)
