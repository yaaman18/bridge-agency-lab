# S31 (spec discussion/specs/S31-body-blunt.md r2): the value-bluntness check R3-d, inherited from S12 Q-C (clamp.jl `qc`)
# with predictions. COND=SF (main) or SFD (separate auxiliary, SEDFADE_DRIVE on in raising and trials).
# Changes from S12 Q-C: no switch counts as latency Inf (not 15), and latN (first act of the hiZ patch motor in N) is recorded.
# Writes results-blunt-<cond>.json. Predictions: predictions-blunt.md (frozen before the first run).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

const COND = get(ENV, "COND", "SF")
COND in ("SF", "SFD") || error("COND is SF or SFD")
LBA.SEDFADE_DRIVE[] = COND == "SFD"
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(381:400, ",")), ","))
const H = 392
const ARMS = Symbol.(split(get(ENV, "ARMS", "std,swap"), ","))
const EXTRAS = get(ENV, "EXTRAS", "1") == "1"
const W = 15
const GSEED = parse(Int, get(ENV, "GSEED", "381"))   # the gate seed (smoke tests use a used seed)

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))
const CLAMPS = IdDict{Any,Any}()
LBA.CLAMP[] = (st, y) -> haskey(CLAMPS, st) ? CLAMPS[st](st, y) : (y, nothing)
alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))
swapped(sch) = AS.Schedule(sch.name * "-swap", reverse(sch.first), reverse(sch.second), sch.switch)
cstate(c) = Tuple(isdefined(c, f) ? deepcopy(getfield(c, f)) : nothing for f in fieldnames(typeof(c)))
rngstate(r) = Tuple(getfield(r, f) for f in fieldnames(typeof(r)))

function main_run(s, p, sch)
    st = AS.initial_state(s, p); snaps = Dict{Int,Any}()
    for t in 1:H
        AS.step!(st, s, p, sch, Set{Int}())
        alive(s, st) && t % 32 == 0 && (snaps[t] = deepcopy((st, s.side[st])))
    end
    delete!(s.side, st); snaps
end

"""As clamp.jl `branch` (without pool_set): a branch from the snapshot at t for n updates."""
function branch(s, p, sch, snap, t, n; swap_pool = false, yoke = nothing)
    st, S = deepcopy(snap); s.side[st] = S
    swap_pool && (S.pool .= reverse(S.pool))
    if yoke !== nothing
        sense, answer, yN = yoke
        CLAMPS[st] = (st_, y) -> (i = st_.t - t + 1; (sense ? yN[i] : y, answer ? yN[i] : y))
    end
    rec = Any[]; dead = false
    SINK[] = (st_, o, c, y) -> st_ === st && push!(rec, (acts = Set(s.b.patch[m] for m in o.acting if s.b.patch[m] <= 2), motors = Set(o.acting), y = copy(y), d = copy(o.d)))
    for τ in t+1:t+n
        k = length(rec)
        AS.step!(st, s, p, sch, Set{Int}())
        length(rec) == k && push!(rec, (acts = Set{Int}(), motors = Set{Int}(), y = nothing, d = nothing))
        alive(s, st) || (dead = true)
    end
    out = (rec = rec, dead = dead, cs = cstate(S.c), noise = rngstate(S.noise))
    SINK[] = nothing; delete!(CLAMPS, st); delete!(s.side, st)
    out
end

"""Q-C at t as clamp.jl `qc`, with latency Inf for no switch, latN, and the replay check (both channels yoked) when asked."""
function qc(s, p, sch, snap, t; replay = false)
    schZ = swapped(sch)
    N = branch(s, p, sch, snap, t, W)
    yN = [r.y for r in N.rec]
    rp = nothing   # C0 replay (codex I-R 4-5): every point where N lives through the window, before any early return
    if replay && !N.dead && all(y -> y !== nothing, yN)
        R = branch(s, p, schZ, snap, t, W; swap_pool = true, yoke = (true, true, yN))
        V0 = branch(s, p, schZ, snap, t, W; swap_pool = true, yoke = (true, false, yN))
        same(X) = [r.motors for r in X.rec] == [r.motors for r in N.rec] && isequal(X.cs, N.cs) && X.noise == N.noise
        rp = (identical = same(R), v_identical = same(V0))   # v_identical is the negative control: V should differ somewhere
    end
    tag(d) = (rp === nothing || (d["replay_identical"] = rp.identical; d["replay_v_identical"] = rp.v_identical); d)
    cnt = Dict(k => count(r -> k in r.acts, N.rec) for k in (1, 2))
    mstar = cnt[1] == cnt[2] ? nothing : (cnt[1] > cnt[2] ? 1 : 2)
    mstar === nothing && return tag(Dict{String,Any}("type" => "other", "why" => "tie or no acts"))
    g1, g2 = AS.yield_of(schZ, 1, t), AS.yield_of(schZ, 2, t)
    g1 == g2 && return tag(Dict{String,Any}("type" => "other", "why" => "Z schedule tie at t+1"))
    hiZ = g1 > g2 ? 1 : 2
    hiZ == mstar && return tag(Dict{String,Any}("type" => "excluded", "why" => "Z's high patch is m*'s"))
    st, S = snap; mu = LC.unit(s.b, "m$mstar")
    ks = [k for (k, (a, c, _)) in enumerate(s.edges) if c == mu && s.b.kind[a] == 'R']
    ty = any(k -> S.c.q[k] >= 1, ks) ? "q" : any(k -> S.c.sg[k] >= 1, ks) ? "sg" : "other"
    (N.dead || any(y -> y === nothing, yN)) && return tag(Dict{String,Any}("type" => ty, "why" => "N died"))
    V = branch(s, p, schZ, snap, t, W; swap_pool = true, yoke = (true, false, yN))
    out = tag(Dict{String,Any}("type" => ty, "m_star" => mstar, "hiZ" => hiZ))
    V.dead && (out["why"] = "V died"; return out)
    out["why"] = ""
    out["answer_d_differs"] = [r.d for r in V.rec] != [r.d for r in N.rec]
    out["answer_sign_differs"] = [r.d .> 0 for r in V.rec] != [r.d .> 0 for r in N.rec]
    lat = findfirst(r -> hiZ in r.acts, V.rec); latN = findfirst(r -> hiZ in r.acts, N.rec)
    out["switched"] = lat !== nothing
    out["latency"] = lat === nothing ? "Inf" : lat        # JSON has no Inf
    out["latN"] = latN === nothing ? "Inf" : latN
    out
end

function run_one(s, p, sch; replay = false)
    snaps = main_run(s, p, sch)
    [merge(Dict{String,Any}("t" => t), qc(s, p, sch, snaps[t], t; replay)) for t in sort(collect(keys(snaps)))]
end

res = Dict{String,Any}("spec" => "discussion/specs/S31-body-blunt.md r2", "cond" => COND, "rule" => COND == "SF" ? "sf" : "sf+sed_fade_drive",
                       "seeds" => SEEDS, "gseed" => GSEED, "H" => H, "W" => W, "arms" => String.(ARMS), "runs" => Any[])
su = LBA.setup_with(H); p = su.params
if EXTRAS   # C0 replay on seed 381 (all points, both arms, 4 schedules); C1 repeat; C2 the switch back to off equals SF
    rep = Bool[]; neg = Bool[]; npts = 0
    for arm in ARMS, sch in su.survival
        for e in run_one(org(GSEED, su, arm), p, sch; replay = true)
            global npts += 1
            haskey(e, "replay_identical") && (push!(rep, e["replay_identical"]); push!(neg, e["replay_v_identical"]))
        end
    end
    r1 = run_one(org(GSEED, su, :std), p, su.survival[1]); r2 = run_one(org(GSEED, su, :std), p, su.survival[1])
    c2 = nothing
    if COND == "SFD"
        LBA.SEDFADE_DRIVE[] = false; a = run_one(org(GSEED, su, :std), p, su.survival[1])
        LBA.SEDFADE_DRIVE[] = true; c2 = a   # compared with the SF file's C1 run by check_blunt.jl
    end
    res["controls"] = Dict("C0_points" => npts, "C0_replay_n" => length(rep), "C0_replay_all" => !isempty(rep) && all(rep),
                           "C0_negative_some_V_differs" => !isempty(neg) && !all(neg), "C1_repeat" => isequal(r1, r2))
    res["C1_run"] = r1
    c2 === nothing || (res["C2_off_run"] = c2)
    println("controls ", res["controls"])
end
for seed in SEEDS, arm in ARMS, sch in su.survival
    t0 = time(); ev = run_one(org(seed, su, arm), p, sch)
    push!(res["runs"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "events" => ev))
    ty = [e["type"] for e in ev]
    println("$COND seed=$seed $arm $(rpad(sch.name, 11)) q $(count(==("q"), ty)) sg $(count(==("sg"), ty)) ($(round(time() - t0; digits = 1)) s)")
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-blunt-$(lowercase(COND)).json"))
write(out, JSON.json(res, 2))
println("written ", out)
