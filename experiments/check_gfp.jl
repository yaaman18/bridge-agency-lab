# S27 evaluation (predictions-gfp.md): C2 and GP1-GP3 from results-gfp-{gfp,kappa}.json; C1 is the Lean #eval of AgentBodyGfp-nu.
using JSON
g = JSON.parsefile(joinpath(@__DIR__, "results-gfp-gfp.json"))["objects"]; k = JSON.parsefile(joinpath(@__DIR__, "results-gfp-kappa.json"))["objects"]
@assert [(x["seed"], x["arm"]) for x in g] == [(x["seed"], x["arm"]) for x in k]
dcw = [x for x in g if x["dc"]["dc"]]
c2 = all(x -> x["kappa_sub_nu"] && x["gfp_ge_kappa"], dcw)
println("C2 (DC windows $(length(dcw))/20): kappa ⊆ nu_fin and value_gfp ≥ value_kappa: ", c2, "  (kappa ⊆ nu in all 20 windows: ", count(x -> x["kappa_sub_nu"], g), "/20)")
gp1 = count(x -> x["kappa_sub_nu"] && x["nu_has_receptor_edge"], g)
sup = count(((a, b),) -> issubset(Set(b["T_struct"]), Set(a["T_struct"])) && Set(a["T_struct"]) != Set(b["T_struct"]), zip(g, k))
gp3 = count(x -> x["builds"], g)
println("GP1 $(gp1 >= 15 ? "hit" : "miss") ($gp1/20)  GP2 $(sup >= 10 ? "hit" : "miss") ($sup/20)  GP3 $(gp3 >= 10 ? "hit" : "miss") ($gp3/20, Julia; Lean agent_lean.sh AgentBodyGfp)")
println("kappa mode builds $(count(x -> x["builds"], k))/20")
for (a, b) in zip(g, k)
    println("  seed=$(a["seed"]) $(a["arm"]) T_struct gfp $(sort(a["T_struct"])) kappa $(sort(b["T_struct"])) | |kappa| $(length(a["kappa"])) |nu| $(length(a["nu_fin"])) receptor edges in nu $(count(e -> startswith(e, "r"), a["nu_fin"])) | witness gfp $(a["witness"]) kappa $(b["witness"])")
end
