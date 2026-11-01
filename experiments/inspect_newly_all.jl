# Post hoc: for random circuits that become agents only with minimal sets, does silencing the larger set
# change the choice to "nothing" (activity stops) or to another motor?
using AgencySubstrate
const AS = AgencySubstrate
include(joinpath(@__DIR__, "variant_freq.jl")); include(joinpath(@__DIR__, "variant_digest.jl")); include(joinpath(@__DIR__, "variant_digest_repair.jl"))
include(joinpath(@__DIR__, "variant_tracking_sets.jl"))
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
function main()
    base = load_templates(); state = Ref(UInt64(20261009))
    for k in 1:20000
        x = random_substrate(state); r = Base.invokelatest(evaluate, x, base)
        (r.agency && any(S -> length(S) > 1, r.tracking_sets)) || continue
        id(n) = findfirst(==(n), x.names)
        T1 = [id(only(S)) for S in r.tracking_sets if length(S) == 1]
        a1 = Base.invokelatest(AS.value_needed, x, base.params, base.survival, T1)
        a1 && continue
        for S in filter(S -> length(S) > 1, r.tracking_sets)
            after = Dict(c.name => sort([x.names[m] for m in Base.invokelatest(AS.choice, x, base.choice_params, c, base.choice_window; silenced=Set{Int}(id.(S)))]) for c in base.choice)
            println("k=$k set=$S intact=", r.choices, " silenced=", after)
        end
    end
end
main()
