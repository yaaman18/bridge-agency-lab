# Export a reference trajectory (selfloop-pair-agent and omnivore, 1000 steps, world env_digest_wta.jl, final
# rule set) for checking the JavaScript port used by the viewer.
using AgencySubstrate, TOML
const AS = AgencySubstrate
for f in ("variant_freq.jl", "variant_digest.jl", "variant_digest_repair.jl", "variant_tracking_sets.jl", "variant_direction.jl", "variant_attention.jl", "variant_select.jl")
    include(joinpath(@__DIR__, f))
end
include(joinpath(@__DIR__, "env_digest_wta.jl"))
set = load_templates(joinpath(@__DIR__, "templates-digest.toml")); p = set.params
open(joinpath(@__DIR__, "reference_trace.txt"), "w") do io
    for nm in ("selfloop-pair-agent", "omnivore", "alternator")
        s = only(t for t in set.templates if t.name == nm).substrate
        st = AS.initial_state(s, p); R = [CAP, CAP]
        for t in 1:1000
            y = (min(R[1], 5), min(R[2], 5))
            AS.step!(st, s, p, AS.Schedule("w", y, y, 0), Set{Int}())
            offer = [0, 0]; for (m, pa) in s.motors; st.active[m] && (offer[pa] = y[pa]); end
            d = AS.allocate(offer); g = season(t); R = [min(CAP, R[i] - d[i] + g[i]) for i in 1:2]
            println(io, nm, " ", t, " ", join(Int.(st.active), ""), " ", join(st.strength, ","), " ", R[1], ",", R[2])
        end
    end
end
