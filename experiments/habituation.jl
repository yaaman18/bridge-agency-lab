# S11 (spec discussion/specs/S11-body-habituation.md r1): move the habituation h of r5->m1, r5->m2 between the arms (or set it
# to 0) in the raised copy, one-shot or persistent, and compare the tie choices. Writes experiments/results-habituation.json.
# Predictions: predictions-habituation.md (frozen before the first run). The choice is the definition of S10 (paths.jl my_choice).
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
r5edges(s) = [k for (k, (a, c, _)) in enumerate(s.edges) if s.names[a] == "r5" && s.names[c] in ("m1", "m2")]
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))

"""S10's choice (AS.choice's definition) with h of the r5 edges set to `hv` before the first update (and after each update
if `persist`); `hv = nothing` changes nothing. Returns the choice, the acts in the window, and the window updates where an r5 edge drove."""
function my_choice(s, pc, sch, window; hv = nothing, persist = false)
    st = AS.initial_state(s, pc); S = s.side[st]; ks = r5edges(s)
    set!() = hv === nothing || (for (i, k) in enumerate(ks); S.c.h[k] = hv[i]; end)
    set!()
    chosen = Set{Int}(); n = 0; dr = Ref(0); t = Ref(0)
    SINK[] = (st_, o, c, y) -> st_ === st && t[] in window && any(o.drove[k] for k in ks) && (dr[] += 1)
    for u in 1:maximum(window)
        t[] = u
        AS.step!(st, s, pc, sch, Set{Int}())
        persist && set!()
        u in window && for m in keys(s.motors); st.active[m] && (push!(chosen, m); n += 1); end
    end
    SINK[] = nothing; delete!(s.side, st)
    (choice = join(sort([s.names[m] for m in chosen]), ","), acts = n, r5_drove = dr[])
end
table(s, su; kw...) = Dict(pname(y) => my_choice(s, su.choice_params, ASC.Schedule(pname(y), y, y, 20), su.choice_window; kw...) for y in TIES)
ch(t) = Dict(k => v.choice for (k, v) in t)

su = LBA.setup_with(H)
S8 = JSON.parsefile(joinpath(LAB, "experiments", "results-tiesource.json"))
pairs = [x["seed"] for x in S8["runs"] if x["H"] == H && !isempty(x["differ"]["J0"])]
out = Any[]; c0 = true
for seed in pairs
    sd, sw = org(seed, su, :std), org(seed, su, :swap)
    hd, hw = [sd.raised.h[k] for k in r5edges(sd)], [sw.raised.h[k] for k in r5edges(sw)]
    base_d, base_w = table(sd, su), table(sw, su)
    for y in TIES   # C0: equal to AS.choice
        for (s, t) in ((sd, base_d), (sw, base_w))
            t[pname(y)].choice == join(sort([s.names[m] for m in ASC.choice(s, su.choice_params, ASC.Schedule(pname(y), y, y, 20), su.choice_window)]), ",") || (global c0 = false)
        end
    end
    row = Dict{String,Any}("seed" => seed, "h_std" => hd, "h_swap" => hw, "none" => Dict("std" => ch(base_d), "swap" => ch(base_w)),
                           "r5_drove_none" => Dict("std" => sum(v.r5_drove for v in values(base_d)), "swap" => sum(v.r5_drove for v in values(base_w))))
    for persist in (false, true)
        tag = persist ? "persist" : "once"
        x1 = table(sd, su; hv = hw, persist); x2 = table(sw, su; hv = hd, persist)
        z0d = table(sd, su; hv = zero(hd), persist); z0w = table(sw, su; hv = zero(hw), persist)
        row["X1_$tag"] = Dict("choices" => ch(x1), "equals_swap" => ch(x1) == ch(base_w), "r5_drove" => sum(v.r5_drove for v in values(x1)))
        row["X2_$tag"] = Dict("choices" => ch(x2), "equals_std" => ch(x2) == ch(base_d), "r5_drove" => sum(v.r5_drove for v in values(x2)))
        row["X0_$tag"] = Dict("std" => ch(z0d), "swap" => ch(z0w), "difference_gone" => ch(z0d) == ch(z0w),
                              "tie_acted" => Dict("std" => count(v -> v.choice != "", values(z0d)), "swap" => count(v -> v.choice != "", values(z0w))))
    end
    push!(out, row)
    println("seed=$seed h std $hd swap $hw | X0p gone=$(row["X0_persist"]["difference_gone"]) X1p=swap $(row["X1_persist"]["equals_swap"]) X2p=std $(row["X2_persist"]["equals_std"]) | once: X0 $(row["X0_once"]["difference_gone"]) X1 $(row["X1_once"]["equals_swap"]) X2 $(row["X2_once"]["equals_std"])")
end
write(joinpath(LAB, "experiments", "results-habituation.json"), JSON.json(Dict("spec" => "discussion/specs/S11-body-habituation.md r1", "H" => H, "pairs" => out, "C0" => c0), 2))
println("C0 $c0; written experiments/results-habituation.json")
