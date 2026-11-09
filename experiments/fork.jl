# S43 (spec discussion/specs/S43-rb-fork.md): the fork between death and release after the exchange Z on RB :swap (S42), and
# tests of the life/death judgment itself (user 2026-11-09). For each Z branch (as S42, L updates), a second branch NM from the
# same state with m* silenced (sil: m* has no outgoing edge, so sil only suppresses its act; it stays in the choice).
# Death tests: A1 the recount (dead set <=> no body site before the update), A2 absorption (no act, no circuit update, q only by
# B7, no undead), A3 controlled negative tests, A4 the protocol's survives on the main run.
# Writes experiments/results-rb-fork.json (OUT). Predictions: predictions-rb-fork-smoke.md (seed 1), predictions-rb-fork.md.
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(501:510, ",")), ",")))
const H = 392
const L = 160
const TPTS = 32:32:H
main_point(t) = t + L <= H

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
    contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = true, rest_body = :B)
swapped(sch) = AS.Schedule(sch.name * "-swap", reverse(sch.first), reverse(sch.second), sch.switch)
nsites(w) = count(!=(0), w.C)
deq(a, b) = typeof(a) == typeof(b) && (a isa AbstractArray ? (size(a) == size(b) && all(deq(x, y) for (x, y) in zip(a, b))) :
    (isstructtype(typeof(a)) && !(a isa Number || a isa AbstractString || a isa Symbol || a isa Tuple)) ? all(f -> deq(getfield(a, f), getfield(b, f)), fieldnames(typeof(a))) : isequal(a, b))
states_equal(A, B) = all(f -> deq(getfield(A[1], f), getfield(B[1], f)), fieldnames(typeof(A[1]))) && keys(A[2]) == keys(B[2]) && all(k -> deq(A[2][k], B[2][k]), keys(A[2]))

"""B7 (variant_horizon.jl:136–138): on a dead update t -> t+1, q drops by 1 (floor 0) when (t+1) % period == 0, else unchanged."""
q_b7_ok(q0, q1, t, period) = q1 == max.(q0 .- ((t + 1) % period == 0 ? 1 : 0), 0)
# codex I-R 2 #3: the computation of the flag checked on built values (not only the flag's corruption)
const Q_B7_UNIT = Dict("decay_update" => q_b7_ok([2, 0, 1], [1, 0, 0], 7, 8), "other_update" => q_b7_ok([2, 0, 1], [2, 0, 1], 6, 8),
                       "wrong_no_decay" => !q_b7_ok([2, 0, 1], [2, 0, 1], 7, 8), "wrong_decay_off_period" => !q_b7_ok([2, 0, 1], [1, 0, 0], 6, 8),
                       "wrong_below_zero" => !q_b7_ok([2, 0, 1], [1, -1, 0], 7, 8), "wrong_extra" => !q_b7_ok([2, 0, 1], [0, 0, 0], 7, 8))
# ---------------------------------------------------------------- one update with its record (hooks keyed on the watched state)
const POST = Ref{Any}(nothing); const WATCH = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (st === WATCH[] && (POST[] = (acting = copy(o.acting), choice = o.choice, answered = copy(o.answered), d = copy(o.d), y = copy(y))))
"""One update of (st, S) under org s; the record of the death judgment and of the act."""
function step_rec!(s, p, sch, st, S, sil)
    pre = (dead = st.dead, nb = nsites(S.w), Q = LBA.body_quantity(S.w), ct = S.c.t, q = copy(S.c.q), sg = copy(S.c.sg),
           lastM = S.c.lastM === nothing ? nothing : copy(S.c.lastM), pool = copy(S.pool), t = st.t)
    WATCH[] = st; POST[] = nothing
    AS.step!(st, s, p, sch, sil)
    WATCH[] = nothing
    o = POST[]
    nm(m) = s.b.names[m]
    (dead_pre = pre.dead, dead_post = st.dead, nb_pre = pre.nb, nb_post = nsites(S.w), Q_pre = pre.Q, ct_pre = pre.ct, ct_post = S.c.t,
     q_ok_dead = !pre.dead || q_b7_ok(pre.q, S.c.q, pre.t, p.decay_period),
     b7 = pre.dead && (pre.t + 1) % p.decay_period == 0, q_changed = S.c.q != pre.q,
     sg_same = S.c.sg == pre.sg, lastM_same = S.c.lastM == pre.lastM, active_off = !any(S.c.active),
     stepped = o !== nothing, act = o === nothing ? "dead" : isempty(o.acting) ? "none" : join(sort(nm.(o.acting)), ","),
     win = o === nothing || o.choice === nothing ? nothing : nm(o.choice.win),
     answered = o === nothing ? Dict{String,Bool}() : Dict(nm(m) => v for (m, v) in o.answered),
     d = o === nothing ? [0.0, 0.0] : o.d, pool_pre = pre.pool, lastM_pre = pre.lastM, now = pre.ct + 1, y = o === nothing ? nothing : o.y[1:2])
end

# ---------------------------------------------------------------- main run (snapshots at t and t + 1), A4 with the protocol
function main_run(s, p, sch)
    st = AS.initial_state(s, p); S = s.side[st]; snaps = Dict{Int,Any}(); nexts = Dict{Int,Any}(); recs = Any[]
    traj = [AS.State(copy(st.active), copy(st.strength), st.resource, st.t, st.dead)]
    for t in 1:H
        push!(recs, step_rec!(s, p, sch, st, S, Set{Int}()))
        push!(traj, AS.State(copy(st.active), copy(st.strength), st.resource, st.t, st.dead))
        (t - 1) in TPTS && haskey(snaps, t - 1) && (nexts[t - 1] = deepcopy((st, S)))
        !st.dead && t in TPTS && (snaps[t] = deepcopy((st, S)))
    end
    delete!(s.side, st)
    snaps, nexts, recs, traj
end
alive_window_ok(s, p, traj) = all(x -> any(u -> x.active[u] && !AS.is_sensor(s, u), 1:AS.nunits(s)), traj[(end - p.alive_window + 1):end])

"""A1, A2 over a sequence of update records."""
function death_checks(recs)
    live = [r for r in recs if !r.dead_pre]; dead = [r for r in recs if r.dead_pre]
    a1 = all(r -> r.dead_post == (r.nb_pre == 0), live)
    # the update where the world removed the last site, and the next update where dead is set
    vanish = [i for (i, r) in enumerate(recs) if !r.dead_pre && r.nb_pre > 0 && r.nb_post == 0]
    a1b = all(i -> i == length(recs) || (recs[i + 1].dead_post && !recs[i + 1].dead_pre), vanish)
    a2 = all(r -> r.dead_post && !r.stepped && r.act == "dead" && r.ct_post == r.ct_pre && r.q_ok_dead && r.sg_same && r.lastM_same && r.active_off, dead)
    (a1 = a1, a1_vanish_then_dead = a1b, a2 = a2, n_live = length(live), n_dead = length(dead),
     regrowth = count(r -> r.dead_pre && r.nb_post > 0, dead))
end

# ---------------------------------------------------------------- A3: controlled negative tests of the death judgment
function death_negtests(s, p, sch, snap, snap_next)
    out = Dict{String,Any}()
    # (a) every site emptied -> the next update is dead with no act
    st, S = deepcopy(snap); s.side[st] = S; S.w.C .= 0
    r = step_rec!(s, p, sch, st, S, Set{Int}()); delete!(s.side, st)
    out["a_all_sites_zero"] = r.dead_post && !r.stepped && r.act == "dead"
    # (b) one site with B below THETA_EXIST, no free matter (A = 0 everywhere, the other sites empty, pools 0): the first update
    # still sees a site (not dead) and the world removes it; the second is dead
    st, S = deepcopy(snap); s.side[st] = S; i = findfirst(!=(0), S.w.C)
    S.w.C .= 0; S.w.B .= 0.0; S.w.A .= 0.0; S.w.C[i] = 1; S.w.B[i] = 0.1; S.pool .= 0.0
    r1 = step_rec!(s, p, sch, st, S, Set{Int}()); r2 = step_rec!(s, p, sch, st, S, Set{Int}())
    # codex I-R 1 #2: 16 more updates after the death (two B7 periods), so that A2 is not empty
    after = [step_rec!(s, p, sch, st, S, Set{Int}()) for _ in 1:16]; delete!(s.side, st)
    out["b_first_alive"] = !r1.dead_post && r1.nb_pre == 1
    out["b_site_removed_by_world"] = r1.nb_post == 0
    out["b_second_dead"] = r2.dead_post && !r2.stepped
    dc = death_checks(vcat([r1, r2], after))
    out["b_after_death_A1_A2"] = dc.a1 && dc.a1_vanish_then_dead && dc.a2 && dc.n_dead == 16
    # B7 is exercised: two decay updates among the 16, q changed only on them (some q > 0 at the death)
    out["b_after_death_B7_exercised"] = count(r -> r.b7, after) == 2 && all(r -> r.q_changed == r.b7 || !r.q_changed, after) && any(r -> r.b7 && r.q_changed, after)
    # the checker itself must catch a wrong dead update (a clock advanced, a q changed, an act): each corruption must fail A2
    bad(f) = (rs = vcat([r1, r2], after); rs[5] = f(rs[5]); !death_checks(rs).a2)
    out["checker_catches_clock"] = bad(x -> merge(x, (ct_post = x.ct_post + 1,)))
    out["checker_catches_q"] = bad(x -> merge(x, (q_ok_dead = false,)))
    out["checker_catches_act"] = bad(x -> merge(x, (stepped = true, act = "m0")))
    out["checker_catches_undead"] = bad(x -> merge(x, (dead_post = false,)))
    # (c) a copy known to stay alive (the main run's next state was alive): one update gives exactly the recorded next state
    st, S = deepcopy(snap); s.side[st] = S
    r = step_rec!(s, p, sch, st, S, Set{Int}())
    out["c_alive_and_equal_to_the_run"] = !r.dead_post && states_equal((st, S), snap_next)
    delete!(s.side, st)
    out
end

# ---------------------------------------------------------------- one Z branch: actual (A) and m* silenced (NM), in lockstep
function fork(s, p, sch, snap, t)
    A = deepcopy(snap); s.side[A[1]] = A[2]
    N = deepcopy(snap); s.side[N[1]] = N[2]
    rA = Any[]; rN = Any[]; ms = nothing; silN = Set{Int}(); eq_upto = 0; first_act = nothing; diverged = false
    for k in 1:L
        a = step_rec!(s, p, sch, A[1], A[2], Set{Int}())
        if k == 1
            if a.act == "dead" || a.y[1] == a.y[2]
                delete!(s.side, A[1]); delete!(s.side, N[1])
                return Dict("t" => t, "mstar" => nothing, "outcome" => a.act == "dead" ? "dead at t+1" : "excluded (y1 == y2 at t+1)")
            end
            ms = a.y[1] > a.y[2] ? "m1" : "m2"; silN = Set([LC.unit(s.b, ms)])
        end
        n = step_rec!(s, p, sch, N[1], N[2], silN)
        push!(rA, a); push!(rN, n)
        first_act === nothing && a.act != "dead" && ms in split(a.act, ",") && (first_act = k)
        # the state of NM equals the actual one after every update before m*'s first act (codex V1 5, 7)
        if first_act === nothing && !diverged
            states_equal(A, N) ? (eq_upto = k) : (diverged = true)
        end
    end
    delete!(s.side, A[1]); delete!(s.side, N[1])
    dA = findfirst(r -> r.act == "dead", rA); dN = findfirst(r -> r.act == "dead", rN)
    lm = rA[1].lastM_pre[LC.unit(s.b, ms)]
    due = lm + LC.FORGET + 2 - rA[1].now
    other = ms == "m1" ? "m2" : "m1"
    stopN = dN === nothing ? L : dN - 1
    oth = [r for r in rN[1:stopN] if other in split(r.act, ",")]
    pk = other == "m1" ? 1 : 2
    w0 = snap[2].w
    Dict("t" => t, "mstar" => ms, "main_point" => main_point(t),
         "rest15" => all(r -> r.act != "dead" && !(ms in split(r.act, ",")), rA[1:15]),
         "outcome" => first_act !== nothing ? "release" : dA === nothing ? "lock" : "death",
         "first_act" => first_act, "dead_A" => dA, "dead_NM" => dN, "k_idle_due" => due,
         "eq_upto" => eq_upto, "diverged_before_first_act" => diverged,
         "eq_required" => first_act === nothing ? L : first_act - 1,
         "Q_t" => LBA.body_quantity(w0), "sites_t" => nsites(w0), "minB_t" => minimum(w0.B[i] for i in eachindex(w0.C) if w0.C[i] != 0),
         "other_NM" => Dict("acts" => length(oth), "answered" => count(r -> get(r.answered, other, false), oth),
                            "intake_offer" => sum(r -> r.d[pk], oth; init = 0.0)),
         "NM_after_due" => due <= L && (dN === nothing || dN > due) ? (r = rN[due]; Dict("win" => r.win, "act" => r.act)) : nothing,
         "checks_A" => Dict(pairs(death_checks(rA))), "checks_NM" => Dict(pairs(death_checks(rN))))
end

res = Dict{String,Any}("spec" => "discussion/specs/S43-rb-fork.md r2", "q_b7_unit" => Q_B7_UNIT, "rule" => "rb", "seeds" => SEEDS, "H" => H, "L" => L, "arm" => "swap", "runs" => Any[])
su = LBA.setup_with(H); p = su.params
for seed in SEEDS
    s = org(seed, su, :swap)
    for sch in su.survival
        snaps, nexts, recs, traj = main_run(s, p, sch)
        ours_dead = traj[end].dead; ours_window = alive_window_ok(s, p, traj)
        prot = AS.survives(s, p, sch)   # the protocol's judgment (AgencySubstrate criteria.jl:10) on the same org and schedule
        a4 = Dict("protocol_survives" => prot, "ours_dead_at_H" => ours_dead, "ours_window" => ours_window,
                  "ours_alive_as_protocol" => !ours_dead && ours_window)
        mc = death_checks(recs)
        # codex I-R 1 #1: every combination with a live branch point gets the negative tests (at its first point whose next state is alive)
        tl = sort([t for t in keys(snaps) if haskey(nexts, t) && !nexts[t][1].dead])
        tneg = isempty(tl) ? nothing : death_negtests(s, p, sch, snaps[tl[1]], nexts[tl[1]])   # none eligible: not verified (reported)
        evs = Any[]
        for t in sort(collect(keys(snaps)))
            Zs = deepcopy(snaps[t]); Zs[2].pool .= reverse(Zs[2].pool)   # Z as S39–S42
            push!(evs, fork(s, p, swapped(sch), Zs, t))
        end
        push!(res["runs"], Dict("seed" => seed, "schedule" => sch.name, "n_snaps" => length(snaps), "n_eligible_A3" => length(tl), "A4" => a4, "main_checks" => Dict(pairs(mc)), "negtests" => tneg, "events" => evs))
        println("seed=$seed $(rpad(sch.name, 11)) A4 $(a4) A1/A2 $(mc.a1)/$(mc.a2) neg $(tneg) ",
                join(["t$(e["t"]):$(e["outcome"])" * (e["mstar"] === nothing ? "" : "(dA $(e["dead_A"]) dNM $(e["dead_NM"]) due $(e["k_idle_due"]) Q $(round(e["Q_t"]; digits = 3)))") for e in evs], " "))
    end
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-rb-fork.json"))
write(out, JSON.json(res)); println("written ", out)
