# S20b (spec discussion/specs/S20b-body-alpha-scan.md r1, gaps G4): the one-step alpha check of S12 Q-B (clamp.jl qb) with both
# pools scanned on {0..10}U x {0..10}U before t+1 (S20 r1 used the grid {0..6}U; the correspondence between the declared alpha and the implementation
# under input scanning). Writes experiments/results-alpha-scan.json.
# Pairs are assigned to the cell of B's second read (y_own_B, y_other_B). Predictions: predictions-alpha-scan.md (frozen before the first run).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(161:170, ",")), ","))
const H = 392
const RECEPTORS = ["r$i" for i in 1:8]
const COUPLED = ["r1", "r2", "r3", "r4", "r7", "r8"]
const DECLARED = Dict("m1" => Set(["r1", "r3", "r7", "r8"]), "m2" => Set(["r2", "r4", "r7", "r8"]))
const GRID = 0:10

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))
alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))
rngstate(r) = Tuple(getfield(r, f) for f in fieldnames(typeof(r)))

function main_run(s, p, sch)
    st = AS.initial_state(s, p); snaps = Dict{Int,Any}()
    for t in 1:H
        AS.step!(st, s, p, sch, Set{Int}())
        alive(s, st) && t % 32 == 0 && t >= 64 && (snaps[t] = deepcopy((st, s.side[st])))
    end
    delete!(s.side, st); snaps
end

"""Two updates from the snapshot at t; `pools` (pool of patch 1, pool of patch 2) set before t+1 or nothing; m silenced at t+1 if `silm`."""
function branch(s, p, sch, snap, t, pools, m, silm)
    st, S = deepcopy(snap); s.side[st] = S
    pools === nothing || (S.pool[1] = pools[1]; S.pool[2] = pools[2])
    rec = Any[]; after = Any[]; dead = false
    SINK[] = (st_, o, c, y) -> st_ === st && push!(rec, (motors = Set(o.acting), y = copy(y)))
    for τ in t+1:t+2
        k = length(rec)
        AS.step!(st, s, p, sch, (silm && τ == t + 1) ? Set([m]) : Set{Int}())
        length(rec) == k && push!(rec, (motors = Set{Int}(), y = nothing))
        alive(s, st) || (dead = true)
        push!(after, (recep = Dict(r => S.c.active[LC.unit(s.b, r)] for r in RECEPTORS), pool = copy(S.pool)))
    end
    out = (rec = rec, after = after, dead = dead, noise = rngstate(S.noise))
    SINK[] = nothing; delete!(s.side, st); out
end

"""One event: motor mname at t, pools by `cell` = (own, other) in U, or nothing for the natural state (clamp.jl qb's usable conditions)."""
function event(s, p, sch, snap, t, mname, cell)
    m = LC.unit(s.b, mname); pk = s.b.patch[m]
    pools = cell === nothing ? nothing : (v = zeros(2); v[pk] = cell[1] * s.U; v[3-pk] = cell[2] * s.U; v)
    C = branch(s, p, sch, snap, t, pools, m, false); B = branch(s, p, sch, snap, t, pools, m, true)
    (length(C.rec) == 2 && C.rec[2].y !== nothing && B.rec[2].y !== nothing && !C.dead && !B.dead) || return nothing
    m in C.rec[1].motors || return nothing
    setdiff(C.rec[1].motors, [m]) == setdiff(B.rec[1].motors, [m]) || return nothing
    C.after[1].pool[3-pk] == B.after[1].pool[3-pk] || return nothing
    C.noise == B.noise || return nothing
    diff = [r for r in RECEPTORS if C.after[2].recep[r] != B.after[2].recep[r]]
    pk2 = pk; yb = B.rec[2].y
    Dict("cell" => cell === nothing ? nothing : collect(cell), "bcell" => [Int(yb[pk2]), Int(yb[3-pk2])], "y1" => [C.rec[1].y, B.rec[1].y], "y2" => [C.rec[2].y, B.rec[2].y], "diff" => diff,
         "undeclared" => [r for r in diff if !(r in DECLARED[mname]) && r in COUPLED])
end

res = Dict{String,Any}("spec" => "discussion/specs/S20b-body-alpha-scan.md r1", "rule" => "sf", "seeds" => SEEDS, "H" => H, "grid" => collect(GRID), "runs" => Any[])
su = LBA.setup_with(H); p = su.params
todo = vec([(seed, arm, sch) for seed in SEEDS, arm in (:std, :swap), sch in su.survival])
for (seed, arm, sch) in todo
    t0 = time(); s = org(seed, su, arm); snaps = main_run(s, p, sch); ev = Any[]
    for t in sort(collect(keys(snaps))), mn in ("m1", "m2")
        for a in GRID, b in GRID
            e = event(s, p, sch, snaps[t], t, mn, (a, b)); e === nothing || push!(ev, merge(e, Dict("t" => t, "m" => mn, "natural" => false)))
        end
    end
    push!(res["runs"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "events" => ev))
    println("seed=$seed $arm $(rpad(sch.name, 11)) usable $(length(ev)) natural $(count(e -> e["natural"], ev)) with diff $(count(e -> !isempty(e["diff"]), ev)) undeclared $(count(e -> !isempty(e["undeclared"]), ev)) ($(round(time() - t0; digits = 1)) s)")
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-alpha-scan.json"))
write(out, JSON.json(res, 2))
println("written ", out)
