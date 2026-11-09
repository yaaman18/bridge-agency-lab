# S14 post hoc localization (not a prediction): in the residual pairs, move only the sg of r5->m2 from :swap to :std
# (the other sg differences left), and only the sg of the other differing edges, and compare the tie choices.
include(joinpath(@__DIR__, "..", "variant_horizon.jl"))
using .LabBodyAgency
const L = LabBodyAgency; const ASC = L.AS
su = L.setup_with(392)
o(s, c) = L.BodyOrg(s; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true, contrast = :bin3, cur = c, core_gate = true, sed_fade = true, KC_trial = 0.0015)
wr(S, r) = L.BodyOrg(S.names, S.edges, S.motors, S.b, r, S.noise, S.structure, S.abundant_r0, S.U, S.MCOST, S.idle_first, S.contrast, S.core_gate, S.seen_both, S.sed_fade, S.grow, S.KC, S.PER, S.w0, S.pool0, IdDict())
ch(s) = [join(sort([s.names[m] for m in ASC.choice(s, su.choice_params, ASC.Schedule("t", y, y, 20), su.choice_window)]), ",") for y in ((1, 1), (2, 2), (3, 3), (4, 4), (5, 5))]
for seed in (29, 39, 40)
    d, w = o(seed, :std), o(seed, :swap)
    k5 = only(k for (k, (a, b, _)) in enumerate(d.edges) if (d.names[a], d.names[b]) == ("r5", "m2"))
    r1 = deepcopy(d.raised); r1.sg[k5] = w.raised.sg[k5]
    r2 = deepcopy(d.raised); for k in eachindex(r2.sg); k != k5 && (r2.sg[k] = w.raised.sg[k]); end
    println("seed=$seed std $(ch(d)) swap $(ch(w)) | std + swap's r5->m2 sg: $(ch(wr(d, r1))) | std + swap's other sg: $(ch(wr(d, r2)))")
end
