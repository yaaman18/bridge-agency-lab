using AgencySubstrate, Random
const AS = AgencySubstrate
ad = load_templates(joinpath(@__DIR__, "designs-adapt2.toml")); s = ad.templates[1].substrate; p = ad.params
r = MersenneTwister(1); g = [rand(r, 1:2) for _ in 1:20]; println(g)
st = AS.initial_state(s, p); log = String[]
for t in 1:200
    y = g[cld(t, 10)] == 1 ? (5, 0) : (0, 5)
    AS.step!(st, s, p, AS.Schedule("e", y, y, 0), Set{Int}())
    push!(log, string(t, " ", y[1] > 0 ? "P1" : "P2", " r=", st.resource, " act=", join([s.names[u] for u in 1:AS.nunits(s) if st.active[u]], ","), " str=", st.strength, st.dead ? " DEAD" : ""))
    st.dead && break
end
foreach(println, log[max(1, end - 25):end])
