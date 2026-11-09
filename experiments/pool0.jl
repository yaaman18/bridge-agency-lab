# S22 (spec discussion/specs/S22-body-pool0.md r1, gaps G17): the trial start pools [0,0] (default), [5U,5U], [50U,50U]
# (POOL0) on the same raised object; j3 (S19 three_at) per run, the cOff status of receptor->patch-motor edges, survival.
# Writes experiments/results-pool0.json. Predictions: predictions-pool0.md (frozen before the first run).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(181:220, ",")), ","))
const H = 392
const P0S = [("0,0", 0.0), ("5U,5U", 5.0), ("50U,50U", 50.0)]

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))
alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))
cstate(c) = Tuple(isdefined(c, f) ? deepcopy(getfield(c, f)) : nothing for f in fieldnames(typeof(c)))

"""Main run (habit3.jl's records) with the cOff status of the receptor->patch-motor edges."""
function main_run(s, p, sch, ks)
    st = AS.initial_state(s, p); S = s.side[st]; recs = Any[]; snaps = Dict{Int,Any}(); cur = Ref{Any}(nothing)
    init = Dict(k => (S.c.cOff !== nothing && !isnan(S.c.cOff[k])) for k in ks)
    first = Dict{Int,Any}(); tr = Any[]
    SINK[] = (st_, o, c, y) -> st_ === st && (cur[] = (acting = Set(o.acting), drove = copy(o.drove), conf = copy(o.confirmed_patch), sg_after = copy(c.sg)))
    for t in 1:H
        pre = (q = copy(S.c.q), sg = copy(S.c.sg), lastM = S.c.lastM === nothing ? nothing : copy(S.c.lastM), now = S.c.t + 1)
        cur[] = nothing
        AS.step!(st, s, p, sch, Set{Int}())
        push!(recs, cur[] === nothing ? nothing : merge(pre, cur[]))
        push!(tr, (cstate(S.c), copy(S.pool)))
        for k in ks
            (!init[k] && !haskey(first, k) && S.c.cOff !== nothing && !isnan(S.c.cOff[k])) && (first[k] = (t, S.c.cOff[k]))
        end
        alive(s, st) && t % 32 == 0 && t >= 64 && (snaps[t] = deepcopy((st, s.side[st])))
    end
    alive_end = alive(s, st)
    SINK[] = nothing; delete!(s.side, st)
    recs, snaps, init, first, alive_end, tr
end

"""(3) of S18 at t (sedfade_cause.jl three_at, unchanged)."""
function three_at(s, recs, snap, t)
    patch = [m for m in eachindex(s.names) if s.b.kind[m] == 'M' && s.b.patch[m] <= 2]
    win = recs[t-31:t]
    any(r -> r === nothing, win) && return nothing
    cnt = Dict(m => count(r -> m in r.acting, win) for m in patch)
    best = maximum(values(cnt)); ms = [m for m in patch if cnt[m] == best]
    (best == 0 || length(ms) > 1) && return nothing
    m = only(ms); st, S = snap
    E = [k for (k, (a, c, _)) in enumerate(s.edges) if c == m && s.b.kind[a] == 'R' && S.c.sg[k] >= 1]
    isempty(E) && return nothing
    noconf = all(r -> !any(k -> r.conf[k], E) && all(k -> r.q[k] == 0, E), win)
    actup = [r for r in win if m in r.acting]
    idle(r) = r.lastM !== nothing && r.now - r.lastM[m] > LC.FORGET
    viaE = all(r -> any(k -> r.drove[k] && r.q[k] == 0 && r.sg[k] >= 1, E) && !idle(r), actup)
    (noconf && length(actup) >= 16 && viaE) ? (m = m, E = E) : nothing
end

ename(s, k) = s.names[s.edges[k][1]] * "->" * s.names[s.edges[k][2]]
res = Dict{String,Any}("spec" => "discussion/specs/S22-body-pool0.md r1", "rule" => "sf", "seeds" => SEEDS, "H" => H, "P0" => [x[1] for x in P0S], "runs" => Any[])
su = LBA.setup_with(H); p = su.params
# control: POOL0 = [0,0] equals no POOL0 (every update's CState and pools) on the first object
let s = org(SEEDS[1], su, :std), sch = su.survival[1]
    ks = [k for (k, (a, c, _)) in enumerate(s.edges) if s.b.kind[a] == 'R' && s.b.kind[c] == 'M' && s.b.patch[c] <= 2]
    LBA.POOL0[] = nothing; a = main_run(s, p, sch, ks)[6]; LBA.POOL0[] = [0.0, 0.0]; b = main_run(s, p, sch, ks)[6]; LBA.POOL0[] = nothing
    res["control_pool0_default"] = isequal(a, b); println("control POOL0=[0,0] equals default: ", res["control_pool0_default"])
end
for seed in SEEDS, arm in (:std, :swap), sch in su.survival
    s = org(seed, su, arm)
    ks = [k for (k, (a, c, _)) in enumerate(s.edges) if s.b.kind[a] == 'R' && s.b.kind[c] == 'M' && s.b.patch[c] <= 2]
    row = Dict{String,Any}("seed" => seed, "arm" => String(arm), "schedule" => sch.name)
    for (name, v) in P0S
        LBA.POOL0[] = name == "0,0" ? nothing : [v * s.U, v * s.U]
        recs, snaps, init, first, alive_end, _ = main_run(s, p, sch, ks)
        pts = Any[]
        for t in 64:32:384
            haskey(snaps, t) || continue
            x = three_at(s, recs, snaps[t], t); x === nothing && continue
            push!(pts, Dict("t" => t, "m_star" => s.names[x.m], "E" => [ename(s, k) for k in x.E],
                            "E_cOff" => [init[k] ? "initially finite" : haskey(first, k) ? Dict("update" => first[k][1], "value" => first[k][2]) : "undefined to H" for k in x.E]))
        end
        row[name] = Dict("j3_points" => pts, "alive_end" => alive_end,
                         "cOff" => Dict(ename(s, k) => (init[k] ? "initially finite" : haskey(first, k) ? [first[k][1], first[k][2]] : "undefined to H") for k in ks))
    end
    LBA.POOL0[] = nothing
    push!(res["runs"], row)
    println("seed=$seed $arm $(rpad(sch.name, 11)) j3 points ", join(["$(n) $(length(row[n]["j3_points"]))" for (n, _) in P0S], " / "), "  alive ", join([row[n]["alive_end"] for (n, _) in P0S], "/"))
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-pool0.json"))
write(out, JSON.json(res, 2))
println("written ", out)
