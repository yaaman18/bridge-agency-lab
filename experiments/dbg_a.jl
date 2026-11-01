using AgencySubstrate, Random
const AS = AgencySubstrate
include(joinpath(@__DIR__, "variant_freq.jl"))
ad = load_templates(joinpath(@__DIR__, "designs-adapt.toml")); s = ad.templates[1].substrate; p = ad.params
r = Base.invokelatest(evaluate, s, ad)
println("core=", r.core, " hinge=", r.core_enables_action, " alive_somewhere=", r.alive_somewhere, " diff=", r.differentiated, " needed=", r.value_needed, " surv=", r.survival)
for (nm, sch) in [("p1-high", ad.survival[1]), ("flip7", nothing)]
    st = AS.initial_state(s, p); println("-- ", nm)
    for t in 1:60
        y = sch === nothing ? (isodd(div(t - 1, 7)) ? (0, 5) : (5, 0)) : AS.yield_of(sch, 1, t - 1) == 5 ? (5, 0) : (0, 5)
        AS.step!(st, s, p, AS.Schedule("e", y, y, 0), Set{Int}())
        (t <= 22 || st.dead) && println(t, " ", y, " r=", st.resource, " act=", [s.names[u] for u in 1:AS.nunits(s) if st.active[u]], st.dead ? " DEAD" : "")
        st.dead && break
    end
end
