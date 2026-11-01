using AgencySubstrate
const AS = AgencySubstrate
include(joinpath(@__DIR__, "variant_freq.jl")); include(joinpath(@__DIR__, "variant_digest.jl")); include(joinpath(@__DIR__, "variant_digest_repair.jl"))
include(joinpath(@__DIR__, "variant_tracking_sets.jl"))
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
base = load_templates(); state = Ref(UInt64(20261009)); x = nothing
for k in 1:442; global x = random_substrate(state); end
r = Base.invokelatest(evaluate, x, base)
println("theta=", Dict(zip(x.names, x.theta)), "\nedges=", [(x.names[a], x.names[b], w) for (a, b, w) in x.edges], "\ncore=", r.core, " sets=", r.tracking_sets, " choices=", r.choices)
id(n) = findfirst(==(n), x.names)
for sil in (["s2"], ["x1"], ["s2", "x1"])
    println(sil, " => ", Dict(c.name => sort([x.names[m] for m in Base.invokelatest(AS.choice, x, base.choice_params, c, base.choice_window; silenced=Set{Int}(id.(sil)))]) for c in base.choice))
end
