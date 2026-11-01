using AgencySubstrate, Random
const AS = AgencySubstrate
set = load_templates(joinpath(@__DIR__, "designs.toml")); p = load_templates().params
s = only(t for t in set.templates if t.name == "selfloop-pair-agent").substrate
rng = MersenneTwister(20261029); H = 200
g = [rand(rng, 1:2) for _ in 1:cld(H, 10)]; println("good patch per 10 steps: ", g)
yields = [g[cld(t, 10)] == 1 ? (5, 0) : (0, 5) for t in 1:H]
st = AS.initial_state(s, p)
for (t, y) in enumerate(yields)
    AS.step!(st, s, p, AS.Schedule("e", y, y, 0), Set{Int}())
    (t in (60, 70, 100, 120, 125, 128) || st.dead) && print(t, ":", y[1] > 0 ? "P1" : "P2", " r=", st.resource, " str=", [string(s.names[a], "->", s.names[b], "=", st.strength[k]) for (k, (a, b, _)) in enumerate(s.edges)], " act=", [s.names[u] for u in 1:AS.nunits(s) if st.active[u]], st.dead ? " DEAD" : "", "\n")
    st.dead && break
end
