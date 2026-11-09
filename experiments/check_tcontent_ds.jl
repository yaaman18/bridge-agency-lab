# S5 (deepseek-lab's check): reads experiments/results-tcontent-ds.json; exit 0 iff the seeds are exactly 21..30, H are
# 294/392/588, there are 30 runs, both C0 flags are true on every arm, and the negative control is detected. The verdicts of
# the predictions (experiments/predictions-tcontent.md, CP1..CP6) are printed only.
# Usage: cd experiments && julia --project=.. check_tcontent_ds.jl
using JSON
LAB = normpath(joinpath(@__DIR__, ".."))
d = JSON.parsefile(joinpath(LAB, "experiments", "results-tcontent-ds.json"))
seeds, hs, runs = d["seeds"], d["horizons"], d["runs"]
fails = String[]
sort(seeds) == collect(21:30) || push!(fails, "seeds = $(seeds)")
sort(hs) == [294, 392, 588] || push!(fails, "horizons = $(hs)")
length(runs) == 30 || push!(fails, "runs = $(length(runs))")
length(unique((r["H"], r["seed"]) for r in runs)) == 30 || push!(fails, "runs repeat a (H, seed)")
for r in runs, a in ("std", "swap")
    (r[a]["C0_matches_S4"] === true && r[a]["C0_repeat_equal"] === true) || push!(fails, "C0 H=$(r["H"]) seed=$(r["seed"]) $a")
end
d["negative_control_detected"] === true || push!(fails, "negative_control_detected = $(d["negative_control_detected"])")

# the predictions, displayed only (never in the exit code)
cpall = [true, true, true, true, true, true]   # CP1..CP6
set!(i, v) = (cpall[i] = cpall[i] && v)
at(H, seed, a) = runs[findfirst(r -> r["H"] == H && r["seed"] == seed, runs)][a]
for r in runs, a in ("std", "swap")
    x = r[a]; k = x["kind"]; L = Set(x["confirmed_links"])
    set!(1, sort(x["discriminating_cues"]) == ["r7", "r8"])
    k == "P2" && set!(2, "r2->m2" in L && "r8->m2" in L)
    k == "P1" && set!(2, "r1->m1" in L && "r7->m1" in L)
    k == "P2" && set!(3, x["silenced_T"]["c1-better"] == "m1" && x["silenced_T"]["c2-better"] == "m1")
    k == "P1" && set!(3, x["silenced_T"]["c1-better"] == "m2" && x["silenced_T"]["c2-better"] == "m2")
    k == "P2" && set!(4, x["probes"]["eq-high"] == "m1")
    k == "P1" && set!(4, x["probes"]["eq-high"] == "m2")
    k == "P2" && set!(5, x["probes"]["lo-1"] == "m1" && x["probes"]["lo-2"] == "m1")
    k == "P1" && set!(5, x["probes"]["lo-1"] == "m2" && x["probes"]["lo-2"] == "m2")
    r["std"]["T"] == r["swap"]["T"] && set!(6, r["std"]["probes"] == r["swap"]["probes"])   # CP6
end
for seed in intersect((24, 28, 29), seeds), H in hs   # CP4: the arms differ on eq-high
    set!(4, at(H, seed, "std")["probes"]["eq-high"] != at(H, seed, "swap")["probes"]["eq-high"])
end
for i in 1:6
    println("CP$i: ", cpall[i] ? "holds" : "fails")
end
nfalse = count(r -> !(r["std"]["C0_matches_S4"] && r["std"]["C0_repeat_equal"] && r["swap"]["C0_matches_S4"] && r["swap"]["C0_repeat_equal"]), runs)
println("runs = $(length(runs)); runs with a C0 false = $nfalse; negative_control_detected = $(d["negative_control_detected"])")
if isempty(fails)
    println("check_tcontent_ds: ok")
    exit(0)
end
foreach(f -> println("FAIL ", f), first(fails, 10))
exit(1)
