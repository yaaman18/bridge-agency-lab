# S7 check (spec discussion/specs/S7-body-selfmaint.md r1): reads results-selfmaint-H{294,392,588}.json (the runs split by H),
# exit 0 when the seeds are 31..40, both arms, the 4 survival schedules, 240 runs, the controls worked, and the frozen sha
# matches. SP1-SP7 printed only (the Lean comparison is dc_lean_body.sh).
using JSON
const LAB = normpath(joinpath(@__DIR__, ".."))
fs = [JSON.parsefile(joinpath(LAB, "experiments", "results-selfmaint-H$H.json")) for H in (294, 392, 588)]
ok = true
fail(m) = (println("FAIL ", m); global ok = false)
for (f, H) in zip(fs, (294, 392, 588))
    f["seeds"] == collect(31:40) || fail("seeds H=$H")
    f["horizons"] == [H] || fail("horizon H=$H")
    f["arms"] == ["std", "swap"] || fail("arms H=$H")
end
runs = vcat([f["runs"] for f in fs]...)
length(runs) == 240 || fail("runs $(length(runs))")
keys4 = [(x["H"], x["seed"], x["arm"], x["schedule"]) for x in runs]   # codex I-R 8: each combination once
Set(keys4) == Set((H, s, a, c) for H in (294, 392, 588) for s in 31:40 for a in ("std", "swap") for c in ("p1-high", "p2-high", "p1-then-p2", "p2-then-p1")) && allunique(keys4) || fail("combinations")
fs[1]["controls_ok"] === true || fail("controls $(fs[1]["controls"])")
fs[1]["lean_windows"] > 0 || fail("no Lean windows")
sha = split(read(joinpath(LAB, "experiments", "freeze-selfmaint.txt"), String))[1]
sha == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", "predictions-selfmaint.md"))`, String))[1] || fail("freeze sha")
ev = [e for x in runs for e in x["events"]]
frac(f) = isempty(ev) ? NaN : count(f, ev) / length(ev)
sp1 = all(e -> e["conf_X"] == 0 && e["conf_Y"] == 0, ev)
# codex I-R 6: one confirmation in any X branch refutes the L9 map for all (b1) (D2 §5), not only for that branch point
l9 = all(e -> e["conf_X"] == 0, ev)
l9 || println("L9 map refuted by an X-branch confirmation: every (b1), and every T resting on it, is undetermined")
sp2 = all(e -> e["b1"] == "holds", ev)
sp3 = all(e -> e["death_X"] !== nothing, ev)
sp4 = all(e -> e["death_Y"] == e["death_X"], ev)
nalive = frac(e -> e["death_N"] === nothing)
afrac = frac(e -> e["a"] == "holds")
aliveH = [x for x in runs if x["alive_at_H"]]
sp6b = all(x -> any(e -> e["T"] == "holds", x["events"]), aliveH)
sp7 = all(e -> e["T_core"] == e["T"], ev)
println("branch points $(length(ev)) in $(length(runs)) runs (alive at H: $(length(aliveH)))")
println("SP1 $sp1  SP2 $sp2  SP3 $sp3  SP4 $sp4  SP5 $(nalive >= 0.9) (N alive at t+H $(round(nalive; digits = 3)))  ",
        "SP6 $(afrac >= 0.5 && sp6b) ((a) $(round(afrac; digits = 3)), T in every run alive at H: $sp6b)  SP7 $sp7")
for k in ("a", "b1", "b2", "b3", "T", "T_core")
    println("  $k: ", sort([(v, count(e -> e[k] == v, ev)) for v in unique([e[k] for e in ev])]))
end
for H in (294, 392, 588), sch in unique([x["schedule"] for x in runs])
    rs = [x for x in runs if x["H"] == H && x["schedule"] == sch]; es = [e for x in rs for e in x["events"]]
    tp = [e["Tplus_t1"] - e["t"] for e in es if e["Tplus_t1"] !== nothing]
    println("  H=$H $(rpad(sch, 11)) runs alive at H $(count(x -> x["alive_at_H"], rs))/$(length(rs)) points $(length(es)) T $(count(e -> e["T"] == "holds", es)) ",
            "b2 fails $(count(e -> e["b2"] == "fails", es)) (N dies $(count(e -> e["death_N"] !== nothing, es)), X lives $(count(e -> e["death_X"] === nothing, es))) ",
            "dc(all events) $(round(sum(x -> something(x["dc_rate_all_events"], 0.0), rs) / length(rs); digits = 2)) T+ length median $(isempty(tp) ? "-" : sort(tp)[cld(length(tp), 2)])")
end
println(ok ? "check_selfmaint: ok" : "check_selfmaint: FAILED")
exit(ok ? 0 : 1)
