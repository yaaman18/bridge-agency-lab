# S14 (spec discussion/specs/S14-body-residual.md r1): move groups of the raised CState between the arms, one group or a pair
# of groups at a time, one-shot at the start of each tie probe, and compare the tie choices. Writes experiments/results-residual.json.
# Predictions: predictions-residual.md (only the controls). Exit 1 if a control fails or the frozen sha differs.
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const ASC = LBA.AS
const LAB = normpath(joinpath(@__DIR__, ".."))
const H = 392
const TIES = [(1, 1), (2, 2), (3, 3), (4, 4), (5, 5)]
pname(y) = "$(y[1]),$(y[2])"
org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
const GROUPS = [("q", [:q]), ("sg", [:sg]), ("h", [:h]), ("stats", [:cOn, :cOff]), ("lastM", [:lastM]), ("lastC", [:lastC]),
                ("activity", [:active, :prev, :off]), ("fresh", [:fresh]), ("pend", [:pend]), ("t", [:t])]
@assert sort(vcat([f for (_, fs) in GROUPS for f in fs])) == sort(collect(fieldnames(LC.CState)))   # every field once
with_raised(S, raised) = LBA.BodyOrg(S.names, S.edges, S.motors, S.b, raised, S.noise, S.structure, S.abundant_r0, S.U, S.MCOST,
                                     S.idle_first, S.contrast, S.core_gate, S.seen_both, S.sed_fade, S.grow, S.KC, S.PER, S.w0, S.pool0, IdDict())
function moved(to, from, fields)
    r = deepcopy(to.raised)
    for f in fields; setfield!(r, f, deepcopy(getfield(from.raised, f))); end
    in_range = all(x -> 0 <= x <= 4, vcat(r.q, r.sg, r.h))
    with_raised(to, r), in_range
end
choices(s, su) = Dict(pname(y) => join(sort([s.names[m] for m in ASC.choice(s, su.choice_params, ASC.Schedule(pname(y), y, y, 20), su.choice_window)]), ",") for y in TIES)
rng(r) = Tuple(getfield(r, f) for f in fieldnames(typeof(r)))

su = LBA.setup_with(H)
sha = split(read(joinpath(LAB, "experiments", "freeze-residual.txt"), String))[1]
sha_ok = sha == split(read(`shasum -a 256 $(joinpath(LAB, "experiments", "predictions-residual.md"))`, String))[1]
out = Any[]; ok = sha_ok
for (seed, role) in ((29, "residual"), (39, "residual"), (40, "residual"), (23, "comparison"), (24, "comparison"), (25, "comparison"))
    d, w = org(seed, su, :std), org(seed, su, :swap)
    tc1 = rng(d.noise) == rng(w.noise) && d.names == w.names && d.edges == w.edges && d.motors == w.motors && d.b.kind == w.b.kind
    cd, cw = choices(d, su), choices(w, su)
    differing = [String(f) for f in fieldnames(LC.CState) if !isequal(getfield(d.raised, f), getfield(w.raised, f))]
    groups = [(n, fs) for (n, fs) in GROUPS if any(f -> String(f) in differing, fs)]
    allf = [f for (_, fs) in GROUPS for f in fs]
    tc2 = choices(moved(d, w, allf)[1], su) == cw && choices(moved(w, d, allf)[1], su) == cd
    tc3 = choices(moved(d, d, Symbol[])[1], su) == cd && choices(moved(w, w, Symbol[])[1], su) == cw
    row = Dict{String,Any}("seed" => seed, "role" => role, "std" => cd, "swap" => cw, "differing_fields" => differing,
                           "TC1" => tc1, "TC2" => tc2, "TC3" => tc3, "single" => Any[], "pairs" => Any[])
    combos = vcat([[g] for g in groups], [[groups[i], groups[j]] for i in eachindex(groups) for j in i+1:length(groups)])
    for gs in combos
        fs = vcat([g[2] for g in gs]...); name = join([g[1] for g in gs], "+")
        sdw, okr1 = moved(d, w, fs); swd, okr2 = moved(w, d, fs)
        a, b = choices(sdw, su), choices(swd, su)
        push!(row[length(gs) == 1 ? "single" : "pairs"], Dict("groups" => name, "in_range" => okr1 && okr2,
              "std_given_swap" => a, "std_becomes_swap" => a == cw, "swap_given_std" => b, "swap_becomes_std" => b == cd))
    end
    push!(out, row); global ok = ok && tc1 && tc2 && tc3
    mv(k) = [x["groups"] for x in row[k] if x["std_becomes_swap"] || x["swap_becomes_std"]]
    println("seed=$seed $role TC $(tc1)/$(tc2)/$(tc3) differing $(differing) | single moving: $(mv("single")) | pairs moving: $(length(mv("pairs"))) $(first(mv("pairs"), 6))")
end
write(joinpath(LAB, "experiments", "results-residual.json"), JSON.json(Dict("spec" => "discussion/specs/S14-body-residual.md r1", "H" => H, "pairs" => out, "sha_ok" => sha_ok), 2))
println(ok ? "residual: controls ok" : "residual: a control FAILED (or sha)")
exit(ok ? 0 : 1)
