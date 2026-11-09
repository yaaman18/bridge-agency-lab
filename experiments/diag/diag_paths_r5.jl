# S10 post hoc diagnostic (not a prediction): the raised state of the edges that reach m1/m2 in the S8 pairs (H 392),
# to see where the two arms differ when the r5 edges are at q = sg = 0 in both.
include(joinpath(@__DIR__, "..", "variant_horizon.jl"))
using .LabBodyAgency
const LBA = LabBodyAgency
su = LBA.setup_with(392)
for seed in (23, 24, 36)
    for a in (:std, :swap)
        s = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true, contrast = :bin3,
                        cur = a, core_gate = true, sed_fade = true, KC_trial = 0.0015)
        c = s.raised
        e = ["$(s.names[x])->$(s.names[y]) q$(c.q[k]) sg$(c.sg[k]) h$(c.h[k])" for (k, (x, y, _)) in enumerate(s.edges) if s.names[y] in ("m1", "m2") && (c.q[k] + c.sg[k] + c.h[k] > 0 || s.names[x] == "r5")]
        println("seed=$seed $a lastM=$(c.lastM === nothing ? "-" : c.lastM[[LBA.LC.unit(s.b, "m1"), LBA.LC.unit(s.b, "m2")]]) t=$(c.t): ", join(e, ", "))
    end
end
