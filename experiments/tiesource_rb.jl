# S38 (spec discussion/specs/S38-rb-tiesource.md r1): which receptor makes the tie acts on RB (S8's question on RB,
# notes/RB-redo.md §3). Interventions J (as S8) x the rb condition (normal input / rb clamped false through BODY_CLAMP),
# tie probes (1,1)..(5,5) built as in S8 (choice_params, switch 20, window 5:15). For each window step: m1, m2, m0 active
# (the same denominator: window steps x probes). Writes experiments/results-rb-tiesource.json.
# Predictions: predictions-rb-tiesource.md (frozen before the first run on the claim seeds).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const ASC = LBA.AS
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(451:460, ",")), ",")))
const H = 392
const TIES = [(1, 1), (2, 2), (3, 3), (4, 4), (5, 5)]
pname(y) = "$(y[1]),$(y[2])"
const IVS = [("J0", String[]), ("J3", ["r3"]), ("J4", ["r4"]), ("J5", ["r5"]), ("J6", ["r6"]), ("J12", ["r1", "r2"]), ("J56", ["r5", "r6"]),
             ("J125", ["r1", "r2", "r5"]), ("J126", ["r1", "r2", "r6"]), ("J1256", ["r1", "r2", "r5", "r6"])]
const RBC = ("normal", "rb_false")

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
    contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = true, rest_body = :B)

"""One probe: per window step, which of m1, m2, m0 are active; the rb input at the window's steps (as read, after the clamp)."""
function probe(s, pc, y, w, sil, rbc)
    LBA.BODY_CLAMP[] = rbc == "rb_false" ? (st -> false) : nothing
    acts = String[]   # the act of each update (the winner, step!'s acting; read-only hook)
    LBA.ON_STEP[] = (st, o, c, yy) -> push!(acts, isempty(o.acting) ? "none" : join(sort([s.b.names[m] for m in o.acting]), ","))
    traj = ASC.run_trajectory(s, pc, ASC.Schedule(pname(y), y, y, 20); silenced = sil)
    LBA.BODY_CLAMP[] = nothing; LBA.ON_STEP[] = nothing
    length(acts) == length(traj) - 1 || error("one act per update expected")
    u(n) = LC.unit(s.b, n)
    steps = [(m1 = traj[t + 1].active[u("m1")], m2 = traj[t + 1].active[u("m2")], m0 = traj[t + 1].active[u("m0")], rb = traj[t + 1].active[u("rb")], act = acts[t]) for t in w]
    Dict("m1" => count(z -> z.m1, steps), "m2" => count(z -> z.m2, steps), "m0" => count(z -> z.m0, steps),
         "patch" => count(z -> z.m1 || z.m2, steps), "none" => count(z -> !(z.m1 || z.m2 || z.m0), steps), "n" => length(steps),
         "rb_on" => count(z -> z.rb, steps), "rb_first" => steps[1].rb,
         "act_m0" => count(z -> z.act == "m0", steps), "act_patch" => count(z -> z.act in ("m1", "m2"), steps), "act_none" => count(z -> z.act == "none", steps),
         "acts" => [z.act for z in steps],
         "choice" => join(sort([n for n in ("m1", "m2") if any(z -> getfield(z, Symbol(n)), steps)]), ","))
end
function table(s, su)
    pc, w = su.choice_params, su.choice_window
    Dict(rbc => Dict(iv => (sil = Set{Int}(LC.unit(s.b, n) for n in names); Dict(pname(y) => probe(s, pc, y, w, sil, rbc) for y in TIES)) for (iv, names) in IVS) for rbc in RBC)
end

res = Dict{String,Any}("spec" => "discussion/specs/S38-rb-tiesource.md r1", "rule" => "rb", "seeds" => SEEDS, "H" => H,
                       "ties" => pname.(TIES), "interventions" => Dict(IVS), "rb_conditions" => collect(RBC), "runs" => Any[])
su = LBA.setup_with(H)
res["window"] = collect(su.choice_window)
for seed in SEEDS
    row = Dict{String,Any}("seed" => seed)
    for a in ("std", "swap")
        t = table(org(seed, su, Symbol(a)), su)
        row[a] = t
        row["repeat_equal_$a"] = table(org(seed, su, Symbol(a)), su) == t
    end
    push!(res["runs"], row)
    println("seed=$seed rep=$(row["repeat_equal_std"] && row["repeat_equal_swap"]) ",
            join(["$a/$rbc J0: " * join([row[a][rbc]["J0"][p]["choice"] == "" ? "." : row[a][rbc]["J0"][p]["choice"] for p in pname.(TIES)], "|") *
                  " m0 " * string(sum(row[a][rbc]["J0"][p]["m0"] for p in pname.(TIES))) for a in ("std", "swap") for rbc in RBC], "  "))
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-rb-tiesource.json"))
write(out, JSON.json(res, 2)); println("written ", out)
