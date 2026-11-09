# S19 evaluation of predictions-sedfade-cause.md (GC1-GC4) from results-sedfade-cause.json.
using JSON, Statistics
d = JSON.parsefile(joinpath(@__DIR__, get(ENV, "IN", "results-sedfade-cause.json")))
pts = [(r, x) for r in d["runs"] for x in r["points"]]
usable = [(r, x) for (r, x) in pts if x["N"]["death"] === nothing && x["F"]["death"] === nothing]
nd = count(((r, x),) -> x["N"]["death"] !== nothing, pts); fd = count(((r, x),) -> x["F"]["death"] !== nothing, pts)
println("control override identity: ", d["control_override_identity"])
println("targets $(length(pts)) in $(count(r -> !isempty(r["points"]), d["runs"])) runs; both alive $(length(usable)); N died $nd, F died $fd")
ev(v) = isempty(usable) ? "not evaluable" : v ? "hit" : "miss"
gc1 = all(((r, x),) -> x["N"]["sgkept"] == false, usable)
fk = count(((r, x),) -> x["F"]["sgkept"] == true, usable); gc2 = fk > length(usable) / 2
decs = [dd for (r, x) in pts for dd in x["F"]["decs"]]
gc3 = isempty(decs) ? "not evaluable" : all(dd -> dd["route"] == "weaken", decs) ? "hit" : "miss"
diffs = [x["F"]["acts"] - x["N"]["acts"] for (r, x) in usable]
println("GC1 N sgkept false at all usable: ", ev(gc1), " (N sgkept true ", count(((r, x),) -> x["N"]["sgkept"] == true, usable), ")")
println("GC2 F sgkept true at > half: ", ev(gc2), " ($fk / $(length(usable)))")
println("GC3 F decreases all weaken: ", gc3, " (decreases $(length(decs)), routes ", Dict(k => count(dd -> dd["route"] == k, decs) for k in unique([dd["route"] for dd in decs])), ")")
println("GC4 median(F-N acts) > 0: ", isempty(diffs) ? "not evaluable" : ev(median(diffs) > 0), " (median $(isempty(diffs) ? "-" : median(diffs)))")
for r in d["runs"]; isempty(r["points"]) && continue
    u = [x for x in r["points"] if x["N"]["death"] === nothing && x["F"]["death"] === nothing]
    println("  seed=$(r["seed"]) $(r["arm"]) $(r["schedule"]) t=$([x["t"] for x in r["points"]]) E=$(r["points"][1]["E"]) sg_E=$(r["points"][1]["sg_E"]) ",
            "N sg0=$([x["N"]["sg0"] for x in r["points"]]) N acts=$([x["N"]["acts"] for x in u]) F acts=$([x["F"]["acts"] for x in u]) F qkept=$(count(x -> x["F"]["qkept"] == true, u)) N qkept=$(count(x -> x["N"]["qkept"] == true, u)) median diff $(isempty(u) ? "-" : median([x["F"]["acts"] - x["N"]["acts"] for x in u]))")
end
nroutes = [dd["route"] for (r, x) in pts for dd in x["N"]["decs"]]
println("N decreases by route (record): ", Dict(k => count(==(k), nroutes) for k in unique(nroutes)))
