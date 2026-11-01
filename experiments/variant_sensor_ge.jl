# World revision 2 (2026-10-29), after the first run of the depletion world (eval_world-v1.out): both
# stocks start full, so both yields are 5, and a patch sensor fires only when its patch is strictly
# richer. At a tie neither sensor fires, every agent's motors stop, and it starves by step 6. This file
# applies variant_precision.jl unchanged except that a patch sensor fires when its patch is AT LEAST as
# rich as the other ("not worse"). The frozen schedules have no ties, so the frozen labels are unaffected.
let src = read(joinpath(@__DIR__, "variant_precision.jl"), String)
    old = "yield_of(sch, patch, st.t) > yield_of(sch, 3 - patch, st.t)"
    count(old, src) == 1 || error("edit target not unique")
    include_string(Main, replace(src, old => "yield_of(sch, patch, st.t) >= yield_of(sch, 3 - patch, st.t)"))
end
