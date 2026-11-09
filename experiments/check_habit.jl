# S13 check (spec discussion/specs/S13-body-habit.md r1): exit 0 when the seeds are 61..70, both arms, the 4 schedules each once,
# every candidate point 64:32:384 is present, the named points are separate, and the frozen sha matches. RB1-RB3 printed only.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(joinpath(LAB, "experiments", "results-habit.json"))
ok = true
fail(m) = (println("FAIL ", m); global ok = false)
r["seeds"] == collect(61:70) || fail("seeds")
kk = [(x["seed"], x["arm"], x["schedule"]) for x in r["runs"]]
Set(kk) == Set((s, a, c) for s in 61:70 for a in ("std", "swap") for c in ("p1-high", "p2-high", "p1-then-p2", "p2-then-p1")) && allunique(kk) || fail("combinations")
all(x -> [p["t"] for p in x["points"]] == collect(64:32:384), r["runs"]) || fail("candidate points")
length(r["named"]) == 2 || fail("named")
sha = split(read(joinpath(LAB, "experiments", "freeze-habit.txt"), String))[1]
sha == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", "predictions-habit.md"))`, String))[1] || fail("freeze sha")
pts = [p for x in r["runs"] for p in x["points"]]; d = [p for p in pts if !haskey(p, "excluded")]
det = [p for p in d if p["R3b"] != "undetermined"]
rb1 = isempty(det) ? "not evaluable" : string(count(p -> p["R3b"] == "holds", det) / length(det) <= 0.05)
xs = [p for p in d if p["X_q32"] !== nothing]; rb2 = isempty(xs) ? "not evaluable" : string(all(p -> all(==(0), p["X_q32"]), xs))
rb3 = string(all(x -> only(x["points"])["j3"] == "holds", r["named"]))
println("candidates $(length(pts)), judged $(length(d)), determined $(length(det)); RB1 $rb1 (holds $(count(p -> p["R3b"] == "holds", det)))  RB2 $rb2 ($(length(xs)) X branches)  RB3 $rb3")
for k in ("j1", "j2", "j3", "G"); println("  $k ", sort([(v, count(p -> p[k] == v, d)) for v in unique([p[k] for p in d])])); end
println("  (2) parts [X q, X sg, N kept]: ", sort([(string(v), count(p -> p["j2_parts"] == v, d)) for v in unique([p["j2_parts"] for p in d])]))
println("  points where every edge of E has q = 0 at t: $(count(p -> all(==(0), p["q_E"]), d)); X died before every sg of E reached 0: $(count(p -> p["X_sg0"] === nothing && p["X_death"] !== nothing, d))")
println(ok ? "check_habit: ok" : "check_habit: FAILED")
exit(ok ? 0 : 1)
