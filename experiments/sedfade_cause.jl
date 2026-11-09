# S19 (spec discussion/specs/S19-body-sedfade-cause.md r1, gaps G3): at the points where (3) of S18 holds (the sediment-only
# type), branch N (no intervention) and F (sed_fade off from t+1, SEDFADE_OVERRIDE) to t+400 and compare the support of E.
# Derived from habit3.jl (S18). Writes experiments/results-sedfade-cause.json. Predictions: predictions-sedfade-cause.md (frozen).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(111:150, ",")), ","))
const H = 392
const LONG = LC.FORGET * LC.P_SMAX   # 400

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))
const OFF = IdDict{Any,Bool}()   # AS state -> sed_fade of that branch
LBA.SEDFADE_OVERRIDE[] = (st, sf) -> get(OFF, st, sf)
alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))
cstate(c) = Tuple(isdefined(c, f) ? deepcopy(getfield(c, f)) : nothing for f in fieldnames(typeof(c)))

"""Main run with per-update records as in habit3.jl (state before the update, acting, drove, confirmed_patch, sg after)."""
function main_run(s, p, sch; trace = false)
    st = AS.initial_state(s, p); S = s.side[st]; recs = Any[]; snaps = Dict{Int,Any}(); cur = Ref{Any}(nothing); tr = Any[]
    SINK[] = (st_, o, c, y) -> st_ === st && (cur[] = (acting = Set(o.acting), drove = copy(o.drove), conf = copy(o.confirmed_patch), sg_after = copy(c.sg)))
    for t in 1:H
        pre = (q = copy(S.c.q), sg = copy(S.c.sg), lastM = S.c.lastM === nothing ? nothing : copy(S.c.lastM), now = S.c.t + 1)
        cur[] = nothing
        AS.step!(st, s, p, sch, Set{Int}())
        push!(recs, cur[] === nothing ? nothing : merge(pre, cur[]))
        trace && push!(tr, (cstate(S.c), copy(S.pool), cur[] === nothing ? nothing : cur[].acting))
        alive(s, st) && t % 32 == 0 && t >= 64 && (snaps[t] = deepcopy((st, s.side[st])))
    end
    SINK[] = nothing; delete!(s.side, st)
    recs, snaps, tr
end

"""(3) of S18 at t (habit3.jl judge, the m*/E identification and j3 only)."""
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

"""A branch to t+n with sed_fade `sf`; per update the sg decreases of E classified by the rule's conditions; stops at death."""
function branch(s, p, sch, snap, t, n, m, E, sf; trace = false)
    st, S = deepcopy(snap); s.side[st] = S; OFF[st] = sf
    acts = 0; death = nothing; sg0 = nothing; decs = Any[]; cur = Ref{Any}(nothing); tr = Any[]
    nconf = 0; sgmin = [S.c.sg[k] for k in E]; sgmax = copy(sgmin)   # added after the I-R (codex 2, 6): every update's confirmations and sg range of E
    SINK[] = (st_, o, c, y) -> st_ === st && (cur[] = o)
    for τ in t+1:t+n
        q0 = copy(S.c.q); s0 = copy(S.c.sg); now = S.c.t + 1
        lc = S.c.lastC === nothing ? zeros(Int, length(S.c.q)) : copy(S.c.lastC)
        cur[] = nothing
        AS.step!(st, s, p, sch, Set{Int}())
        o = cur[]
        trace && push!(tr, (cstate(S.c), copy(S.pool)))
        if o !== nothing
            m in o.acting && (acts += 1)
            nconf += count(k -> o.confirmed_patch[k], E)
            for (i, k) in enumerate(E); sgmin[i] = min(sgmin[i], S.c.sg[k]); sgmax[i] = max(sgmax[i], S.c.sg[k]); end
            for k in E
                S.c.sg[k] < s0[k] || continue
                mk = s.edges[k][2]; a = now - lc[k]
                fade = sf && !o.confirmed_patch[k] && a >= LC.FORGET && a % LC.FORGET == 0
                weak = mk in o.acting && !get(o.answered, mk, true) && o.drove[k] && !o.confirmed_patch[k] && q0[k] == 0
                route = fade && weak ? "both" : fade ? "sed_fade" : weak ? "weaken" : "other"
                push!(decs, Dict("tau" => τ, "edge" => s.names[s.edges[k][1]] * "->" * s.names[mk], "before" => s0[k], "after" => S.c.sg[k], "route" => route))
            end
        end
        if !alive(s, st); death = τ; break; end
        sg0 === nothing && all(k -> S.c.sg[k] == 0, E) && (sg0 = τ)
    end
    sgkept = death === nothing ? any(k -> S.c.sg[k] >= 1, E) : nothing
    qkept = death === nothing ? any(k -> S.c.q[k] >= 1, E) : nothing
    SINK[] = nothing; delete!(OFF, st); delete!(s.side, st)
    (acts = acts, death = death, sg0 = sg0, sgkept = sgkept, qkept = qkept, decs = decs, tr = tr, nconf = nconf, sgmin = sgmin, sgmax = sgmax)
end

res = Dict{String,Any}("spec" => "discussion/specs/S19-body-sedfade-cause.md r1", "rule" => "sf", "seeds" => SEEDS, "H" => H, "runs" => Any[])
su = LBA.setup_with(H); p = su.params
# control: the override returning the object's own sed_fade equals no override (main run and an N branch, every update)
let s = org(SEEDS[1], su, :std), sch = su.survival[1]
    saved = LBA.SEDFADE_OVERRIDE[]; LBA.SEDFADE_OVERRIDE[] = nothing
    r0, sn0, tr0 = main_run(s, p, sch; trace = true)
    LBA.SEDFADE_OVERRIDE[] = saved
    r1, sn1, tr1 = main_run(s, p, sch; trace = true)
    tt = maximum(keys(sn1)); b1 = branch(s, p, sch, sn1[tt], tt, 64, 1, Int[], true; trace = true)
    LBA.SEDFADE_OVERRIDE[] = nothing; b0 = branch(s, p, sch, sn0[tt], tt, 64, 1, Int[], true; trace = true); LBA.SEDFADE_OVERRIDE[] = saved
    res["control_override_identity"] = isequal(tr0, tr1) && isequal(b0.tr, b1.tr)
    println("control override identity: ", res["control_override_identity"])
end
todo = vec([(seed, arm, sch) for seed in SEEDS, arm in (:std, :swap), sch in su.survival])
for (seed, arm, sch) in todo
    t0 = time(); s = org(seed, su, arm); recs, snaps, _ = main_run(s, p, sch); pts = Any[]
    for t in 64:32:384
        haskey(snaps, t) || continue
        x = three_at(s, recs, snaps[t], t); x === nothing && continue
        N = branch(s, p, sch, snaps[t], t, LONG, x.m, x.E, true); F = branch(s, p, sch, snaps[t], t, LONG, x.m, x.E, false)
        st, S = snaps[t]
        push!(pts, Dict("t" => t, "m_star" => s.names[x.m], "E" => [s.names[s.edges[k][1]] * "->" * s.names[s.edges[k][2]] for k in x.E],
                        "q_E" => [S.c.q[k] for k in x.E], "sg_E" => [S.c.sg[k] for k in x.E],
                        "N" => Dict(String(k) => getfield(N, k) for k in (:acts, :death, :sg0, :sgkept, :qkept, :decs, :nconf, :sgmin, :sgmax)),
                        "F" => Dict(String(k) => getfield(F, k) for k in (:acts, :death, :sg0, :sgkept, :qkept, :decs, :nconf, :sgmin, :sgmax))))
    end
    push!(res["runs"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "points" => pts))
    isempty(pts) || println("seed=$seed $arm $(rpad(sch.name, 11)) targets $(length(pts)) N sgkept $(count(x -> x["N"]["sgkept"] == true, pts)) F sgkept $(count(x -> x["F"]["sgkept"] == true, pts)) ($(round(time() - t0; digits = 1)) s)")
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-sedfade-cause.json"))
write(out, JSON.json(res, 2))
println("written ", out, "  targets ", sum(length(r["points"]) for r in res["runs"]))
