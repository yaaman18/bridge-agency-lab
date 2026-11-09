# G8 follow-up (not a prediction, codex G7・G8 5): the first update at which cOff of r2->m2 and r8->m2 becomes finite in the sediment-only arms
# (seeds 35, 37, 110 :swap p2-high, H 392): the values before and after, whether the source receptor was on (old) at that update, whether m2
# acted and was answered, the observed v, whether the edge was confirmed, and whether cc = cOn - cOff is ever != 0 later.
include(joinpath(@__DIR__, "..", "variant_horizon.jl"))
using .LabBodyAgency
const L = LabBodyAgency; const LC = L.LC
su = L.setup_with(392); p = su.params; sch = su.survival[2]
for seed in (35, 37, 110)
    s = L.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true, contrast = :bin3, cur = :swap, core_gate = true, sed_fade = true, KC_trial = 0.0015)
    st = AS.initial_state(s, p); S = s.side[st]; m2 = LC.unit(s.b, "m2")
    ks = [(s.names[a], k, a) for (k, (a, c, _)) in enumerate(s.edges) if c == m2 && s.names[a] in ("r2", "r8")]
    first = Dict{String,Any}(); later_nonzero = Dict(n => 0 for (n, _, _) in ks)
    for t in 1:392
        pre_off = Dict(n => S.c.cOff[k] for (n, k, _) in ks); pre_on = Dict(n => S.c.cOn[k] for (n, k, _) in ks); old = copy(S.c.active)
        conf = Ref{Any}(nothing); ans = Ref(false); acted = Ref(false); yy = Ref{Any}(nothing)
        L.ON_STEP[] = (st_, o, c, y) -> st_ === st && (conf[] = copy(o.confirmed_patch); acted[] = m2 in o.acting; ans[] = get(o.answered, m2, false); yy[] = copy(y))
        AS.step!(st, s, p, sch, Set{Int}()); L.ON_STEP[] = nothing
        for (n, k, a) in ks
            if isnan(pre_off[n]) && !isnan(S.c.cOff[k]) && !haskey(first, n)
                first[n] = (t = t, cOff_before = pre_off[n], cOff_after = S.c.cOff[k], cOn = pre_on[n], source_on_old = old[a], m2_acted = acted[], answered = ans[], y = yy[], confirmed = conf[] === nothing ? nothing : conf[][k])
            end
            haskey(first, n) && t > first[n].t && !isnan(S.c.cOff[k]) && S.c.cOn[k] - S.c.cOff[k] != 0 && (later_nonzero[n] += 1)
        end
    end
    delete!(s.side, st)
    for (n, _, _) in ks; println("seed=$seed $n->m2 first finite cOff: $(get(first, n, "never")) ; later updates with cc != 0: $(later_nonzero[n])"); end
end
