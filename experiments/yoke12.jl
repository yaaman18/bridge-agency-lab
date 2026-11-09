# S28 (spec discussion/specs/S28-body-yoke12.md r1, gaps G12, D3b DY2'): both channels yoked for W = 32 updates to Y0 (own N),
# Y1 (the provider's N: the next seed of the group, same arm, schedule, t) or Y2 (own N reversed in time); real pools; then real
# input to t + H. Writes experiments/results-yoke12.json. Predictions: predictions-yoke12.md (frozen before the first run).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(331:340, ",")), ","))
const H = 392; const W = 32; const TS = 64:32:352
org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))
const CLAMPS = IdDict{Any,Any}()
LBA.CLAMP[] = (st, y) -> haskey(CLAMPS, st) ? CLAMPS[st](st, y) : (y, nothing)
alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))
nbody(s, st) = length(LBA.body_sites(s.side[st].w))
cstate(c) = Tuple(isdefined(c, f) ? deepcopy(getfield(c, f)) : nothing for f in fieldnames(typeof(c)))

function main_run(s, p, sch)
    st = AS.initial_state(s, p); snaps = Dict{Int,Any}()
    for t in 1:H
        AS.step!(st, s, p, sch, Set{Int}())
        alive(s, st) && t in TS && (snaps[t] = deepcopy((st, s.side[st])))
    end
    delete!(s.side, st); snaps
end

"""From the snapshot at t to t + H; `seq` (length W) yokes both channels at t+1..t+W, or nothing. Records in W: patch acts, y read, CState."""
function branch(s, p, sch, snap, t, seq)
    st, S = deepcopy(snap); s.side[st] = S
    seq === nothing || (CLAMPS[st] = (st_, y) -> (i = st_.t - t + 1; 1 <= i <= W ? (seq[i], seq[i]) : (y, nothing)))
    acts = Any[]; ys = Any[]; cs = Any[]; cur = Ref{Any}(nothing); deadW = false; bodyW = nothing
    SINK[] = (st_, o, c, y) -> st_ === st && (cur[] = (Set(s.b.patch[m] for m in o.acting if s.b.patch[m] <= 2), copy(y)))
    for τ in t+1:t+H
        cur[] = nothing
        AS.step!(st, s, p, sch, Set{Int}())
        if τ <= t + W
            push!(acts, cur[] === nothing ? nothing : cur[][1]); push!(ys, cur[] === nothing ? nothing : cur[][2]); push!(cs, cstate(S.c))
            alive(s, st) || (deadW = true)
            τ == t + W && (bodyW = alive(s, st) ? nbody(s, st) : 0)
        end
    end
    aliveH = alive(s, st)
    SINK[] = nothing; delete!(CLAMPS, st); delete!(s.side, st)
    (acts = acts, ys = ys, cs = cs, deadW = deadW, bodyW = bodyW, aliveH = aliveH)
end

su = LBA.setup_with(H); p = su.params
keys_ = [(seed, arm, i) for seed in SEEDS, arm in (:std, :swap), i in eachindex(su.survival)]
orgs = Dict(); snapsD = Dict(); Ns = Dict()
for (seed, arm, i) in keys_
    s = org(seed, su, arm); orgs[(seed, arm, i)] = s; sch = su.survival[i]
    snapsD[(seed, arm, i)] = main_run(s, p, sch)
    for (t, sn) in snapsD[(seed, arm, i)]; Ns[(seed, arm, i, t)] = branch(s, p, sch, sn, t, nothing); end
end
nxt(seed) = SEEDS[mod1(findfirst(==(seed), SEEDS) + 1, length(SEEDS))]
res = Dict{String,Any}("spec" => "discussion/specs/S28-body-yoke12.md r1", "seeds" => SEEDS, "W" => W, "H" => H, "points" => Any[])
for (seed, arm, i) in keys_, t in TS
    s = orgs[(seed, arm, i)]; sch = su.survival[i]
    pt = Dict{String,Any}("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "t" => t)
    if !haskey(snapsD[(seed, arm, i)], t); pt["excluded"] = "dead at t"; push!(res["points"], pt); continue; end
    N = Ns[(seed, arm, i, t)]
    if N.deadW || any(isnothing, N.ys); pt["excluded"] = "N died in W"; push!(res["points"], pt); continue; end
    sn = snapsD[(seed, arm, i)][t]
    Y0 = branch(s, p, sch, sn, t, N.ys)
    pt["C0"] = isequal(Y0.acts, N.acts) && isequal(Y0.cs, N.cs)
    pt["N"] = Dict("bodyW" => N.bodyW, "aliveH" => N.aliveH)
    div(B) = count(j -> B.acts[j] != N.acts[j], 1:W)
    pv = (nxt(seed), arm, i, t)
    if !haskey(Ns, pv) || Ns[pv].deadW || any(isnothing, Ns[pv].ys)
        pt["Y1"] = Dict("excluded" => "provider dead at t or in W", "provider" => nxt(seed))
    else
        B = branch(s, p, sch, sn, t, Ns[pv].ys)
        pt["Y1"] = Dict("provider" => nxt(seed), "same_seq_as_N" => isequal(Ns[pv].ys, N.ys), "div" => div(B), "deadW" => B.deadW, "bodyW" => B.bodyW, "aliveH" => B.aliveH)
    end
    rv = reverse(N.ys)
    if isequal(rv, N.ys)
        pt["Y2"] = Dict("excluded" => "reversed sequence equals N's")
    else
        B = branch(s, p, sch, sn, t, rv)
        pt["Y2"] = Dict("div" => div(B), "deadW" => B.deadW, "bodyW" => B.bodyW, "aliveH" => B.aliveH)
    end
    push!(res["points"], pt)
end
write(joinpath(LAB, "experiments", "results-yoke12.json"), JSON.json(res, 2))
println("points ", length(res["points"]), " C0 all ", all(x -> get(x, "C0", true), res["points"]))
