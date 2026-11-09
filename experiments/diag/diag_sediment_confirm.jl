# G8 diagnosis (not a prediction): in the sediment-only arms (seeds 35, 37, 110 :swap p2-high, H 392), at the updates where m2 acted
# and was answered (gate) and r2->m2 or r8->m2 drove, why the edge was not confirmed: the bin3 contrast cc = cOn - cOff against
# THETA_B (passes, core/circuit.jl), and the other conditions of the confirmation (drove, target on, gate, answered).
include(joinpath(@__DIR__, "..", "variant_horizon.jl"))
using .LabBodyAgency
const L = LabBodyAgency; const LC = L.LC
su = L.setup_with(392); p = su.params; sch = su.survival[2]
for (seed, cur) in ((35, :swap), (37, :swap), (110, :swap), (35, :std))
    s = L.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true, contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
    st = AS.initial_state(s, p); S = s.side[st]
    m2 = LC.unit(s.b, "m2"); ks = [k for (k, (a, c, _)) in enumerate(s.edges) if c == m2 && s.names[a] in ("r2", "r8")]
    cnt = Dict{String,Int}()
    L.ON_STEP[] = (st_, o, c, y) -> begin
        st_ === st || return
        (m2 in o.acting && o.gate) || return
        for k in ks
            o.drove[k] || (cnt["not drove"] = get(cnt, "not drove", 0) + 1; continue)
            cc = c.cOn === nothing ? NaN : c.cOn[k] - c.cOff[k]
            key = o.confirmed_patch[k] ? "confirmed" : isnan(cc) ? "not confirmed, cc undefined (NaN)" : cc > LC.THETA_B ? "not confirmed, cc passes ($(round(cc; digits = 3)))" : "not confirmed, cc ≤ θ ($(round(cc; digits = 2)))"
            cnt[key] = get(cnt, key, 0) + 1
        end
    end
    for _ in 1:392; AS.step!(st, s, p, sch, Set{Int}()); end
    L.ON_STEP[] = nothing; delete!(s.side, st)
    println("seed=$seed $cur: ", join(sort(["$k => $v" for (k, v) in cnt]), "; "))
end
