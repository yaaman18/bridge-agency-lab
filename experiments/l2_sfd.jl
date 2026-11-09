# S25 (b) (spec discussion/specs/S25-body-sfd.md r1): the tool L2 under SF and SFD (COND), the main block of variant_horizon.jl
# (SF defaults) with SEDFADE_DRIVE set; variant_horizon.jl itself is not changed (its sha is in freeze-sfd.txt).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using JSON
const COND = get(ENV, "COND", "SF"); COND in ("SF", "SFD") || error("COND")
LBA.SEDFADE_DRIVE[] = COND == "SFD"
const LAB = normpath(joinpath(@__DIR__, ".."))
const HS = [60, 294, 392, 588]
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(291:310, ",")), ","))
res = Dict{String,Any}("spec" => "discussion/specs/S25-body-sfd.md r1", "cond" => COND, "seeds" => SEEDS, "horizons" => HS, "runs" => Any[])
for cur in (:std, :swap), H in HS
    su = LBA.setup_with(H)
    for seed in SEEDS, structure in (:constituents, :q)
        s = LBA.BodyOrg(seed; structure, abundant_r0 = su.choice_params.resource0, idle_first = true, contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
        r = AS.evaluate(s, su)
        push!(res["runs"], Dict("arm" => String(cur), "H" => H, "seed" => seed, "structure" => String(structure), "agency_L2" => r.agency, "value_needed" => r.value_needed,
                                "alive_somewhere" => r.alive_somewhere, "self_producing_L3" => r.self_producing, "value_tracking" => r.value_tracking))
    end
    println("$COND $cur H=$H L2 true ", count(x -> x["agency_L2"] && x["arm"] == String(cur) && x["H"] == H, res["runs"]), "/", 2 * length(SEEDS))
end
write(joinpath(LAB, "experiments", "results-sfd-l2-$COND.json"), JSON.json(res, 2))
println("written")
