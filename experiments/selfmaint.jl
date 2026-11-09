# S7 (spec discussion/specs/S7-body-selfmaint.md r1): D2's rule T ((a)(a')(b)(c)), T+ and T_core on the SF version of BODY,
# three-valued (holds / fails / undetermined). Writes experiments/results-selfmaint.json and formal/gen/WindowsBody.lean.
# Predictions: predictions-selfmaint.md (frozen before the first run, freeze-selfmaint.txt).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(31:40, ",")), ","))
const HS = parse.(Int, split(get(ENV, "HORIZONS", "294,392,588"), ","))
const ARMS = Symbol.(split(get(ENV, "ARMS", "std,swap"), ","))
const SCHEDS = split(get(ENV, "SCHEDULES", ""), ",", keepempty = false)
const HOLDS, FAILS, UNDET = "holds", "fails", "undetermined"
const LABSCHED = get(ENV, "LABSCHED", "") == "mid"   # S29 (G18 b): the lab schedules of S23 instead of the frozen survival schedules
const MIDS = [AS.Schedule("mid-32", (3, 2), (3, 2), 20), AS.Schedule("mid-23", (2, 3), (2, 3), 20), AS.Schedule("mid-32to23", (3, 2), (2, 3), 20), AS.Schedule("mid-41to14", (4, 1), (1, 4), 20)]

const GROWV = get(ENV, "GROWV", "0") == "1"   # S29 (G18): the G version (item 81), default off
const RBV = get(ENV, "RBV", "0") == "1"       # S37 (notes/RB-redo.md): RB = SF + rest (m0) + rest_body :B (rb) + α, default off
org(seed, su, cur) = RBV ?
    LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = true, rest_body = :B) : GROWV ?
    LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                contrast = :bin3, core_gate = true, sed_fade = true, grow = true, KC = 0.002) :
    LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))
alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))
kappa_empty(s, c) = !any(k -> c.q[k] >= 1 && s.b.kind[s.b.edges[k][1]] != 'R', eachindex(c.q))
# S37 H2 (notes/RB-redo.md §2, formal LSH2): κ_prec = the κ edges that are not exempt from the decay (α exempts an edge into
# a patch-4 motor with q0 > 0, core/circuit.jl:289): the precarious ones, which can be lost
exempt(b, k) = b.patch[b.edges[k][2]] == 4 && b.q0[k] > 0
kpatch(s) = [k for k in eachindex(s.b.edges) if s.b.kind[s.b.edges[k][1]] != 'R' && !exempt(s.b, k)]
kpatch_empty(s, c) = !any(k -> c.q[k] >= 1, kpatch(s))
const M0 = Ref{Any}(nothing)
three(xs) = any(==(FAILS), xs) ? FAILS : all(==(HOLDS), xs) ? HOLDS : UNDET

"""The main run: H updates without intervention. Returns the DC records (one per living update), the external flags,
the alive-after-update flags, and the snapshots at the branch points E."""
function main_run(s, p, sch, H)
    st = AS.initial_state(s, p)
    recs = LC.DCStep[]; ext = Bool[]; alive_after = Bool[]; snaps = Dict{Int,Any}()
    acts = Dict("m0" => 0, "patch" => 0, "none" => 0)   # S37: the act of each living update (same denominator)
    SINK[] = (st_, o, c, y) -> st_ === st && (push!(recs, LC.dc_record(s.b, o, c; partner_live = false, y = y, phase = "world")); push!(ext, false);
        a = [s.b.patch[m] for m in o.acting]; acts[isempty(a) ? "none" : any(==(4), a) ? "m0" : "patch"] += 1)
    for t in 1:H
        AS.step!(st, s, p, sch, Set{Int}())
        push!(alive_after, alive(s, st))
        alive_after[t] && t % 32 == 0 && (snaps[t] = deepcopy((st, s.side[st])))
    end
    SINK[] = nothing; delete!(s.side, st)
    M0[] = acts
    recs, ext, alive_after, snaps
end

"""One branch from the snapshot at t to the absolute time t+H with `sil` from t+1: death time, confirmations, and
whether kappa was empty or the body dead after some update t+1..t+32."""
function branch(s, p, sch, snap, t, H, sil)
    st, S = deepcopy(snap); s.side[st] = S
    nconf = Ref(0); death = nothing; b1 = false; b1p = false; kp_inc = false; kappa_ever_empty = false; m0acts = Ref(0); alive32 = true
    kp = kpatch(s); qprev = S.c.q[kp]; any(qprev .> LC.P_SMAX) && (kp_inc = true)
    SINK[] = (st_, o, c, y) -> st_ === st && ((any(o.confirmed_patch) || !isempty(o.call_confirmed)) && (nconf[] += 1); any(m -> s.b.patch[m] == 4, o.acting) && (m0acts[] += 1))
    for τ in t+1:t+H
        AS.step!(st, s, p, sch, sil)
        dead = isempty(LBA.body_sites(S.w))
        dead && death === nothing && (death = τ)
        τ <= t + 32 && (dead || kappa_empty(s, S.c)) && (b1 = true)
        τ <= t + 32 && (dead || kpatch_empty(s, S.c)) && (b1p = true)           # S37 H2
        τ <= t + 32 && dead && (alive32 = false)
        # S37 (codex I-R 4): the LSH2 map, checked update by update on κ_prec: q ≤ 4 and q_new ≤ decay(now, q_old) with now = the
        # circuit's clock after the update (core/circuit.jl:289 decays at now % 8 == 0); any breach refutes the map (b1p undetermined)
        dead || (q = S.c.q[kp]; now = S.c.t; bound = now % LC.P_DECAY == 0 ? max.(qprev .- 1, 0) : qprev;
                 (any(q .> bound) || any(q .> LC.P_SMAX)) && (kp_inc = true); qprev = q)
        dead || kappa_empty(s, S.c) && (kappa_ever_empty = true)
    end
    SINK[] = nothing; delete!(s.side, st)
    (death = death, alive_at_deadline = death === nothing, confirmations = nconf[], b1_hit = b1, b1p_hit = b1p, kp_inc = kp_inc,
     kappa_ever_empty = kappa_ever_empty, m0acts = m0acts[], alive32 = alive32)
end

"""(a) at event t (window of the 32 records ending at t; records index = update index while alive)."""
function judge_a(s, recs, ext, t)
    t < LC.DC_L && return (v = UNDET, clauses = nothing)
    any(ext[t-LC.DC_L+1:t]) && return (v = UNDET, clauses = nothing)
    c = LC.check_dc(s.b, LC.dc_window(s.b, @view recs[t-LC.DC_L+1:t]))
    (v = c.dc ? HOLDS : FAILS, clauses = c)
end
# S37 H3 (notes/RB-redo.md §2): (a) with the window's kept restricted to the precarious edges (exempt edges are given by the
# rule, never produced; with them kept, hSelf is false on every window, formal Window.no_self_of_unreproduced)
prec_window(b, w) = LC.DCWindow((f == :kept ? [w.kept[k] && !exempt(b, k) for k in eachindex(w.kept)] : getfield(w, f) for f in fieldnames(LC.DCWindow))...)
function judge_a_prec(s, recs, ext, t)
    t < LC.DC_L && return (v = UNDET, clauses = nothing)
    any(ext[t-LC.DC_L+1:t]) && return (v = UNDET, clauses = nothing)
    c = LC.check_dc(s.b, prec_window(s.b, LC.dc_window(s.b, @view recs[t-LC.DC_L+1:t])))
    (v = c.dc ? HOLDS : FAILS, clauses = c)
end
judge_b1(x) = x.confirmations > 0 ? UNDET : x.b1_hit ? HOLDS : UNDET
judge_b2(n, x) = n.alive_at_deadline && !x.alive_at_deadline ? HOLDS : FAILS

function run_one(s, p, sch, H)
    recs, ext, alive_after, snaps = main_run(s, p, sch, H)
    nalive = length(recs)
    a_at = Dict(t => judge_a(s, recs, ext, t) for t in LC.DC_L:H if t <= nalive && alive_after[t])
    ap_at = RBV ? Dict(t => judge_a_prec(s, recs, ext, t) for t in keys(a_at)) : nothing
    events = Any[]
    X = Set(LC.unit(s.b, n) for n in ("m1", "m2")); Y = Set(LC.unit(s.b, n) for n in ("c1", "c2"))
    for t in sort(collect(keys(snaps)))
        n = branch(s, p, sch, snaps[t], t, H, Set{Int}()); x = branch(s, p, sch, snaps[t], t, H, X); y = branch(s, p, sch, snaps[t], t, H, Y)
        a = a_at[t].v; b1 = judge_b1(x); b2 = judge_b2(n, x); b3 = judge_b2(n, y)
        T = three([a, HOLDS, b1, b2, HOLDS])   # (a), (a') clean by construction (checked in judge_a), (b1), (b2), (c) by rule
        Tc = three([T, b3])
        t1 = nothing
        if T == HOLDS
            t1 = t
            while t1 + 1 <= H && haskey(a_at, t1 + 1) && a_at[t1 + 1].v == HOLDS; t1 += 1; end
        end
        cl = a_at[t].clauses
        push!(events, Dict("t" => t, "a" => a, "clauses" => cl === nothing ? nothing : Dict(string(k) => getfield(cl, k) for k in keys(cl)),
            "b1" => b1, "b2" => b2, "b3" => b3, "T" => T, "T_core" => Tc, "Tplus_t1" => t1,
            "death_N" => n.death, "death_X" => x.death, "death_Y" => y.death, "conf_X" => x.confirmations, "conf_Y" => y.confirmations, "conf_N" => n.confirmations,
            # S37 (RB): H2 judged like (b1) with κ_patch; T_H2 = T with (b1) replaced by it (a separate proposition, not T)
            # codex I-R 3: alive through t+32 with κ_prec never empty is H2's refutation -> fails (not undetermined)
            "b1p" => (x.confirmations > 0 || x.kp_inc) ? UNDET : x.b1p_hit ? HOLDS : x.alive32 ? FAILS : UNDET, "kp_inc_X" => x.kp_inc,
            "kappa_ever_empty_X" => x.kappa_ever_empty, "m0acts_X" => x.m0acts, "m0acts_Y" => y.m0acts, "m0acts_N" => n.m0acts))
        ev = events[end]; ev["T_H2"] = three([a, HOLDS, ev["b1p"], b2, HOLDS])
        if RBV   # S37: T_prec = (a) on κ_prec, (b1) on κ_prec, (b2), (c); T_prec_core adds (b3)
            ap = ap_at[t]; ev["a_prec"] = ap.v; ev["clauses_prec"] = ap.clauses === nothing ? nothing : Dict(string(k) => getfield(ap.clauses, k) for k in keys(ap.clauses))
            ev["T_prec"] = three([ap.v, HOLDS, ev["b1p"], b2, HOLDS]); ev["T_prec_core"] = three([ev["T_prec"], b3])
        end
    end
    (events = events, dc_rate = isempty(a_at) ? nothing : count(v -> v.v == HOLDS, values(a_at)) / length(a_at),
     dcp_rate = (ap_at === nothing || isempty(ap_at)) ? nothing : count(v -> v.v == HOLDS, values(ap_at)) / length(ap_at),
     alive_at_H = alive_after[H], death_main = findfirst(!, alive_after), recs = recs, a_at = a_at, acts = M0[], ap_at = ap_at)
end

# ---------------------------------------------------------------- runs
res = Dict{String,Any}("spec" => RBV ? "discussion/specs/S37-rb-selfmaint.md r1" : "discussion/specs/S7-body-selfmaint.md r1", "rule" => RBV ? "rb" : "sf", "seeds" => SEEDS, "horizons" => HS,
                       "arms" => String.(ARMS), "runs" => Any[])
samples = Dict{Tuple{Symbol,Bool},Vector{Any}}()   # (clause, value) -> windows for Lean
B0 = Ref{Any}(nothing)
for H in HS
    su = LBA.setup_with(H); p = su.params
    for seed in SEEDS, arm in ARMS
        s = org(seed, su, arm)
        B0[] === nothing && (B0[] = s.b)
        @assert s.b.edges == B0[].edges && s.b.kind == B0[].kind
        for sch in (LABSCHED ? MIDS : su.survival)
            isempty(SCHEDS) || sch.name in SCHEDS || continue
            t0 = time(); r = run_one(s, p, sch, H)
            for (t, v) in r.a_at
                v.clauses === nothing && continue
                for f in (:self, :smc, :act, :bound, :dc)
                    l = get!(samples, (f, getfield(v.clauses, f)), Any[])
                    length(l) < 2 && push!(l, (LC.dc_window(s.b, @view r.recs[t-LC.DC_L+1:t]), v.clauses))
                end
            end
            RBV && for (t, v) in r.ap_at   # S37: the κ_prec windows too, each clause true and false where seen
                v.clauses === nothing && continue
                for f in (:self, :smc, :act, :bound, :dc)
                    l = get!(samples, (Symbol("prec_", f), getfield(v.clauses, f)), Any[])
                    length(l) < 2 && push!(l, (prec_window(s.b, LC.dc_window(s.b, @view r.recs[t-LC.DC_L+1:t])), v.clauses))
                end
            end
            push!(res["runs"], Dict("H" => H, "seed" => seed, "arm" => String(arm), "schedule" => sch.name, "events" => r.events,
                                    "dc_rate_all_events" => r.dc_rate, "alive_at_H" => r.alive_at_H, "death_main" => r.death_main, "acts" => r.acts, "dc_prec_rate_all_events" => r.dcp_rate))
            ev = r.events
            println("H=$H seed=$seed $arm $(rpad(sch.name, 11)) aliveH=$(r.alive_at_H) dc=$(r.dc_rate === nothing ? "-" : round(r.dc_rate; digits = 2)) E=$(length(ev)) ",
                    "T=$(count(e -> e["T"] == HOLDS, ev)) Tc=$(count(e -> e["T_core"] == HOLDS, ev)) b2fail=$(count(e -> e["b2"] == FAILS, ev)) confX=$(sum(e -> e["conf_X"], ev; init = 0)) ($(round(time() - t0; digits = 1)) s)")
        end
    end
end

# ---------------------------------------------------------------- controls (they show the checks work, nothing more)
# EXTRAS=0 skips the controls and the Lean export (the runs are split by H into parallel processes; one of them has EXTRAS=1)
const EXTRAS = get(ENV, "EXTRAS", "1") == "1"
const CARM = RBV ? :swap : :std   # S37: RB's :std never eats (no confirmation for control i), so its controls use :swap
const JA = RBV ? judge_a_prec : judge_a   # S37: (a) never holds on RB as is (Window.no_self_of_unreproduced); control ii on κ_prec
EXTRAS && let su = LBA.setup_with(294), p = su.params, sch = su.survival[1], s = org(1, su, CARM)   # seed 1 is outside the claim seeds
    recs, ext, alive_after, snaps = main_run(s, p, sch, 294)
    t = minimum(keys(snaps))
    n = branch(s, p, sch, snaps[t], t, 294, Set{Int}()); fake = branch(s, p, sch, snaps[t], t, 294, Set{Int}())   # "X" silencing nothing
    i_ok = fake.confirmations > 0 && judge_b1(fake) == UNDET && judge_b2(n, fake) == FAILS
    tt = findfirst(u -> u >= LC.DC_L && alive_after[u] && JA(s, recs, ext, u).v == HOLDS, 1:294)
    ii_ok = tt !== nothing && (e2 = copy(ext); e2[tt - 3] = true; JA(s, recs, e2, tt).v == UNDET)
    r1 = run_one(org(1, su, CARM), p, sch, 294); r2 = run_one(org(1, su, CARM), p, sch, 294)
    iii_ok = r1.events == r2.events && r1.dc_rate == r2.dc_rate
    # (v) the hook writes nothing back: the end state with the hook off equals the end state with the hook on
    function endstate(hook)
        s2 = org(1, su, CARM); st = AS.initial_state(s2, p); old = LBA.ON_STEP[]
        hook || (LBA.ON_STEP[] = nothing)
        SINK[] = (a...) -> nothing
        for _ in 1:294; AS.step!(st, s2, p, sch, Set{Int}()); end
        LBA.ON_STEP[] = old; SINK[] = nothing
        S = s2.side[st]; (copy(S.c.q), copy(S.c.sg), copy(S.c.active), copy(S.w.C), copy(S.pool))
    end
    v_ok = endstate(true) == endstate(false)
    res["controls"] = Dict("i_fake_X_detected" => i_ok, "i_fake_conf" => fake.confirmations, "ii_external_undetermined" => ii_ok,
                           "iii_repeat_equal" => iii_ok, "v_hook_readonly" => v_ok, "seed" => 1, "H" => 294, "schedule" => sch.name, "arm" => String(CARM))
    res["controls_ok"] = i_ok && ii_ok && iii_ok && v_ok
    println("controls i=$i_ok ii=$ii_ok iii=$iii_ok v=$v_ok")
end

# ---------------------------------------------------------------- windows for Lean (each clause true and false where seen)
kindnum(k) = k == 'R' ? 0 : k == 'C' ? 1 : 2
blist(x) = "#[" * join(string.(x), ", ") * "]"
EXTRAS && let b = B0[], io = IOBuffer(), expect = Any[], nU = length(b.names), nK = length(b.edges)
    println(io, "-- Generated by experiments/selfmaint.jl (S7): BODY windows, evaluated by Lean's own Window.checkDC.")
    println(io, "import LabCircuit\nopen BridgeLab\n")
    println(io, "def kindOf : Nat → Kind\n  | 0 => .receptor\n  | 1 => .core\n  | _ => .motor\n")
    println(io, "def net : Net where\n  nU := $nU\n  nK := $nK")
    println(io, "  kind := fun u => kindOf ($(blist([kindnum(k) for k in b.kind]))[u.val]!)")
    println(io, "  src := fun k => ⟨$(blist([e[1]-1 for e in b.edges]))[k.val]! % $nU, Nat.mod_lt _ (by decide)⟩")
    println(io, "  dst := fun k => ⟨$(blist([e[2]-1 for e in b.edges]))[k.val]! % $nU, Nat.mod_lt _ (by decide)⟩\n")
    i = 0
    for key in sort(collect(keys(samples)); by = string), (w, v) in samples[key]
        i += 1
        println(io, "def w$i : Window net where")
        println(io, "  kept := fun k => $(blist(w.kept))[k.val]!")
        println(io, "  on := fun u => $(blist(w.on))[u.val]!")
        println(io, "  reproduced := fun m k => $(blist(vec(permutedims(w.reproduced))))[m.val * $nK + k.val]!")
        println(io, "  affects := fun m e => $(blist(vec(permutedims(w.affects))))[m.val * $nU + e.val]!")
        println(io, "  reproducedVia := fun e k => $(blist(vec(permutedims(w.via))))[e.val * $nK + k.val]!")
        println(io, "#eval [decide w$i.ElemSelf, decide w$i.ElemSMC, decide w$i.ElemAct, decide w$i.ElemBound, w$i.checkDC]\n")
        push!(expect, [v.self, v.smc, v.act, v.bound, v.dc])
    end
    gen = get(ENV, "GEN", "")   # S24: other generated names (default unchanged)
    write(joinpath(LAB, "formal", "gen", gen == "" ? "WindowsBody.lean" : "WindowsBody-$gen.lean"), String(take!(io)))
    write(joinpath(LAB, "formal", "gen", gen == "" ? "expected-body.json" : "expected-body-$gen.json"), JSON.json(expect))
    res["lean_windows"] = i; res["lean_windows_seen"] = sort([string(k) for k in keys(samples)])
    println("exported $i windows to formal/gen/", gen == "" ? "WindowsBody.lean" : "WindowsBody-$gen.lean")
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-selfmaint.json"))
write(out, JSON.json(res, 2))
println("written ", relpath(out, LAB))
