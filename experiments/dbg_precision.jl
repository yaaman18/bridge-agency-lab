using AgencySubstrate, Random
const AS = AgencySubstrate
include(joinpath(@__DIR__, "variant_precision.jl"))
set = load_templates(joinpath(@__DIR__, "designs.toml")); s = only(t for t in set.templates if t.name == "selfloop-pair-agent").substrate; p = set.params
r = MersenneTwister(1); g = [rand(r, 1:2) for _ in 1:20]
st = AS.initial_state(s, p); prev = copy(st.active)
for t in 1:200
    y = g[cld(t, 10)] == 1 ? (5, 0) : (0, 5)
    before = copy(st.strength)
    AS.step!(st, s, p, AS.Schedule("e", y, y, 0), Set{Int}())
    for m in keys(s.motors)
        ins = [k for (k, (_, d, _)) in enumerate(s.edges) if d == m]
        if st.active[m] && all(k -> before[k] == 0, ins)
            println("t=$t ", y, " motor ", s.names[m], " fired through stale contingencies ", [string(s.names[s.edges[k][1]], "->", s.names[m]) for k in ins], " store=", st.resource)
        end
    end
end
println("final dead=", st.dead, " store=", st.resource)
