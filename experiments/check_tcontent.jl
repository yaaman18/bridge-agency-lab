# S5 check (spec discussion/specs/S5-body-tcontent.md r1): exit 0 when the seeds are exactly 21..30, the horizons
# 294/392/588, C0 (T and choices equal S4's record, the repeat equal) holds for every (seed, H, arm), and the negative
# controls worked. The predictions CP1-CP6 are printed, not part of the exit code.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(joinpath(LAB, "experiments", "results-tcontent.json"))
ok = true
fail(msg) = (println("FAIL ", msg); global ok = false)
r["seeds"] == collect(21:30) || fail("seeds $(r["seeds"])")
r["horizons"] == [294, 392, 588] || fail("horizons $(r["horizons"])")
length(r["runs"]) == 30 || fail("runs $(length(r["runs"]))")
for x in r["runs"], a in ("std", "swap")
    m = x[a]
    m["C0_matches_S4"] === true || fail("C0 S4 H=$(x["H"]) seed=$(x["seed"]) $a")
    m["C0_repeat_equal"] === true || fail("C0 repeat H=$(x["H"]) seed=$(x["seed"]) $a")
end
r["negative_control_detected"] === true || fail("negative control")

# predictions (printed only)
arms = [(x, a) for x in r["runs"] for a in ("std", "swap")]
cp1 = all(((x, a),) -> x[a]["discriminating_cues"] == ["r7", "r8"] &&
          all(n -> all(s -> x[a]["window_activity"][s][n] == 11, ("c1-better", "c2-better")), ("r1", "r2")), arms)
need = Dict("P2" => ["r2->m2", "r8->m2"], "P1" => ["r1->m1", "r7->m1"])
dflt = Dict("P2" => "m1", "P1" => "m2")
typed = [(x, a) for (x, a) in arms if haskey(need, x[a]["kind"])]
cp2 = all(((x, a),) -> issubset(need[x[a]["kind"]], x[a]["confirmed_links"]), typed)
cp3 = all(((x, a),) -> all(v -> v == dflt[x[a]["kind"]], values(x[a]["silenced_T"])), typed)
cp4a = all(((x, a),) -> x[a]["probes"]["eq-high"] == dflt[x[a]["kind"]], typed)
cp4b = all(x -> "eq-high" in x["probes_differ"], [x for x in r["runs"] if x["seed"] in (24, 28, 29)])
cp5 = all(((x, a),) -> x[a]["probes"]["lo-1"] == dflt[x[a]["kind"]] && x[a]["probes"]["lo-2"] == dflt[x[a]["kind"]], typed)
cp6 = all(x -> isempty(x["probes_differ"]), [x for x in r["runs"] if x["seed"] in (21, 22, 23, 25, 27, 30)])
println("CP1 $cp1  CP2 $cp2  CP3 $cp3  CP4 (each arm) $cp4a (seeds 24/28/29 differ) $cp4b  CP5 $cp5  CP6 $cp6")
for x in r["runs"]
    println("H=$(x["H"]) seed=$(x["seed"]) std $(x["std"]["kind"]) swap $(x["swap"]["kind"]) content_differs=$(x["content_differs"]) probes_differ=$(x["probes_differ"])")
end
println(ok ? "check_tcontent: ok" : "check_tcontent: FAILED")
exit(ok ? 0 : 1)
