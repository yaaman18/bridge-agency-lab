# S8 (spec discussion/specs/S8-body-tiesource.md r1): which receptor makes the tie acts. Interventions common to every arm,
# tie probes only, on the objects of S6 (seeds 21..30) and on new seeds 31..40. Writes experiments/results-tiesource.json.
# Predictions: predictions-tiesource.md (frozen before the first run). The probes are built as in tcommon.jl (S6).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const ASC = LBA.AS
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(21:40, ",")), ","))
const HS = parse.(Int, split(get(ENV, "HORIZONS", "294,392,588"), ","))
const S6 = JSON.parsefile(joinpath(LAB, "experiments", "results-tcommon.json"))
const TIES = [(1, 1), (2, 2), (3, 3), (4, 4), (5, 5)]
pname(y) = "$(y[1]),$(y[2])"
const IVS = [("J0", String[]), ("J3", ["r3"]), ("J4", ["r4"]), ("J5", ["r5"]), ("J6", ["r6"]), ("J12", ["r1", "r2"]), ("J56", ["r5", "r6"]),
             ("J125", ["r1", "r2", "r5"]), ("J126", ["r1", "r2", "r6"]), ("J1256", ["r1", "r2", "r5", "r6"])]

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
choice_str(s, pc, y, w, sil) = join(sort([s.names[m] for m in ASC.choice(s, pc, ASC.Schedule(pname(y), y, y, 20), w; silenced = sil)]), ",")
function table(s, su)
    pc, w = su.choice_params, su.choice_window
    Dict(iv => (sil = Set{Int}(LBA.LC.unit(s.b, n) for n in names); Dict(pname(y) => choice_str(s, pc, y, w, sil) for y in TIES)) for (iv, names) in IVS)
end

res = Dict{String,Any}("spec" => "discussion/specs/S8-body-tiesource.md r1", "rule" => "sf", "seeds" => SEEDS, "horizons" => HS,
                       "ties" => pname.(TIES), "interventions" => Dict(IVS), "runs" => Any[])
for H in HS
    su = LBA.setup_with(H)
    for seed in SEEDS
        row = Dict{String,Any}("H" => H, "seed" => seed)
        s6 = seed in 21:30 ? only(x for x in S6["runs"] if x["H"] == H && x["seed"] == seed) : nothing
        for a in ("std", "swap")
            t = table(org(seed, su, Symbol(a)), su)
            row[a] = t
            row["repeat_equal_$a"] = table(org(seed, su, Symbol(a)), su) == t
            s6 === nothing || (row["C0_matches_S6_$a"] = all(t["J0"][p] == s6[a]["I0"][p] && t["J12"][p] == s6[a]["I2"][p] for p in pname.(TIES)))
        end
        row["differ"] = Dict(iv => sort([p for p in pname.(TIES) if row["std"][iv][p] != row["swap"][iv][p]]) for (iv, _) in IVS)
        push!(res["runs"], row)
        println("H=$H seed=$seed C0=$(get(row, "C0_matches_S6_std", "-"))/$(get(row, "C0_matches_S6_swap", "-")) rep=$(row["repeat_equal_std"] && row["repeat_equal_swap"]) ",
                join(["$iv:" * join([row[a][iv][p] == "" ? "." : row[a][iv][p] for a in ("std", "swap") for p in pname.(TIES)], "|") for (iv, _) in IVS], " "))
    end
end
write(joinpath(LAB, "experiments", "results-tiesource.json"), JSON.json(res, 2))
println("written experiments/results-tiesource.json")
