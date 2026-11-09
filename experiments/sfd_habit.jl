# S25 (a) (spec discussion/specs/S25-body-sfd.md r1): habit3.jl (S18) under COND=SF or SFD (sed_fade_drive in the raising and trials). S18: R3-b' of S16 with the raising history in (1) (the raising reproduced and
# checked against BodyOrg's raised state). Derived from habit2.jl (S16). S16: of D4's R3-b (E = receptor edges only; (2) silences E's source receptors).
# Derived from habit.jl (S13). D4's R3-b (the limited habit-evidence rule for sg-mediated patterns) on
# the SF version of BODY, three-valued, with the sg-necessity check G. Writes experiments/results-habit3.json.
# Predictions: predictions-habit3.md (frozen before the first run).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))
const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(251:290, ",")), ","))
const H = 392
const LONG = LC.FORGET * LC.P_SMAX   # 400
const COND = get(ENV, "COND", "SF"); COND in ("SF", "SFD") || error("COND")
LBA.SEDFADE_DRIVE[] = COND == "SFD"
const HOLDS, FAILS, UNDET = "holds", "fails", "undetermined"

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))
alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))
three(xs) = any(==(FAILS), xs) ? FAILS : all(==(HOLDS), xs) ? HOLDS : UNDET

"""Main run with per-update records: the state before the update (q, sg, lastM), and the update's acting units, drove,
confirmed_patch, and sg after."""
function main_run(s, p, sch)
    st = AS.initial_state(s, p); S = s.side[st]; recs = Any[]; snaps = Dict{Int,Any}(); cur = Ref{Any}(nothing)
    SINK[] = (st_, o, c, y) -> st_ === st && (cur[] = (acting = Set(o.acting), drove = copy(o.drove), conf = copy(o.confirmed_patch), sg_after = copy(c.sg)))
    for t in 1:H
        pre = (q = copy(S.c.q), sg = copy(S.c.sg), lastM = S.c.lastM === nothing ? nothing : copy(S.c.lastM), now = S.c.t + 1)   # the circuit's clock (it runs on from the raising)
        cur[] = nothing
        AS.step!(st, s, p, sch, Set{Int}())
        push!(recs, cur[] === nothing ? nothing : merge(pre, cur[]))
        alive(s, st) && t % 32 == 0 && t >= 64 && (snaps[t] = deepcopy((st, s.side[st])))
    end
    SINK[] = nothing; delete!(s.side, st)
    recs, snaps
end

"""A branch to t+n; `sil` from t+1; `zero_sg` edges kept at sg 0 (before the first update and after each). Records the
acts of motor m, the q/sg of E after t+32 and the first update when every sg of E is 0, death time, stale updates."""
function branch(s, p, sch, snap, t, n, sil, m, E; zero_sg = Int[])
    st, S = deepcopy(snap); s.side[st] = S
    ins = [k for (k, (_, c, _)) in enumerate(s.edges) if c == m]
    for k in zero_sg; S.c.sg[k] = 0; end
    acts = Ref(0); death = nothing; q32 = nothing; sg0 = nothing; stale = 0
    SINK[] = (st_, o, c, y) -> st_ === st && m in o.acting && (acts[] += 1)   # acts of m from step!'s acting (codex I-R S13 5)
    for τ in t+1:t+n
        all(k -> S.c.q[k] == 0 && S.c.sg[k] == 0, ins) && (stale += 1)
        AS.step!(st, s, p, sch, sil)
        for k in zero_sg; S.c.sg[k] = 0; end
        alive(s, st) || (death === nothing && (death = τ))
        τ == t + 32 && death === nothing && (q32 = [S.c.q[k] for k in E])
        sg0 === nothing && death === nothing && all(k -> S.c.sg[k] == 0, E) && (sg0 = τ)
    end
    endkept = death === nothing ? any(k -> S.c.q[k] >= 1 || S.c.sg[k] >= 1, E) : nothing
    SINK[] = nothing; delete!(s.side, st)
    (acts = acts[], death = death, q32 = q32, sg0 = sg0, endkept = endkept, stale = stale)
end

# the raising, reproduced with BodyOrg's arguments (variant_horizon.jl BodyOrg, the non-grow branch), with per-update records
const RAISE = Ref{Any}(nothing); const RAISE_OK = Ref(false)
function raise!(s, seed, cur)
    b = LC.newborn(false); c = LC.init(b); noise = LC.Mulberry(seed); rs = Any[]
    for y in LBA.curriculum(cur)
        pre = (q = copy(c.q), sg = copy(c.sg), lastM = c.lastM === nothing ? nothing : copy(c.lastM), now = c.t + 1)
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = noise, contrast = s.contrast, idle_first = s.idle_first, core_gate = s.core_gate, seen_both = s.seen_both, sed_fade = s.sed_fade, sed_fade_drive = LBA.SEDFADE_DRIVE[])
        push!(rs, merge(pre, (acting = Set(o.acting), drove = copy(o.drove), conf = copy(o.confirmed_patch), sg_after = copy(c.sg))))
    end
    same = b.edges == s.b.edges && all(f -> isequal(getfield(c, f), getfield(s.raised, f)), fieldnames(typeof(c))) &&
           all(f -> isequal(getfield(noise, f), getfield(s.noise, f)), fieldnames(typeof(noise)))
    RAISE[] = rs; RAISE_OK[] = same
    same
end

function judge(s, p, sch, recs, snap, t)
    patch = [m for m in eachindex(s.names) if s.b.kind[m] == 'M' && s.b.patch[m] <= 2]
    win = recs[t-31:t]
    any(r -> r === nothing, win) && return Dict("excluded" => "dead in the past window")
    cnt = Dict(m => count(r -> m in r.acting, win) for m in patch)
    best = maximum(values(cnt)); ms = [m for m in patch if cnt[m] == best]
    (best == 0 || length(ms) > 1) && return Dict("excluded" => "m* undetermined")
    m = only(ms); st, S = snap
    E = [k for (k, (a, c, _)) in enumerate(s.edges) if c == m && s.b.kind[a] == 'R' && S.c.sg[k] >= 1]   # receptor edges only (S16)
    isempty(E) && return Dict("excluded" => "E empty", "m_star" => s.names[m])
    # (1) a confirmation of an edge of E, with m acting, that raised its sg
    # (1) over the raising and the trial's 1..t (S18): the witness (phase, update, edge, sg before, sg after)
    wit1 = nothing
    for (ph, rs) in (("raising", RAISE[]), ("trial", recs[1:t])), (i, r) in enumerate(rs)
        r === nothing && continue
        m in r.acting || continue
        k = findfirst(k -> r.conf[k] && r.sg_after[k] > r.sg[k], E)
        k === nothing || (wit1 = (ph, i, s.names[s.edges[E[k]][1]] * "->" * s.names[s.edges[E[k]][2]], r.sg[E[k]], r.sg_after[E[k]]); break)
    end
    j1 = RAISE_OK[] ? (wit1 !== nothing ? HOLDS : FAILS) : UNDET
    # (3) the 32 updates t-31..t
    noconf = all(r -> !any(k -> r.conf[k], E) && all(k -> r.q[k] == 0, E), win)
    actup = [(i, r) for (i, r) in enumerate(win) if m in r.acting]
    idle(i, r) = r.lastM !== nothing && r.now - r.lastM[m] > LC.FORGET   # circuit time on both sides (fixed 2026-11-07)
    viaE = all(((i, r),) -> any(k -> r.drove[k] && r.q[k] == 0 && r.sg[k] >= 1, E) && !idle(i, r), actup)
    j3 = noconf && length(actup) >= 16 && viaE ? HOLDS : FAILS
    others_q = [any(k -> !(k in E) && s.edges[k][2] == m && r.drove[k] && r.q[k] >= 1, eachindex(s.edges)) for (i, r) in actup]   # per act update (codex I-R S13 4)
    # (2) X (m silenced) and N, to t+400
    srcs = Set(s.edges[k][1] for k in E)   # (2) silences the source receptors of E (S16)
    X = branch(s, p, sch, snap, t, LONG, srcs, m, E); N = branch(s, p, sch, snap, t, LONG, Set{Int}(), m, E)
    # each condition three-valued, then combined (a false condition makes (2) fail; codex I-R S13 2)
    xq = X.q32 === nothing ? UNDET : any(>(0), X.q32) ? FAILS : HOLDS
    xsg = X.sg0 !== nothing ? HOLDS : X.death === nothing ? FAILS : UNDET
    nk = N.endkept === nothing ? UNDET : N.endkept ? HOLDS : FAILS
    j2 = three([xq, xsg, nk])
    # G: sg of E kept at 0 for 32 updates
    G = branch(s, p, sch, snap, t, 32, Set{Int}(), m, E; zero_sg = E); N32 = branch(s, p, sch, snap, t, 32, Set{Int}(), m, E)
    g = N32.acts == 0 ? UNDET : (2 * G.acts >= N32.acts ? "sg necessity not supported" : "sg necessity supported")
    Dict("m_star" => s.names[m], "E" => [s.names[s.edges[k][1]] * "->" * s.names[s.edges[k][2]] for k in E], "q_E" => [S.c.q[k] for k in E], "sg_E" => [S.c.sg[k] for k in E],
         "j1" => j1, "j2" => j2, "j3" => j3, "R3b" => three([j1, j2, j3]), "others_q_drove_updates" => count(others_q), "others_q_drove_all" => !isempty(others_q) && all(others_q), "j2_parts" => [xq, xsg, nk], "acts_past" => length(actup),
         "X_q32" => X.q32, "X_sg0" => X.sg0, "N_sg0" => N.sg0,   # N_sg0 added after the result review (codex 3): first update with every sg of E at 0
         "X_death" => X.death, "N_death" => N.death, "N_endkept" => N.endkept,
         "j1_witness" => wit1 === nothing ? nothing : collect(wit1), "G" => g, "G_acts" => G.acts, "sources" => [s.names[u] for u in srcs], "t_minus_lastC" => S.c.lastC === nothing ? nothing : [S.c.t - S.c.lastC[k] for k in E], "N32_acts" => N32.acts, "G_stale" => G.stale)
end

res = Dict{String,Any}("spec" => "discussion/specs/S25-body-sfd.md r1", "cond" => COND, "rule" => "sf", "seeds" => SEEDS, "H" => H, "runs" => Any[], "named" => Any[])
su = LBA.setup_with(H); p = su.params
todo = Any[]; append!(todo, vec([(seed, arm, sch, nothing) for seed in SEEDS, arm in (:std, :swap), sch in su.survival]))

for (seed, arm, sch, only_t) in todo
    t0 = time(); s = org(seed, su, arm); rok = raise!(s, seed, arm); recs, snaps = main_run(s, p, sch)
    pts = Any[]
    for t in 64:32:384   # every candidate point, the dead ones kept with the reason (codex I-R S13 3)
        only_t === nothing || t == only_t || continue
        push!(pts, haskey(snaps, t) ? merge(Dict{String,Any}("t" => t), judge(s, p, sch, recs, snaps[t], t)) : Dict{String,Any}("t" => t, "excluded" => "body dead at t"))
    end
    push!(only_t === nothing ? res["runs"] : res["named"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "points" => pts, "raising_reproduced" => rok))
    c(v) = count(x -> get(x, "R3b", "") == v, pts)
    println("seed=$seed $arm $(rpad(sch.name, 11))$(only_t === nothing ? "" : " [named t=$only_t]") points $(length(pts)) excluded $(count(x -> haskey(x, "excluded"), pts)) R3b holds $(c(HOLDS)) fails $(c(FAILS)) undet $(c(UNDET)) ",
            "j3 holds $(count(x -> get(x, "j3", "") == HOLDS, pts)) ($(round(time() - t0; digits = 1)) s)")
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-sfd-habit-$(COND).json"))
write(out, JSON.json(res, 2))
println("written ", out)
