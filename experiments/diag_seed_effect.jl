# Diagnostic (read-only, item 146): how much does the seed change RB (fork.jl's org, S34-S43)? The seed enters only as the
# noise rng of r5 ("noise", core/circuit.jl:15). For each seed and arm: the raised circuit (q, sg, lastM) and, per schedule,
# the main run (H 392) with r5 removed from the active vector. Counts the distinct classes among the seeds.
# Writes experiments/results-diag-seed-effect.json (OUT). No prediction: a diagnostic of existing setups, not a claim.
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency; const LC = LBA.LC; const AS = LBA.AS
const H = 392
const SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(vcat(431:440, 461:470, 501:510), ",")), ",")))
org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
    contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = true, rest_body = :B)
su = LBA.setup_with(H); p = su.params
s0 = org(1, su, :swap); R5 = LC.unit(s0.b, "r5")
@assert LC.FEATURES[s0.b.perm[s0.b.feat[R5]]][1] == "noise"
res = Dict{String,Any}("H" => H, "seeds" => SEEDS, "runs" => Any[])
for cur in (:swap, :std), seed in SEEDS
    s = org(seed, su, cur)
    raise = string(hash((s.raised.q, s.raised.sg, s.raised.lastM)))
    for sch in su.survival
        st = AS.initial_state(s, p); S = s.side[st]; tr = Vector{Vector{Bool}}(); n5 = 0
        for t in 1:H
            AS.step!(st, s, p, sch, Set{Int}())
            push!(tr, [st.active[u] for u in eachindex(st.active) if u != R5]); n5 += st.active[R5]
        end
        push!(res["runs"], Dict("arm" => String(cur), "seed" => seed, "schedule" => sch.name, "raise" => raise,
            "traj_no_r5" => string(hash(tr)), "r5_on" => n5, "dead" => st.dead, "Q_H" => LBA.body_quantity(S.w)))
    end
end
println("arm   schedule      seeds  raised-classes  traj(no r5)-classes  dead")
for cur in ("swap", "std"), sch in unique(r["schedule"] for r in res["runs"])
    rs = filter(r -> r["arm"] == cur && r["schedule"] == sch, res["runs"])
    println(rpad(cur, 6), rpad(sch, 14), rpad(length(rs), 7), rpad(length(unique(r["raise"] for r in rs)), 16),
            rpad(length(unique(r["traj_no_r5"] for r in rs)), 21), count(r -> r["dead"], rs))
end
for cur in ("swap", "std")
    rs = filter(r -> r["arm"] == cur, res["runs"]); cls = unique(r["raise"] for r in rs)
    println(cur, " raised classes: ", [(c[1:6], sort(unique(r["seed"] for r in rs if r["raise"] == c))) for c in cls])
end
out = get(ENV, "OUT", joinpath(@__DIR__, "results-diag-seed-effect.json")); write(out, JSON.json(res)); println("written ", out)
