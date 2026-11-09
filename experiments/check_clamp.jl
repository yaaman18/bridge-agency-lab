# S12 check (spec discussion/specs/S12-body-clamp.md r2): exit 0 when the seeds are 51..60, both arms, the 4 schedules each once,
# the named runs separate, the controls worked and the frozen sha matches. CP1-CP5 and Q-C printed only.
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
r = JSON.parsefile(joinpath(LAB, "experiments", "results-clamp.json"))
ok = true
fail(m) = (println("FAIL ", m); global ok = false)
r["seeds"] == collect(51:60) || fail("seeds")
kk = [(x["seed"], x["arm"], x["schedule"]) for x in r["runs"]]
Set(kk) == Set((s, a, c) for s in 51:60 for a in ("std", "swap") for c in ("p1-high", "p2-high", "p1-then-p2", "p2-then-p1")) && allunique(kk) || fail("combinations")
length(r["named"]) == 4 || fail("named")
r["controls_ok"] === true || fail("controls $(r["controls"])")
sha = split(read(joinpath(LAB, "experiments", "freeze-clamp.txt"), String))[1]
sha == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", "predictions-clamp.md"))`, String))[1] || fail("freeze sha")
ev = [e for x in r["runs"] for e in x["events"]]
frac(xs, f) = isempty(xs) ? nothing : count(f, xs) / length(xs)
fmt(x) = x === nothing ? "not evaluable" : string(round(x; digits = 3))
judge(x, ok) = x === nothing ? "not evaluable" : string(ok(x))
A = [e for e in ev if e["A_common"]]; B = [e for e in ev if e["B_common"]]
cp1 = (isempty(A) || isempty(B)) ? "not evaluable" : string(all(e -> e["A_identity"], A) && all(e -> e["B_identity"], B))
dA2 = [e for e in A if e["A"]["ii"]["shift"] != "undetermined"]
cp2a = frac(dA2, e -> e["A"]["ii"]["shift"] == "holds"); cp2b = frac(A, e -> e["A"]["i"]["D"] > 0)
Bo = [e for e in B if e["B"]["o"]["shift"] == "holds"]; cp3 = frac(Bo, e -> e["B"]["ii"]["shift"] != "holds")
qb1 = [e["QB_one_$m"] for e in ev for m in ("m1", "m2") if e["QB_one_$m"]["usable"]]; cp4 = frac(qb1, x -> x["saturated"])
qbn = [e["QB_nt_$m"] for e in ev for m in ("m1", "m2") if e["QB_nt_$m"]["usable"]]
cp5 = isempty(qbn) ? "not evaluable" : string(all(x -> isempty(x["mismatch"]), qbn))
println("points $(length(ev)) in $(length(r["runs"])) runs; common A $(length(A)) B $(length(B))")
println("CP1 $cp1  CP2 (ii) shift $(judge(cp2a, x -> x >= 0.9)) ($(fmt(cp2a)) of $(length(dA2))), (i) D>0 $(judge(cp2b, x -> x >= 0.5)) ($(fmt(cp2b)) of $(length(A)))  ",
        "CP3 $(judge(cp3, x -> x >= 0.9)) ($(fmt(cp3)) of $(length(Bo)))  CP4 $(judge(cp4, x -> x >= 0.9)) ($(fmt(cp4)) of $(length(qb1)))  CP5 $cp5 ($(length(qbn)) NT events)")
for (lab, xs, key) in (("A", A, "A"), ("B", B, "B")), k in ("o", "i", "ii", "iii")
    println("  series $lab ($k): shift ", sort([(v, count(e -> e[key][k]["shift"] == v, xs)) for v in ("holds", "fails", "undetermined")]),
            " D>0 $(count(e -> e[key][k]["D"] > 0, xs))/$(length(xs))")
end
println("  Q-B one-step: usable $(length(qb1)), pool differs $(count(x -> x["pool_diff"] != 0, qb1)), crossed $(count(x -> x["crossed"], qb1)), receptor diff $(count(x -> !isempty(x["diff"]), qb1))")
println("  Q-B NT: usable $(length(qbn)), pool differs $(count(x -> x["pool_diff"] != 0, qbn)), crossed $(count(x -> x["crossed"], qbn)), receptor diff $(count(x -> !isempty(x["diff"]), qbn)), ",
        "realized m1 $(sort(unique(vcat([x["realized"] for e in ev for x in (e["QB_nt_m1"],) if x["usable"]]...)))) m2 $(sort(unique(vcat([x["realized"] for e in ev for x in (e["QB_nt_m2"],) if x["usable"]]...))))")
println("  Q-B NT exclusions: ", sort([(w, count(e -> e["QB_nt_$m"]["why"] == w, ev)) for m in ("m1",) for w in unique([e["QB_nt_m1"]["why"] for e in ev])]))
for (lab, rs) in (("seeds 51-60", r["runs"]), ("named", r["named"]))
    qc = [e["QC"] for x in rs for e in x["events"]]
    for ty in ("q", "sg", "other")
        xs = [c for c in qc if c["type"] == ty && c["why"] == ""]
        dd = [c for c in xs if c["answer_d_differs"]]
        lat = sort([c["latency"] for c in dd])
        println("  Q-C $lab type $ty: cases $(length(xs)), answer d differs $(length(dd)), sign differs $(count(c -> c["answer_sign_differs"], xs)), switched $(count(c -> c["switched"], dd)), latency median $(isempty(lat) ? "-" : lat[cld(length(lat), 2)])")
    end
    println("  Q-C $lab excluded/other reasons: ", sort([(w, count(c -> c["why"] == w, qc)) for w in unique([c["why"] for c in qc])]))
end
println(ok ? "check_clamp: ok" : "check_clamp: FAILED")
exit(ok ? 0 : 1)
