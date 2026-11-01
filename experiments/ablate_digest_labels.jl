# Post hoc check (2026-10-29): which frozen labels of templates-digest.toml depend on each mechanism.
using AgencySubstrate
const AS = AgencySubstrate
include(joinpath(@__DIR__, "variant_freq.jl"))
include(joinpath(@__DIR__, "variant_digest.jl"))
include(joinpath(@__DIR__, "variant_digest_repair.jl"))
set = load_templates(joinpath(@__DIR__, "templates-digest.toml"))
for (lab, g, e) in [("both on", true, true), ("DIGEST_GATE off", false, true), ("EXPLORE off", true, false)]
    AS.DIGEST_GATE[] = g; AS.EXPLORE[] = e
    bad = String[]
    for t in set.templates
        r = Base.invokelatest(evaluate, t.substrate, set)
        for (nm, w, x) in (("L2", t.L2, r.agency), ("L3", t.L3, r.self_producing), ("L3R", t.L3R, r.self_repairing))
            w == x || push!(bad, "$(t.name).$nm")
        end
    end
    println(rpad(lab, 18), length(bad), " disagree: ", join(bad, ", "))
end
