# S6 check (spec discussion/specs/S6-body-tcommon.md r1): exit 0 when the seeds are 21..30, the horizons 294/392/588,
# 30 runs, C0 (S5 match, repeat) for both arms of every run, and the negative controls worked. AP0-AP4 printed only.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(joinpath(LAB, "experiments", "results-tcommon.json"))
ok = true
fail(m) = (println("FAIL ", m); global ok = false)
r["seeds"] == collect(21:30) || fail("seeds")
r["horizons"] == [294, 392, 588] || fail("horizons")
length(r["runs"]) == 30 || fail("runs")
for x in r["runs"], a in ("std", "swap")
    x["C0_matches_S5_$a"] === true || fail("C0 S5 H=$(x["H"]) seed=$(x["seed"]) $a")
    x["C0_repeat_equal_$a"] === true || fail("C0 repeat H=$(x["H"]) seed=$(x["seed"]) $a")
end
r["negative_control_detected"] === true || fail("negative control")
ties = Set(r["ties"])
only_ties(iv) = all(x -> issubset(x["differ"][iv], ties), r["runs"])
better(iv) = all(x -> x["nontie_better"]["std"][iv] && x["nontie_better"]["swap"][iv], r["runs"])
println("AP1 $(better("I0"))  AP2 $(only_ties("I0"))  AP3 I1 $(only_ties("I1")) I2 $(only_ties("I2"))  AP4 $(better("I1"))  (I2 non-tie better: $(better("I2")))")
for iv in ("I0", "I1", "I2")
    off = [(x["H"], x["seed"], setdiff(x["differ"][iv], ties)) for x in r["runs"] if !issubset(x["differ"][iv], ties)]
    nb = [(x["H"], x["seed"], a) for x in r["runs"] for a in ("std", "swap") if !x["nontie_better"][a][iv]]
    println("$iv: seeds differing off ties $(off); arms not choosing the better patch on some non-tie $(nb)")
    println("$iv: seeds differing at all (H=392) ", [x["seed"] for x in r["runs"] if x["H"] == 392 && !isempty(x["differ"][iv])])
end
println(ok ? "check_tcommon: ok" : "check_tcommon: FAILED")
exit(ok ? 0 : 1)
