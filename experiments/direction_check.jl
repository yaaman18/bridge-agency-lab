# Post hoc trial (2026-10-29, not adopted): add a direction condition to agency. With A_i the choice in
# choice schedule i and val_i(A) the summed yield of the patches of A under schedule i: directed iff
# val_1(A_1) > val_1(A_2) and val_2(A_2) > val_2(A_1) (in each context the system's own choice is worth more
# there than the choice it makes in the other context). Computed from evaluate's output; criteria unchanged.
using AgencySubstrate
const AS = AgencySubstrate
mode = ARGS[1]
if mode == "digest"
    include(joinpath(@__DIR__, "variant_freq.jl")); include(joinpath(@__DIR__, "variant_digest.jl")); include(joinpath(@__DIR__, "variant_digest_repair.jl"))
    include(joinpath(@__DIR__, "variant_tracking_sets.jl"))
end
include("/Users/yamaguchimitsuyuki/bridge-protocol/logs/gates/AGENCY-001/sweep-and-search-generator.jl")
const FX = "/Users/yamaguchimitsuyuki/bridge-protocol/tools/AgencySubstrate/fixtures"
val(x, set, sch, names) = sum((AS.yield_of(sch, x.motors[findfirst(==(n), x.names)], 0) for n in names); init=0)
function directed(x, set, r)
    A1 = r.choices[set.choice[1].name]; A2 = r.choices[set.choice[2].name]
    val(x, set, set.choice[1], A1) > val(x, set, set.choice[1], A2) && val(x, set, set.choice[2], A2) > val(x, set, set.choice[2], A1)
end
function main()
    files = mode == "digest" ? [joinpath(@__DIR__, "templates-digest.toml")] :
        [joinpath(FX, f) for f in ("templates.toml", "templates-adversarial.toml", "templates-adversarial-2.toml", "templates-adversarial-3.toml", "templates-adversarial-4.toml", "templates-repair.toml")]
    for f in files, t in load_templates(f).templates
        set = load_templates(f); r = Base.invokelatest(evaluate, t.substrate, set)
        r.agency && !directed(t.substrate, set, r) && println("   labelled-set agent NOT directed: ", t.name, " label L2=", t.L2)
    end
    base = load_templates(); state = Ref(UInt64(20261009)); n = 0; d = 0
    for k in 1:20000
        x = random_substrate(state); r = Base.invokelatest(evaluate, x, base)
        r.agency || continue
        n += 1; directed(x, base, r) && (d += 1)
    end
    println(mode, ": random agents ", n, ", directed ", d)
end
main()
