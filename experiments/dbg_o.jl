using AgencySubstrate
const AS = AgencySubstrate
set = load_templates(joinpath(@__DIR__, "designs-opt1.toml")); p = set.params; s = set.templates[1].substrate
st = AS.initial_state(s, p); prev = copy(st.strength)
for t in 1:200
    y = isodd(div(t - 1, 7)) ? (0, 5) : (5, 0)
    AS.step!(st, s, p, AS.Schedule("e", y, y, 0), Set{Int}())
    grown = sum(max.(st.strength .- prev, 0)); global prev = copy(st.strength)
    (t <= 30 || st.dead) && println(t, " ", y, " r=", st.resource, " grow=", grown, " act=", [s.names[u] for u in 1:AS.nunits(s) if st.active[u]], st.dead ? " DEAD" : "")
    st.dead && (println("strengths ", [string(s.names[a], "->", s.names[b], "=", st.strength[k]) for (k, (a, b, _)) in enumerate(s.edges)]); break)
end
