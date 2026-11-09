# S22 evaluation of predictions-pool0.md (GP1-GP3) from results-pool0.json.
using JSON
d = JSON.parsefile(joinpath(@__DIR__, get(ENV, "IN", "results-pool0.json")))
P = d["P0"]; runs = d["runs"]
println("control POOL0=[0,0] equals default: ", d["control_pool0_default"])
j3(r, p) = !isempty(r[p]["j3_points"])
n = Dict(p => count(r -> j3(r, p), runs) for p in P)
println("runs $(length(runs)); j3 runs ", n, "; alive at end ", Dict(p => count(r -> r[p]["alive_end"], runs) for p in P))
z = [r for r in runs if j3(r, "0,0")]
gp1 = isempty(z) ? "not evaluable" : all(r -> !j3(r, "50U,50U"), z) ? "hit" : "miss"
ok2(r) = all(c -> c isa AbstractDict && c["update"] <= 3 && c["value"] == 1.0, r["0,0"]["j3_points"][1]["E_cOff"])
gp2 = isempty(z) ? "not evaluable" : all(ok2, z) ? "hit" : "miss"
gp3 = n["5U,5U"] <= n["0,0"] && n["50U,50U"] <= n["0,0"] ? "hit" : "miss"
println("GP1 ", gp1, "  GP2 ", gp2, "  GP3 ", gp3)
for r in runs, p in P
    j3(r, p) || continue
    x = r[p]["j3_points"]
    println("  $p seed=$(r["seed"]) $(r["arm"]) $(r["schedule"]) points $(length(x)) t=$(x[1]["t"]) m*=$(x[1]["m_star"]) E=$(x[1]["E"]) cOff=$(x[1]["E_cOff"])")
end
for p in P   # cOff status of r2->m2, r8->m2 on the :swap p2-high runs
    st = [get(r[p]["cOff"], e, nothing) for r in runs if r["arm"] == "swap" && r["schedule"] == "p2-high" for e in ("r2->m2", "r8->m2")]
    println("  $p swap p2-high r2/r8->m2 cOff: initially finite $(count(==("initially finite"), st)), undefined $(count(==("undefined to H"), st)), first in trial ",
            sort([Int(x[1]) for x in st if x isa AbstractVector])[1:min(end, 12)], " values ", unique([x[2] for x in st if x isa AbstractVector]))
end
