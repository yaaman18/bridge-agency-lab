# S9 check (spec discussion/specs/S9-body-envresp.md r2): exit 0 when the seeds are 41..50, both arms, the 4 schedules each once,
# the named runs are separate, the controls worked and the frozen sha matches. EP1-EP4 printed only.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(joinpath(LAB, "experiments", "results-envresp.json"))
ok = true
fail(m) = (println("FAIL ", m); global ok = false)
r["seeds"] == collect(41:50) || fail("seeds")
kk = [(x["seed"], x["arm"], x["schedule"]) for x in r["runs"]]
Set(kk) == Set((s, a, c) for s in 41:50 for a in ("std", "swap") for c in ("p1-high", "p2-high", "p1-then-p2", "p2-then-p1")) && allunique(kk) || fail("combinations")
length(r["named"]) == 2 || fail("named")
r["controls_ok"] === true || fail("controls $(r["controls"])")
sha = split(read(joinpath(LAB, "experiments", "freeze-envresp.txt"), String))[1]
sha == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", "predictions-envresp.md"))`, String))[1] || fail("freeze sha")
ev = [e for x in r["runs"] for e in x["events"]]
cnt(k) = sort([(v, count(e -> e[k] == v, ev)) for v in unique([e[k] for e in ev])])
mis = [(e["t"], m, d["mismatch"]) for e in ev for (m, d) in e["c_detail"] if !isempty(d["mismatch"])]
ep1 = isempty(mis)
real(m) = any(e -> e["c_detail"][m]["usable"] && any(x -> x in (m == "m1" ? ["r1", "r3", "r7", "r8"] : ["r2", "r4", "r7", "r8"]), e["c_detail"][m]["diff"]), ev)
ep2 = real("m1") && real("m2")
bd = [e for e in ev if e["b"] != "undetermined"]; ep3v = isempty(bd) ? NaN : count(e -> e["b"] == "holds", bd) / length(bd)
nd = [e for e in ev if e["b"] == "holds" && e["b_prime"] != "undetermined"]; ep4v = isempty(nd) ? NaN : count(e -> e["b_prime"] == "fails", nd) / length(nd)
println("points $(length(ev)) in $(length(r["runs"])) runs")
println("EP1 $ep1 (mismatches $(length(mis)))  EP2 $ep2 (realized m1 $(real("m1")) m2 $(real("m2")))  EP3 $(ep3v >= 0.5) ($(round(ep3v; digits = 3)) of $(length(bd)))  EP4 $(ep4v >= 0.9) ($(round(ep4v; digits = 3)) of $(length(nd)))")
for k in ("a", "b", "b_Z0", "b_prime", "b_uncoupled", "need", "c", "R2c"); println("  $k: ", cnt(k)); end
use = Dict(m => sort([(w, count(e -> e["c_detail"][m]["why"] == w, ev)) for w in unique([e["c_detail"][m]["why"] for e in ev])]) for m in ("m1", "m2"))
println("  (c) usable / excluded: ", use)
for sch in ("p1-high", "p2-high", "p1-then-p2", "p2-then-p1")
    es = [e for x in r["runs"] if x["schedule"] == sch for e in x["events"]]
    println("  $(rpad(sch, 11)) b holds $(count(e -> e["b"] == "holds", es))/$(length(es)) need holds $(count(e -> e["need"] == "holds", es)) R2c holds $(count(e -> e["R2c"] == "holds", es))")
end
for x in r["named"]; ev2 = x["events"]
    println("  named seed=$(x["seed"]) $(x["arm"]) $(x["schedule"]): a $(count(e -> e["a"] == "holds", ev2))/$(length(ev2)) b holds $(count(e -> e["b"] == "holds", ev2)) need holds $(count(e -> e["need"] == "holds", ev2)) R2c holds $(count(e -> e["R2c"] == "holds", ev2))")
end
println(ok ? "check_envresp: ok" : "check_envresp: FAILED")
exit(ok ? 0 : 1)
