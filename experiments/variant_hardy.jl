# Hardiness trial (2026-10-29, user request: "the agent dies too easily, like Spelunker").
# Applies variant_precision.jl with one change to the patch sensors: a patch sensor fires when its patch
# yields something AND is not worse than the other. (Rev. 2 of the world used "not worse" only, so in a
# famine, at yields (0, 0), both sensors fired and drove both motors: the agent burned fastest exactly
# when there was nothing to get.) The reserve capacity rmax is varied separately by the caller.
let src = read(joinpath(@__DIR__, "variant_precision.jl"), String)
    old = "yield_of(sch, patch, st.t) > yield_of(sch, 3 - patch, st.t)"
    count(old, src) == 1 || error("edit target not unique")
    include_string(Main, replace(src, old => "yield_of(sch, patch, st.t) > 0 && yield_of(sch, patch, st.t) >= yield_of(sch, 3 - patch, st.t)"))
end
