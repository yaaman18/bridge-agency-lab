# S15 post hoc diagnostic (not a prediction): in the C1 window (choice schedule c1, updates 1..32) of seed 71 :std, which coupled
# receptors are on, which motors a kept contingency from an on coupled receptor drives, and which receptors those motors reach.
include(joinpath(@__DIR__, "..", "variant_horizon.jl"))
using .LabBodyAgency
const L = LabBodyAgency; const LC = L.LC
su = L.setup_with(392)
for (seed, cur) in ((71, :std), (75, :swap))
    s = L.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true, contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
    st = AS.initial_state(s, su.choice_params); recs = LC.DCStep[]
    L.ON_STEP[] = (st_, o, c, y) -> st_ === st && push!(recs, LC.dc_record(s.b, o, c; partner_live = false, y = y, phase = "world"))
    for _ in 1:32; AS.step!(st, s, su.choice_params, su.choice[1], Set{Int}()); end
    L.ON_STEP[] = nothing
    w = LC.dc_window(s.b, recs); n = s.names
    R = [e for e in eachindex(n) if s.b.kind[e] == 'R']; M = [m for m in eachindex(n) if s.b.kind[m] == 'M']
    coupled(e) = any(m -> w.affects[m, e], M)
    eps = [e for e in R if w.on[e] && coupled(e)]
    driven = [m for m in M if any(k -> w.kept[k] && s.edges[k][1] in eps && s.edges[k][2] == m, eachindex(s.edges))]
    reach = Set(e for m in driven for e in R if w.affects[m, e])
    println("seed=$seed $cur ε (on, coupled) = $(n[eps]); motors driven by a kept edge from ε = $(n[driven]); reached = $(n[sort(collect(reach))]); not reached = $(n[[e for e in eps if !(e in reach)]])")
    println("   kept r->m2: ", join(["$(n[a])->m2 q$(st === nothing ? "" : s.side[st].c.q[k])" for (k, (a, b, _)) in enumerate(s.edges) if n[b] == "m2" && s.b.kind[a] == 'R' && s.side[st].c.q[k] + s.side[st].c.sg[k] > 0], ", "))
end
