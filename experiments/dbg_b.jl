using AgencySubstrate
const AS = AgencySubstrate
set = load_templates(joinpath(@__DIR__, "designs-b.toml")); p = set.params
s = set.templates[1].substrate
st = AS.initial_state(s, p)
for t in 1:200
    y = isodd(div(t - 1, 7)) ? (0, 5) : (5, 0)
    AS.step!(st, s, p, AS.Schedule("e", y, y, 0), Set{Int}())
    (t <= 24 || st.dead) && println(t, " ", y, " r=", st.resource, " act=", [s.names[u] for u in 1:AS.nunits(s) if st.active[u]], st.dead ? " DEAD" : "")
    st.dead && break
end
