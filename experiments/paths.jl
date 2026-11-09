# S10 (spec discussion/specs/S10-body-paths.md r2): cutting contingencies (q = sg = 0, one-shot or persistent).
# A: the sediment-only arms of S7 (seeds 35/37 :swap p2-high) and their :std arms. B: the r5 edges at the tie probes of S8.
# Writes experiments/results-paths.json. Predictions: predictions-paths.md (frozen before the first run).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const ASC = LBA.AS
const LAB = normpath(joinpath(@__DIR__, ".."))
const H = 392

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
edges_named(s, pairs) = [k for (k, (a, c, _)) in enumerate(s.edges) if (s.names[a], s.names[c]) in pairs]
edges_from(s, src) = [k for (k, (a, _, _)) in enumerate(s.edges) if s.names[a] == src]
function cut!(c, ks, what)
    for k in ks
        what in (:q, :qg) && (c.q[k] = 0)
        what in (:g, :qg) && (c.sg[k] = 0)
    end
end
body_alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))

# ---------------------------------------------------------------- A
function partA(su)
    p = su.params; sch = su.survival[2]; @assert sch.name == "p2-high"
    out = Any[]
    for seed in (35, 37), arm in (:swap, :std)
        s = org(seed, su, arm); st = AS.initial_state(s, p); snaps = Dict{Int,Any}()
        for t in 1:192
            AS.step!(st, s, p, sch, Set{Int}())
            t in (64, 192) && (snaps[t] = deepcopy((st, s.side[st])))
        end
        delete!(s.side, st)
        cuts = Dict("U" => Int[], "R" => edges_named(s, [("r2", "m2"), ("r8", "m2")]), "C" => edges_named(s, [("c2", "m2")]))
        cuts["RC"] = vcat(cuts["R"], cuts["C"])
        for t0 in (64, 192), (name, ks) in sort(collect(cuts)), mode in (:once, :persist)
            name == "U" && mode == :persist && continue
            b, S = deepcopy(snaps[t0]); s.side[b] = S
            q0 = [S.c.q[k] for k in ks]; g0 = [S.c.sg[k] for k in ks]
            cut!(S.c, ks, :qg)
            death = nothing; acts = Dict("m1" => 0, "m2" => 0)
            for τ in t0+1:t0+H
                AS.step!(b, s, p, sch, Set{Int}())
                for m in ("m1", "m2"); acts[m] += S.c.active[LC.unit(s.b, m)] && !b.dead; end
                mode == :persist && cut!(S.c, ks, :qg)
                death === nothing && !body_alive(s, b) && (death = τ)
            end
            push!(out, Dict("seed" => seed, "arm" => String(arm), "t0" => t0, "cut" => name, "mode" => String(mode), "edges" => [s.names[s.edges[k][1]] * "->" * s.names[s.edges[k][2]] for k in ks],
                            "q_before" => q0, "sg_before" => g0, "q_end" => [S.c.q[k] for k in ks], "sg_end" => [S.c.sg[k] for k in ks],
                            "death" => death, "alive_at_deadline" => death === nothing, "acts" => acts))
            delete!(s.side, b)
            x = out[end]; println("A seed=$seed $arm t0=$t0 $(rpad(name, 2)) $(rpad(String(mode), 7)) alive=$(x["alive_at_deadline"]) death=$death acts=$acts q/sg before $(q0)/$(g0)")
        end
    end
    out
end

# ---------------------------------------------------------------- B
"""AS.choice's definition (criteria.jl:16-19: the motors active after update t for t in the window), with a cut applied
before the first update (and, persistent, after each update). Also the number of (update, motor) acts in the window."""
function my_choice(s, pc, sch, window; ks = Int[], what = :none, persist = false)
    st = AS.initial_state(s, pc); S = s.side[st]
    what == :none || cut!(S.c, ks, what)
    chosen = Set{Int}(); n = 0
    for t in 1:maximum(window)
        AS.step!(st, s, pc, sch, Set{Int}())
        persist && what != :none && cut!(S.c, ks, what)
        if t in window
            for m in keys(s.motors); st.active[m] && (push!(chosen, m); n += 1); end
        end
    end
    delete!(s.side, st)
    join(sort([s.names[m] for m in chosen]), ","), n
end
const TIES = [(1, 1), (2, 2), (3, 3), (4, 4), (5, 5)]
pname(y) = "$(y[1]),$(y[2])"
function partB(su)
    pc, w = su.choice_params, su.choice_window
    S8 = JSON.parsefile(joinpath(LAB, "experiments", "results-tiesource.json"))
    pairs = [x for x in S8["runs"] if x["H"] == H && !isempty(x["differ"]["J0"])]
    out = Any[]; c0 = true
    for x in pairs
        seed = x["seed"]; row = Dict{String,Any}("seed" => seed, "differ_J0" => x["differ"]["J0"])
        tabs = Dict{String,Any}()
        for a in ("std", "swap")
            s = org(seed, su, Symbol(a)); ks = edges_from(s, "r5")
            t = Dict{String,Any}()
            for (lab, what, persist) in (("none", :none, false), ("Q_once", :q, false), ("G_once", :g, false), ("QG_once", :qg, false),
                                         ("Q_persist", :q, true), ("G_persist", :g, true), ("QG_persist", :qg, true))
                t[lab] = Dict(pname(y) => my_choice(s, pc, ASC.Schedule(pname(y), y, y, 20), w; ks, what, persist) for y in TIES)
            end
            for y in TIES   # C0: the own function equals AS.choice and S8's J0 without a cut
                ref = join(sort([s.names[m] for m in ASC.choice(s, pc, ASC.Schedule(pname(y), y, y, 20), w)]), ",")
                (t["none"][pname(y)][1] == ref && ref == x[a]["J0"][pname(y)]) || (c0 = false)
            end
            tabs[a] = t
            row["r5_edges_$a"] = Dict(s.names[s.edges[k][2]] => (q = s.raised.q[k], sg = s.raised.sg[k]) for k in ks)
        end
        for lab in keys(tabs["std"])
            d = [pname(y) for y in TIES if tabs["std"][lab][pname(y)][1] != tabs["swap"][lab][pname(y)][1]]
            acted = Dict(a => count(y -> tabs[a][lab][pname(y)][1] != "", TIES) for a in ("std", "swap"))
            nacts = Dict(a => sum(tabs[a][lab][pname(y)][2] for y in TIES) for a in ("std", "swap"))
            row[lab] = Dict("differ" => d, "tie_probes_acted" => acted, "acts" => nacts, "choices" => Dict(a => Dict(k => v[1] for (k, v) in tabs[a][lab]) for a in ("std", "swap")))
        end
        for lab in keys(tabs["std"]); lab == "none" && continue
            kept = all(a -> row[lab]["tie_probes_acted"][a] * 2 >= row["none"]["tie_probes_acted"][a], ("std", "swap"))
            row[lab]["verdict"] = !isempty(row[lab]["differ"]) ? "difference remains" : kept ? "gone with activity kept" : "gone with activity"
        end
        push!(out, row)
        println("B seed=$seed J0 differ $(row["differ_J0"]) ", join(["$lab:$(row[lab]["verdict"])" for lab in sort(collect(keys(tabs["std"]))) if lab != "none"], " "))
    end
    out, c0
end

su = LBA.setup_with(H)
A = partA(su)
B, c0 = partB(su)
res = Dict("spec" => "discussion/specs/S10-body-paths.md r2", "rule" => "sf", "H" => H, "A" => A, "B" => B, "C0_B" => c0)
write(joinpath(LAB, "experiments", "results-paths.json"), JSON.json(res, 2))
println("C0_B $c0; written experiments/results-paths.json")
