using AgencySubstrate
const AS = AgencySubstrate
include(joinpath(@__DIR__, "variant_freq.jl"))
include(joinpath(@__DIR__, "variant_digest.jl"))
include(joinpath(@__DIR__, "variant_digest_repair.jl"))
set = load_templates(joinpath(@__DIR__, "templates-digest.toml")); println("templates-digest sha256 ", set.sha256)
agree = 0; total = 0
for t in set.templates
    r = Base.invokelatest(evaluate, t.substrate, set)
    want = (t.L2, t.L3, t.L3R); got = (r.agency, r.self_producing, r.self_repairing)
    global agree += count(i -> got[i] == want[i], 1:3); global total += 3
    println(rpad(t.name, 24), "label=", want, " got=", got, got == want ? "" : "  <-- DISAGREE",
        "  core=", r.core, " diff=", r.differentiated, " needed=", r.value_needed, " hinge=", r.core_enables_action)
end
println("agree ", agree, "/", total)
