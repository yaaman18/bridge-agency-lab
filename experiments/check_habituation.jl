# S11 check (spec discussion/specs/S11-body-habituation.md r1): exit 0 when the pairs are S10 B's, C0 holds and the frozen sha matches. HP1-HP3 printed only.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(joinpath(LAB, "experiments", "results-habituation.json"))
ok = true
fail(m) = (println("FAIL ", m); global ok = false)
B = JSON.parsefile(joinpath(LAB, "experiments", "results-paths.json"))["B"]
sort([x["seed"] for x in r["pairs"]]) == sort([x["seed"] for x in B]) || fail("pairs")
r["C0"] === true || fail("C0")
sha = split(read(joinpath(LAB, "experiments", "freeze-habituation.txt"), String))[1]
sha == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", "predictions-habituation.md"))`, String))[1] || fail("freeze sha")
n(f) = count(f, r["pairs"])
a, b, c = n(x -> x["X0_persist"]["difference_gone"]), n(x -> x["X1_persist"]["equals_swap"]), n(x -> x["X2_persist"]["equals_std"])
println("HP1 $(a >= 10) ($a/13)  HP2 $(b >= 10) ($b/13)  HP3 $(c >= 10) ($c/13)")
println("  X0 persistent leaves a difference: ", [x["seed"] for x in r["pairs"] if !x["X0_persist"]["difference_gone"]])
println("  one-shot = persistent in every pair: ", all(x -> all(x["$(k)_once"] == x["$(k)_persist"] || x["$(k)_once"]["choices" in keys(x["$(k)_once"]) ? "choices" : "std"] == x["$(k)_persist"]["choices" in keys(x["$(k)_persist"]) ? "choices" : "std"] for k in ("X0", "X1", "X2")), r["pairs"]))
println(ok ? "check_habituation: ok" : "check_habituation: FAILED")
exit(ok ? 0 : 1)
