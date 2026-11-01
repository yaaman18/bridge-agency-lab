# Post hoc (2026-10-29): agents whose choice does not follow the better patch. Counted under the adopted
# reading (frozen criteria) and under the digestion reading (+ frequency choice, + minimal sets).
using AgencySubstrate
const AS = AgencySubstrate
mode = ARGS[1]
if mode == "digest"
    include(joinpath(@__DIR__, "variant_freq.jl")); include(joinpath(@__DIR__, "variant_digest.jl")); include(joinpath(@__DIR__, "variant_digest_repair.jl"))
    include(joinpath(@__DIR__, "variant_tracking_sets.jl"))
end
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
patchset(x, names) = Set(x.motors[findfirst(==(n), x.names)] for n in names)
function main()
    base = load_templates(); state = Ref(UInt64(20261009)); n = 0; inv = 0; shown = 0
    for k in 1:20000
        x = random_substrate(state); r = Base.invokelatest(evaluate, x, base)
        r.agency || continue
        n += 1
        a = patchset(x, r.choices["c1-better"]); b = patchset(x, r.choices["c2-better"])
        follows = (1 in a) && (2 in b)
        follows && continue
        inv += 1
        if shown < 3
            shown += 1
            println("k=$k choices=", r.choices, " core=", r.core, " tracking=", r.value_tracking, "\n   survival=", get(r, :survival, "-"),
                    haskey(r, :survival_without_tracking) ? "  without=" * string(r.survival_without_tracking) : "")
        end
    end
    println(mode, ": agents ", n, ", not following the better patch ", inv)
end
main()
