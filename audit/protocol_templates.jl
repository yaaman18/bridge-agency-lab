# AgencySubstrate's own evaluation of its frozen templates (fixtures/templates.toml), with or without the lab's adapter
# loaded. audit.jl runs it both ways and requires the same output: the adapter adds methods for LabSubstrate only and
# must not change the protocol's judgments. Usage: julia --project=. audit/protocol_templates.jl [with-adapter]
if get(ARGS, 1, "") == "with-adapter"
    include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
    include(joinpath(@__DIR__, "agency_adapter.jl"))
end
using AgencySubstrate
setup = load_templates()
for t in setup.templates
    r = evaluate(t.substrate, setup)
    println(t.name, " L2=", r.agency, " L3=", r.self_producing, " L3R=", r.self_repairing, " core=", r.core,
            " tracking=", r.value_tracking, " survival=", sort(collect(r.survival)))
end
