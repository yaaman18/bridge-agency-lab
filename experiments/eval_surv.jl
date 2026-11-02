# Item 76 (user 2026-11-02 "じゃあその順番でやってみて", step 1): the survival schedules with both patches positive (the empty
# patch of each frozen schedule given LOW = 4, i.e. 5 vs 4; LOW = 1 reported), body_org with bin3 + idle_first (item 75),
# H = 392: does silencing the value-tracking units r2, r8 cost survival, or only the body's size? Predictions:
# experiments/predictions-surv.md (freeze-surv.txt). AGENCY-001's verdicts: variant_horizon.jl with LOW=4 (results-horizon-low4.json).
# Usage: julia --project=. experiments/eval_surv.jl
include(joinpath(@__DIR__, "variant_horizon.jl"))
using JSON
const LC = LabCore
res = Dict{String,Any}()
for low in (4, 1)
    su = LBA.setup_with(392; low); p, pc = su.params, su.choice_params
    for seed in 1:10
        s = LBA.BodyOrg(seed; abundant_r0 = pc.resource0, contrast = :bin3, idle_first = true)
        T = Set(LC.unit(s.b, n) for n in ("r2", "r8")); m1 = LC.unit(s.b, "m1"); m2 = LC.unit(s.b, "m2")
        for x in su.survival, (lab, sil) in (("intact", Set{Int}()), ("r2,r8 off", T))
            tr = AS.run_trajectory(s, p, x; silenced = sil)
            r = Dict("alive" => AS.alive(tr, s, p), "end_body" => sum(last(tr).strength), "m1" => count(st -> st.active[m1], tr),
                     "m2" => count(st -> st.active[m2], tr))
            res["low$low seed$seed $(x.name) $lab"] = r
            seed == 1 && println(rpad("low $low seed 1 $(x.name) $lab", 40), " alive ", r["alive"], " body end ", r["end_body"], " m1 ", r["m1"], " m2 ", r["m2"])
        end
    end
    for x in su.survival, lab in ("intact", "r2,r8 off")
        rs = [res["low$low seed$seed $(x.name) $lab"] for seed in 1:10]
        println(rpad("low $low all seeds $(x.name) $lab", 40), " alive ", count(r -> r["alive"], rs), "/10, body end ", [r["end_body"] for r in rs])
    end
end
write(joinpath(@__DIR__, "results-surv.json"), JSON.json(res, 2))
println("written experiments/results-surv.json")
