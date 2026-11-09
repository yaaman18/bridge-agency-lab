# D6 LL2 check (not a prediction): the per-update trace (active units, q, sg, h, pools, body) of a main run is the same with the read-only
# hook ON_STEP set and unset, and with CLAMP returning (y, y), for one object of each arm and each survival schedule (seed 1, H 392).
include(joinpath(@__DIR__, "..", "variant_horizon.jl"))
using .LabBodyAgency
const L = LabBodyAgency; const LC = L.LC
su = L.setup_with(392); p = su.params
function trace(s, sch; hook = false, clamp = false)
    L.ON_STEP[] = hook ? ((st, o, c, y) -> nothing) : nothing
    L.CLAMP[] = clamp ? ((st, y) -> (y, y)) : nothing
    st = AS.initial_state(s, p); S = s.side[st]; tr = Any[]
    for _ in 1:392
        AS.step!(st, s, p, sch, Set{Int}())
        push!(tr, (copy(S.c.active), copy(S.c.q), copy(S.c.sg), copy(S.c.h), copy(S.pool), copy(S.w.C), copy(S.w.A)))
    end
    delete!(s.side, st); L.ON_STEP[] = nothing; L.CLAMP[] = nothing
    tr
end
ok = true
for cur in (:std, :swap), sch in su.survival
    s = L.BodyOrg(1; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true, contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
    a, b, c = trace(s, sch), trace(s, sch; hook = true), trace(s, sch; clamp = true)
    same = isequal(a, b) && isequal(a, c); global ok &= same
    println("seed=1 $cur $(rpad(sch.name, 11)) per-update trace equal (hook, clamp): $same")
end
println(ok ? "trace check: ok" : "trace check: DIFFERENT")
