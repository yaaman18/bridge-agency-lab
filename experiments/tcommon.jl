# S6 (spec discussion/specs/S6-body-tcommon.md r1): interventions common to every arm (I0 none, I1 r1..r6 silenced,
# I2 r1, r2 silenced) and tie / non-tie probes, on the objects of S4/S5 (RULE=sf, seeds 21..30, H 294/392/588, :std/:swap).
# Writes experiments/results-tcommon.json. Predictions: predictions-tcommon.md (frozen before the first run).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const ASC = LBA.AS
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(21:30, ",")), ","))
const HS = parse.(Int, split(get(ENV, "HORIZONS", "294,392,588"), ","))
const S5 = JSON.parsefile(joinpath(LAB, "experiments", "results-tcontent.json"))
const TIES = [(1, 1), (2, 2), (3, 3), (4, 4), (5, 5)]
const NONTIES = [(2, 1), (1, 2), (3, 1), (1, 3), (5, 3), (3, 5), (4, 2), (2, 4), (5, 1), (1, 5), (3, 2), (2, 3), (5, 4), (4, 5)]
const PROBES = vcat(TIES, NONTIES)
pname(y) = "$(y[1]),$(y[2])"
const S5NAMES = Dict("eq-high" => (4, 4), "eq-low" => (2, 2), "lo-1" => (2, 1), "lo-2" => (1, 2), "hi-1" => (3, 1), "hi-2" => (1, 3))
const INTERVENTIONS = [("I0", String[]), ("I1", ["r1", "r2", "r3", "r4", "r5", "r6"]), ("I2", ["r1", "r2"])]

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
with_raised(S, raised) = LBA.BodyOrg(S.names, S.edges, S.motors, S.b, raised, S.noise, S.structure, S.abundant_r0, S.U, S.MCOST,
                                     S.idle_first, S.contrast, S.core_gate, S.seen_both, S.sed_fade, S.grow, S.KC, S.PER, S.w0, S.pool0, IdDict())
choice_str(s, pc, y, w, sil) = join(sort([s.names[m] for m in ASC.choice(s, pc, ASC.Schedule(pname(y), y, y, 20), w; silenced = sil)]), ",")

"""Choices of one arm: intervention -> probe -> choice."""
function table(s, su)
    pc, w = su.choice_params, su.choice_window
    Dict(iv => (sil = Set{Int}(LBA.LC.unit(s.b, n) for n in names);
                Dict(pname(y) => choice_str(s, pc, y, w, sil) for y in PROBES)) for (iv, names) in INTERVENTIONS)
end
better(y) = y[1] > y[2] ? "m1" : "m2"

res = Dict{String,Any}("spec" => "discussion/specs/S6-body-tcommon.md r1", "rule" => "sf", "seeds" => SEEDS, "horizons" => HS,
                       "ties" => pname.(TIES), "nonties" => pname.(NONTIES), "interventions" => Dict(INTERVENTIONS), "runs" => Any[])
for H in HS
    su = LBA.setup_with(H)
    for seed in SEEDS
        row = Dict{String,Any}("H" => H, "seed" => seed)
        s5 = only(x for x in S5["runs"] if x["H"] == H && x["seed"] == seed)
        for a in ("std", "swap")
            t = table(org(seed, su, Symbol(a)), su)
            row[a] = t
            row["C0_repeat_equal_$a"] = table(org(seed, su, Symbol(a)), su) == t
            row["C0_matches_S5_$a"] = all(t["I0"][pname(y)] == s5[a]["probes"][n] for (n, y) in S5NAMES)
        end
        row["differ"] = Dict(iv => sort([p for p in pname.(PROBES) if row["std"][iv][p] != row["swap"][iv][p]]) for (iv, _) in INTERVENTIONS)
        row["nontie_better"] = Dict(a => Dict(iv => all(row[a][iv][pname(y)] == better(y) for y in NONTIES) for (iv, _) in INTERVENTIONS) for a in ("std", "swap"))
        push!(res["runs"], row)
        println("H=$H seed=$seed C0=$(row["C0_matches_S5_std"] && row["C0_matches_S5_swap"]) rep=$(row["C0_repeat_equal_std"] && row["C0_repeat_equal_swap"]) differ=$(row["differ"]) better=$(row["nontie_better"])")
    end
end

# negative controls (seed 24, H 392, :std, the T = {r2,r8} arm whose choice without its detector is m1; the short run showed that
# the :swap arm, whose choice without its detector is m2 already, cannot show the cut): (i) r8->m2 at q = sg = 0 must change the I0 choice on (4,5) or (1,2);
# (ii) an untouched copy equals in every table. They show the checks work, nothing more.
let su = LBA.setup_with(392), s = org(24, su, :std)
    base = table(s, su)
    r = deepcopy(s.raised)
    for (k, (a, c, _)) in enumerate(s.edges)
        (s.names[a], s.names[c]) == ("r8", "m2") && (r.q[k] = 0; r.sg[k] = 0)
    end
    cut = table(with_raised(s, r), su)
    clean = table(with_raised(s, deepcopy(s.raised)), su)
    det = cut["I0"]["4,5"] != base["I0"]["4,5"] || cut["I0"]["1,2"] != base["I0"]["1,2"]
    res["negative_control"] = Dict("seed" => 24, "H" => 392, "arm" => "std", "i_cut_detected" => det,
                                   "i_cut_I0" => cut["I0"], "ii_clean_equal" => clean == base)
    res["negative_control_detected"] = det && clean == base
    println("negative control ", res["negative_control_detected"], " cut (4,5)=", cut["I0"]["4,5"], " (1,2)=", cut["I0"]["1,2"])
end
write(joinpath(LAB, "experiments", "results-tcommon.json"), JSON.json(res, 2))
println("written experiments/results-tcommon.json")
