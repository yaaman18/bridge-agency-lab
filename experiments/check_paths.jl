# S10 check (spec discussion/specs/S10-body-paths.md r2): exit 0 when part A has every (seed, arm, t0, cut, mode) once,
# part B has the S8 pairs of H 392 with a J0 difference, C0 holds, and the frozen sha matches. PP1-PP3 printed only.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(joinpath(LAB, "experiments", "results-paths.json"))
ok = true
fail(m) = (println("FAIL ", m); global ok = false)
kA = [(x["seed"], x["arm"], x["t0"], x["cut"], x["mode"]) for x in r["A"]]
want = Set((s, a, t, c, m) for s in (35, 37) for a in ("swap", "std") for t in (64, 192) for c in ("U", "R", "C", "RC") for m in ("once", "persist") if !(c == "U" && m == "persist"))
Set(kA) == want && allunique(kA) || fail("part A combinations")
S8 = JSON.parsefile(joinpath(LAB, "experiments", "results-tiesource.json"))
Set(x["seed"] for x in r["B"]) == Set(x["seed"] for x in S8["runs"] if x["H"] == 392 && !isempty(x["differ"]["J0"])) || fail("part B pairs")
r["C0_B"] === true || fail("C0")
sha = split(read(joinpath(LAB, "experiments", "freeze-paths.txt"), String))[1]
sha == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", "predictions-paths.md"))`, String))[1] || fail("freeze sha")
get1(s, a, t, c, m) = only(x for x in r["A"] if (x["seed"], x["arm"], x["t0"], x["cut"], x["mode"]) == (s, a, t, c, m))
pp1 = all(get1(s, "swap", t, "R", "persist")["alive_at_deadline"] for s in (35, 37), t in (64, 192))
pp2 = all(2 * get1(s, "swap", t, "C", "persist")["acts"]["m2"] <= get1(s, "swap", t, "U", "once")["acts"]["m2"] for s in (35, 37), t in (64, 192))
pp3 = all(isempty(x["QG_persist"]["differ"]) for x in r["B"])
println("PP1 $pp1  PP2 $pp2  PP3 $pp3")
for s in (35, 37), a in ("swap", "std"), t in (64, 192)
    println("  A seed=$s $a t0=$t ", join(["$c/$m:$(x["alive_at_deadline"] ? "alive" : "dies $(x["death"])") m2=$(x["acts"]["m2"])" for c in ("U", "R", "C", "RC"), m in ("once", "persist") for x in r["A"] if (x["seed"], x["arm"], x["t0"], x["cut"], x["mode"]) == (s, a, t, c, m)], "  "))
end
println("  B verdicts: ", Dict(l => sort([(v, count(x -> x[l]["verdict"] == v, r["B"])) for v in unique([x[l]["verdict"] for x in r["B"]])]) for l in ("Q_once", "G_once", "QG_once", "Q_persist", "G_persist", "QG_persist")))
println(ok ? "check_paths: ok" : "check_paths: FAILED")
exit(ok ? 0 : 1)
