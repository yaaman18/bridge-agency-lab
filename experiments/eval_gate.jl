# Item 76 step 2 (user 2026-11-02 "じゃあその順番でやってみて"): the core gate (core/circuit.jl step!(...; core_gate = true),
# formal/LabCircuit.lean CoreGate) on body_org with bin3 + idle_first. Predictions: experiments/predictions-gate.md
# (freeze-gate.txt). AGENCY-001's verdicts: variant_horizon.jl with GATE=1 (results-horizon-gate.json; LOW=4 too).
# Usage: julia --project=. experiments/eval_gate.jl
include(joinpath(@__DIR__, "variant_horizon.jl"))
using JSON
const LC = LabCore
res = Dict{String,Any}()
su = LBA.setup_with(392); p, pc = su.params, su.choice_params
for seed in 1:10
    s = LBA.BodyOrg(seed; abundant_r0 = pc.resource0, contrast = :bin3, idle_first = true, core_gate = true)
    core = Set(LC.unit(s.b, n) for n in ("c1", "c2")); mot = [LC.unit(s.b, n) for n in ("m1", "m2")]
    # with the core silenced, is any patch motor ever on (choice schedules, the whole horizon)?
    on_without_core = sum(count(st -> any(m -> st.active[m], mot), AS.run_trajectory(s, pc, x; silenced = core)) for x in su.choice)
    # raising: switches of the school winner (as eval_body_bin3.jl)
    b = LC.newborn(false); c = LC.init(b); nz = LC.Mulberry(seed); sw = 0; last = 0; acts = [0, 0]
    for (i, y) in enumerate(LC.BO_CUR)
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = nz, contrast = :bin3, idle_first = true, core_gate = true)
        i > 400 || continue
        pa = [b.patch[m] for m in o.acting if b.patch[m] <= 2]; for q in pa; acts[q] += 1; end
        if length(pa) == 1; (last != 0 && pa[1] != last) && (sw += 1); last = pa[1]; end
    end
    res["seed$seed"] = Dict("motor_on_steps_core_silenced" => on_without_core, "school_switches" => sw, "school_acts" => acts)
    println("seed $seed: patch motor on with the core silenced (choice runs) ", on_without_core, " steps; school switches ", sw, " acts ", acts)
end
o = (U = 0.02, MCOST = 0.004, STEPS = 10000)
ds = [body_org_run("ORG", s, merge(o, (CONTRAST = "bin3", IDLE = true, GATE = true)))["death"] for s in 1:10]
res["body_org_ORG_death"] = ds
println("body_org ORG 10000 steps bin3+idle+gate: survived ", count(isnothing, ds), "/10, deaths ", ds)
write(joinpath(@__DIR__, "results-gate.json"), JSON.json(res, 2))
println("written experiments/results-gate.json")
