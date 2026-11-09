# S8 check (spec discussion/specs/S8-body-tiesource.md r1): exit 0 when the seeds are 21..40, the horizons 294/392/588,
# 60 runs, C0 (S6 match for seeds 21..30) and the repeats hold. RP1-RP4 and the descriptive J5/J6/J125/J126 printed only.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(joinpath(LAB, "experiments", "results-tiesource.json"))
ok = true
fail(m) = (println("FAIL ", m); global ok = false)
r["seeds"] == collect(21:40) || fail("seeds")
r["horizons"] == [294, 392, 588] || fail("horizons")
length(r["runs"]) == 60 || fail("runs")
kk = [(x["H"], x["seed"]) for x in r["runs"]]   # codex I-R 8
Set(kk) == Set((H, s) for H in (294, 392, 588) for s in 21:40) && allunique(kk) || fail("combinations")
sha = split(read(joinpath(LAB, "experiments", "freeze-tiesource.txt"), String))[1]
sha == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", "predictions-tiesource.md"))`, String))[1] || fail("freeze sha")
for x in r["runs"], a in ("std", "swap")
    x["repeat_equal_$a"] === true || fail("repeat H=$(x["H"]) seed=$(x["seed"]) $a")
    x["seed"] <= 30 && (x["C0_matches_S6_$a"] === true || fail("C0 H=$(x["H"]) seed=$(x["seed"]) $a"))
end
arms(rs) = [(x, a) for x in rs for a in ("std", "swap")]
same(rs, iv, ps) = all(((x, a),) -> all(x[a][iv][p] == x[a]["J0"][p] for p in ps), arms(rs))
none(rs, iv, ps) = all(((x, a),) -> all(x[a][iv][p] == "" for p in ps), arms(rs))
ALL = r["ties"]; LOW = ["1,1", "2,2"]
for (lab, rs) in (("seeds 21-30 (seen)", filter(x -> x["seed"] <= 30, r["runs"])), ("seeds 31-40 (new)", filter(x -> x["seed"] > 30, r["runs"])))
    println(lab, ": RP1 J3 $(same(rs, "J3", ALL)) J4 $(same(rs, "J4", ALL))  RP2 $(none(rs, "J1256", ALL))  RP3 $(same(rs, "J12", LOW))  RP4 $(none(rs, "J56", LOW))")
    for iv in ("J0", "J5", "J6", "J56", "J125", "J126", "J1256")
        cnt = Dict{String,Int}()
        for (x, a) in arms(rs), p in ALL; c = x[a][iv][p]; c = c == "" ? "none" : c; cnt[c] = get(cnt, c, 0) + 1; end
        nd = count(x -> !isempty(x["differ"][iv]), rs)
        println("  $iv choices over arms x ties: $(sort(collect(cnt))); runs where the arms differ: $nd/$(length(rs))")
    end
end
println(ok ? "check_tiesource: ok" : "check_tiesource: FAILED")
exit(ok ? 0 : 1)
