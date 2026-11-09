# S7 post hoc diagnostic (not a prediction): in the arms where DC fails at every branch point (seed 35/37 :swap p2-high),
# which receptor -> motor contingencies are kept (q >= 1) and which only by sediment (q = 0, sg >= 1), at the end of the main run.
include(joinpath(@__DIR__, "..", "variant_horizon.jl"))
using .LabBodyAgency
const LBA = LabBodyAgency; const LC = LBA.LC
for seed in (35, 37, 36), cur in (:swap, :std)
    su = LBA.setup_with(294); p = su.params; sch = su.survival[2]
    s = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true, contrast = :bin3,
                    cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
    st = AS.initial_state(s, p); acts = Dict{String,Int}()
    LBA.ON_STEP[] = (st_, o, c, y) -> for m in o.acting; acts[s.names[m]] = get(acts, s.names[m], 0) + 1; end
    for _ in 1:294; AS.step!(st, s, p, sch, Set{Int}()); end
    LBA.ON_STEP[] = nothing
    c = s.side[st].c
    e(f) = join(["$(s.names[a])->$(s.names[b]) q$(c.q[k]) sg$(c.sg[k])" for (k, (a, b, _)) in enumerate(s.edges) if f(a, b, k)], ", ")
    println("seed=$seed $cur $(sch.name) acts=$acts")
    println("  R->m2 (q or sg >0): ", e((a, b, k) -> s.b.kind[a] == 'R' && s.names[b] == "m2" && (c.q[k] > 0 || c.sg[k] > 0)))
    println("  C->m2 (q or sg >0): ", e((a, b, k) -> s.b.kind[a] == 'C' && s.names[b] == "m2" && (c.q[k] > 0 || c.sg[k] > 0)))
end
