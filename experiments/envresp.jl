# S9 (spec discussion/specs/S9-body-envresp.md r2): D3's R2-c (with the revision r6, notes/D3.md §7) on the SF version of
# BODY, three-valued. Writes experiments/results-envresp.json. Predictions: predictions-envresp.md (frozen before the first run).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(41:50, ",")), ","))
const H = parse(Int, get(ENV, "H", "392"))
const ARMS = Symbol.(split(get(ENV, "ARMS", "std,swap"), ","))
const NAMED = get(ENV, "NAMED", "1") == "1"         # seeds 35/37 :swap p2-high, described only
const EXTRAS = get(ENV, "EXTRAS", "1") == "1"
const HOLDS, FAILS, UNDET = "holds", "fails", "undetermined"
const W = 15                                         # the end of the frozen choice_window
const COUPLED = ["r1", "r2", "r3", "r4", "r7", "r8"] # alpha reaches them (core/dc.jl ALPHA_FEATURES)
const UNCOUPLED = ["r5", "r6"]
const DECLARED = Dict("m1" => Set(["r1", "r3", "r7", "r8"]), "m2" => Set(["r2", "r4", "r7", "r8"]))
const RBV = get(ENV, "RBV", "0") == "1"   # S39 (specs/S39-rb-envresp.md): RB = SF + rest (m0) + rest_body :B (rb) + α, default off
const RECEPTORS = RBV ? [["r$i" for i in 1:8]; "rb"] : ["r$i" for i in 1:8]   # S39: rb recorded only (not coupled under α)

org(seed, su, cur) = RBV ?
    LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = true, rest_body = :B) :
    LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
# S39: κ_prec windows (as S37, selfmaint.jl): the kept of the window restricted to edges not exempt from the decay
exempt(b, k) = b.patch[b.edges[k][2]] == 4 && b.q0[k] > 0
prec_window(b, w) = LC.DCWindow((f == :kept ? [w.kept[k] && !exempt(b, k) for k in eachindex(w.kept)] : getfield(w, f) for f in fieldnames(LC.DCWindow))...)
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))
alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))
units(s, names) = Set{Int}(LC.unit(s.b, n) for n in names)
three(xs) = any(==(FAILS), xs) ? FAILS : all(==(HOLDS), xs) ? HOLDS : UNDET
rngstate(r) = Tuple(getfield(r, f) for f in fieldnames(typeof(r)))
swapped(sch) = AS.Schedule(sch.name * "-swap", reverse(sch.first), reverse(sch.second), sch.switch)

function main_run(s, p, sch)
    st = AS.initial_state(s, p)
    recs = LC.DCStep[]; alive_after = Bool[]; snaps = Dict{Int,Any}()
    SINK[] = (st_, o, c, y) -> st_ === st && push!(recs, LC.dc_record(s.b, o, c; partner_live = false, y = y, phase = "world"))
    for t in 1:H
        AS.step!(st, s, p, sch, Set{Int}())
        push!(alive_after, alive(s, st))
        alive_after[t] && t % 32 == 0 && (snaps[t] = deepcopy((st, s.side[st])))
    end
    SINK[] = nothing; delete!(s.side, st)
    recs, alive_after, snaps
end

"""A branch from the snapshot at t for n updates with schedule `sch`; `sil(τ)` gives the silenced set at update τ;
`swap_pool` exchanges the two pools at t. Records per update: the patches of the acting patch motors, the yields read,
the receptors' states after the update, the pools after the update; and the noise state at the end."""
function branch(s, p, sch, snap, t, n, sil; swap_pool = false, clamp_rb = false)
    st, S = deepcopy(snap); s.side[st] = S
    swap_pool && (S.pool .= reverse(S.pool))
    # S39 (b_rb): rb read as false at every update t+1..t+n of this branch only (BODY_CLAMP, restored after the branch)
    clamp_rb && (LBA.BODY_CLAMP[] = st_ -> st_ === st ? false : nothing)
    rec = Any[]
    SINK[] = (st_, o, c, y) -> st_ === st && push!(rec, (acts = Set(s.b.patch[m] for m in o.acting if s.b.patch[m] <= 2), motors = Set(o.acting), y = copy(y),
                                                         m0 = any(m -> s.b.patch[m] == 4, o.acting)))
    after = Any[]
    for τ in t+1:t+n
        k = length(rec)
        AS.step!(st, s, p, sch, sil(τ))
        length(rec) == k && push!(rec, (acts = Set{Int}(), motors = Set{Int}(), y = nothing, m0 = false))   # a dead update
        push!(after, (recep = Dict(r => S.c.active[LC.unit(s.b, r)] for r in RECEPTORS), pool = copy(S.pool), body = copy(S.w.A)))
    end
    noise = rngstate(S.noise)
    SINK[] = nothing; delete!(s.side, st); LBA.BODY_CLAMP[] = nothing
    (rec = rec, after = after, noise = noise)
end

"""h, l and the number of counted updates: updates t+1..t+W whose schedule has a strict order (update τ reads yield_of at τ-1)."""
function hl(rec, sch, t)
    h = l = n = 0
    for (i, r) in enumerate(rec)
        g1, g2 = AS.yield_of(sch, 1, t + i - 1), AS.yield_of(sch, 2, t + i - 1)
        g1 == g2 && continue
        hi, lo = g1 > g2 ? (1, 2) : (2, 1)
        n += 1; h += hi in r.acts; l += lo in r.acts
    end
    (h = h, l = l, n = n)
end
"""S39 (b_act): among the counted updates, those with a patch act, with m0's act, with no act, and dead (observation ended)."""
function hl_act(rec, sch, t)
    h = l = n = nact = nm0 = nnone = ndead = 0
    for (i, r) in enumerate(rec)
        g1, g2 = AS.yield_of(sch, 1, t + i - 1), AS.yield_of(sch, 2, t + i - 1)
        g1 == g2 && continue
        hi, lo = g1 > g2 ? (1, 2) : (2, 1)
        n += 1; h += hi in r.acts; l += lo in r.acts
        r.y === nothing ? (ndead += 1) : !isempty(r.acts) ? (nact += 1) : r.m0 ? (nm0 += 1) : (nnone += 1)
    end
    (h = h, l = l, n = n, nact = nact, nm0 = nm0, nnone = nnone, ndead = ndead)
end
"""S39 (b_act, codex V1 1-3): as (b), with one more undetermined case, fixed before the run: a counted update set with no patch
act in N or in Z ("no patch act among the counted updates"; the m0 / none / dead counts are recorded, no cause is named).
The holding condition is the same as (b). Used for N, Z only, never for (b')."""
function judge_b_act(N, Z, schN, schZ, t)
    (N.rec[1].y === nothing || Z.rec[1].y === nothing || N.rec[1].y == Z.rec[1].y) && return (v = UNDET, why = "no perceptual difference at t+1", a = nothing, b = nothing)
    a, b = hl_act(N.rec, schN, t), hl_act(Z.rec, schZ, t)
    (a.n == 0 || b.n == 0) && return (v = UNDET, why = "no counted update", a = a, b = b)
    (a.nact == 0 || b.nact == 0) && return (v = UNDET, why = "no patch act among the counted updates", a = a, b = b)
    (v = a.h > a.l && b.h > b.l ? HOLDS : FAILS, why = "", a = a, b = b)
end
"""(b) from the N and Z branches (fixed before the run, notes/D3.md R2-c and §7)."""
function judge_b(N, Z, schN, schZ, t)
    (N.rec[1].y === nothing || Z.rec[1].y === nothing || N.rec[1].y == Z.rec[1].y) && return (v = UNDET, why = "no perceptual difference at t+1")
    a, b = hl(N.rec, schN, t), hl(Z.rec, schZ, t)
    (a.n == 0 || b.n == 0) && return (v = UNDET, why = "no counted update")
    (v = a.h > a.l && b.h > b.l ? HOLDS : FAILS, why = "N $(a) Z $(b)")
end

"""(c) at t for motor m: usable? and the differing receptors at t+2."""
function check_c(s, p, sch, snap, t, mname)
    m = LC.unit(s.b, mname)
    C = branch(s, p, sch, snap, t, 2, τ -> Set{Int}())
    B = branch(s, p, sch, snap, t, 2, τ -> τ == t + 1 ? Set([m]) : Set{Int}())
    length(C.after) == 2 || return (usable = false, why = "short")
    m in C.rec[1].motors || return (usable = false, why = "m did not act at t+1")
    setdiff(C.rec[1].motors, [m]) == setdiff(B.rec[1].motors, [m]) || return (usable = false, why = "other acts differ")
    pk = s.b.patch[m]; other = 3 - pk
    C.after[1].pool[other] == B.after[1].pool[other] || return (usable = false, why = "other pool differs")
    C.noise == B.noise || return (usable = false, why = "noise state differs")
    diff = [r for r in RECEPTORS if C.after[2].recep[r] != B.after[2].recep[r]]
    (usable = true, why = "", diff = diff, body_differs = C.after[1].body != B.after[1].body)
end
mismatch(mname, diff, declared = DECLARED) = [r for r in diff if !(r in declared[mname]) && r in COUPLED]

function run_one(s, p, sch)
    recs, alive_after, snaps = main_run(s, p, sch)
    schZ = swapped(sch); none = τ -> Set{Int}()
    Cp, Up = units(s, COUPLED), units(s, UNCOUPLED)
    events = Any[]
    for t in sort(collect(keys(snaps)))
        win = LC.dc_window(s.b, @view recs[t-LC.DC_L+1:t])
        c = LC.check_dc(s.b, win)
        a = c.smc && c.act ? HOLDS : FAILS
        cp = RBV ? LC.check_dc(s.b, prec_window(s.b, win)) : nothing   # S39: κ_prec window, recorded beside (codex V1 5)
        N = branch(s, p, sch, snaps[t], t, W, none); Z = branch(s, p, schZ, snaps[t], t, W, none; swap_pool = true)
        Z0 = branch(s, p, schZ, snaps[t], t, W, none)
        b = judge_b(N, Z, sch, schZ, t); b0 = judge_b(N, Z0, sch, schZ, t)
        bp = judge_b(branch(s, p, sch, snaps[t], t, W, τ -> Cp), branch(s, p, schZ, snaps[t], t, W, τ -> Cp; swap_pool = true), sch, schZ, t)
        bu = judge_b(branch(s, p, sch, snaps[t], t, W, τ -> Up), branch(s, p, schZ, snaps[t], t, W, τ -> Up; swap_pool = true), sch, schZ, t)
        need = b.v == HOLDS ? (bp.v == FAILS ? HOLDS : bp.v == HOLDS ? FAILS : UNDET) : UNDET
        cc = Dict(mn => check_c(s, p, sch, snaps[t], t, mn) for mn in ("m1", "m2"))
        mis = Dict(mn => (x.usable ? mismatch(mn, x.diff) : String[]) for (mn, x) in cc)
        # support needs a declared, coupled receptor's difference (codex I-R S9 2; differences of r5 / r6 are recorded only)
        cstate = any(!isempty, values(mis)) ? "mismatch" : any(((mn, x),) -> x.usable && any(r -> r in DECLARED[mn] && r in COUPLED, x.diff), cc) ? "support" : "none"
        R = cstate == "mismatch" ? UNDET : three([a, b.v])
        ex = Dict{String,Any}()
        if RBV   # S39: b_act and R2c_act (a separate proposition), the rb at t+1 in N and Z, b_rb (rb clamped false in N and Z), κ_prec (a)
            ba = judge_b_act(N, Z, sch, schZ, t)
            Nr = branch(s, p, sch, snaps[t], t, W, none; clamp_rb = true); Zr = branch(s, p, schZ, snaps[t], t, W, none; swap_pool = true, clamp_rb = true)
            br = judge_b(Nr, Zr, sch, schZ, t); bra = judge_b_act(Nr, Zr, sch, schZ, t)
            # codex I-R 2 #2, #4: the counts of every branch, independent of the verdict (kept also when (b_act) returns early)
            dct(x) = Dict(string(k) => getfield(x, k) for k in keys(x))
            ex = Dict("b_act" => ba.v, "b_act_why" => ba.why, "b_act_N" => dct(hl_act(N.rec, sch, t)), "b_act_Z" => dct(hl_act(Z.rec, schZ, t)),
                      "b_act_Nrb" => dct(hl_act(Nr.rec, sch, t)), "b_act_Zrb" => dct(hl_act(Zr.rec, schZ, t)),
                      # the clamp's effect: rb on after any update of the clamped branches (must be 0; checked as a gate)
                      "rb_on_clamped" => count(a -> a.recep["rb"], Nr.after) + count(a -> a.recep["rb"], Zr.after),
                      "n_clamped" => length(Nr.after) + length(Zr.after),   # codex I-R 3 #3: the clamped updates (2 x 15 expected)
                      "rb_on_N" => count(a -> a.recep["rb"], N.after), "rb_on_Z" => count(a -> a.recep["rb"], Z.after),
                      "R2c_act" => cstate == "mismatch" ? UNDET : three([a, ba.v]),
                      "rb_t1_N" => N.after[1].recep["rb"], "rb_t1_Z" => Z.after[1].recep["rb"],
                      "b_rb" => br.v, "b_rb_why" => br.why, "b_act_rb" => bra.v, "b_act_rb_why" => bra.why,
                      "m0_N" => count(r -> r.m0, N.rec), "m0_Z" => count(r -> r.m0, Z.rec), "m0_Nrb" => count(r -> r.m0, Nr.rec), "m0_Zrb" => count(r -> r.m0, Zr.rec),
                      "smc_prec" => cp.smc, "act_prec" => cp.act, "a_prec" => cp.smc && cp.act ? HOLDS : FAILS)
        end
        push!(events, Dict("t" => t, "smc" => c.smc, "act" => c.act, "a" => a, "b" => b.v, "b_why" => b.why, "b_Z0" => b0.v, "b_prime" => bp.v, "b_prime_why" => bp.why,
            "b_uncoupled" => bu.v, "need" => need, "c" => cstate, "R2c" => R, "y_N1" => N.rec[1].y, "y_Z1" => Z.rec[1].y,
            "c_detail" => Dict(mn => Dict("usable" => x.usable, "why" => x.why, "diff" => get(x, :diff, String[]), "body_differs" => get(x, :body_differs, nothing), "mismatch" => mis[mn]) for (mn, x) in cc)))
        merge!(events[end], ex)
    end
    (events = events, alive_at_H = alive_after[H], death_main = findfirst(!, alive_after))
end
summ(ev, k) = Dict(v => count(e -> e[k] == v, ev) for v in unique([e[k] for e in ev]))

# ---------------------------------------------------------------- unit tests and controls (EXTRAS=1)
res = Dict{String,Any}("spec" => RBV ? "discussion/specs/S39-rb-envresp.md r1" : "discussion/specs/S9-body-envresp.md r2", "rule" => RBV ? "rb" : "sf", "seeds" => SEEDS, "H" => H, "arms" => String.(ARMS), "runs" => Any[], "named" => Any[])
if EXTRAS
    sch = AS.Schedule("t", (5, 0), (5, 0), 20); schZ = swapped(sch)
    mk(acts, y) = (rec = [(acts = Set(a), motors = Set{Int}(), y = y) for a in acts],)
    u1 = judge_b(mk(fill([1], 15), [5.0, 0.0]), mk(fill([2], 15), [0.0, 5.0]), sch, schZ, 40).v == HOLDS
    u2 = judge_b(mk(fill([1], 15), [5.0, 0.0]), mk(fill([1], 15), [0.0, 5.0]), sch, schZ, 40).v == FAILS
    u3 = judge_b(mk(fill([1], 15), [5.0, 0.0]), mk(fill([2], 15), [5.0, 0.0]), sch, schZ, 40).v == UNDET
    u4 = judge_b(mk(fill(Int[], 15), [5.0, 0.0]), mk(fill(Int[], 15), [0.0, 5.0]), sch, schZ, 40).v == FAILS
    u5 = mismatch("m1", ["r2", "r5", "r1"]) == ["r2"] && isempty(mismatch("m2", ["r2", "r8", "r6"]))
    # S39 unit tests of b_act: holds, fails, no patch act (m0 only) -> undetermined, the same perception -> undetermined
    mka(acts, y; m0 = false) = (rec = [(acts = Set(a), motors = Set{Int}(), y = y, m0 = m0) for a in acts],)
    u6 = judge_b_act(mka(fill([1], 15), [5.0, 0.0]), mka(fill([2], 15), [0.0, 5.0]), sch, schZ, 40).v == HOLDS &&
         judge_b_act(mka(fill([1], 15), [5.0, 0.0]), mka(fill([1], 15), [0.0, 5.0]), sch, schZ, 40).v == FAILS &&
         judge_b_act(mka(fill(Int[], 15), [5.0, 0.0]; m0 = true), mka(fill([2], 15), [0.0, 5.0]), sch, schZ, 40).v == UNDET &&
         judge_b_act(mka(fill([1], 15), [5.0, 0.0]), mka(fill([2], 15), [5.0, 0.0]), sch, schZ, 40).v == UNDET
    CARM = RBV ? :swap : :std   # S39: RB's :std does not eat; the controls use :swap
    su = LBA.setup_with(H); p = su.params; s = org(1, su, CARM); sch1 = su.survival[1]   # seed 1: outside the claim seeds
    recs, aa, snaps = main_run(s, p, sch1); t = minimum(keys(snaps))
    N = branch(s, p, sch1, snaps[t], t, W, τ -> Set{Int}()); fake = branch(s, p, sch1, snaps[t], t, W, τ -> Set{Int}())
    i_ok = judge_b(N, fake, sch1, sch1, t).v == UNDET
    nreal, ndet = let nr = 0, nd = 0   # the counters in a let block (a soft-scope bug found in the smoke run)
        for t in sort(collect(keys(snaps)))
            x = check_c(s, p, sch1, snaps[t], t, "m1")
            x.usable && "r1" in x.diff || continue
            nr += 1; nd += !isempty(mismatch("m1", x.diff, Dict("m1" => Set(["r3", "r7", "r8"]))))
        end
        nr, nd
    end
    r1 = run_one(org(1, su, CARM), p, sch1); r2 = run_one(org(1, su, CARM), p, sch1)
    res["controls"] = Dict("unit_b" => u1 && u2 && u3 && u4, "unit_mismatch" => u5, "unit_b_act" => u6, "arm" => String(CARM), "i_fake_Z_undetermined" => i_ok,
                           "ii_real_m1r1_events" => nreal, "ii_detected" => nreal == 0 ? "unverified" : ndet == nreal, "iii_repeat" => r1.events == r2.events)
    res["controls_ok"] = u1 && u2 && u3 && u4 && u5 && u6 && i_ok && r1.events == r2.events && (nreal == 0 || ndet == nreal)
    println("controls ", res["controls"])
end

su = LBA.setup_with(H); p = su.params
todo = vec([(seed, arm, sch, false) for seed in SEEDS, arm in ARMS, sch in su.survival])
NAMED && append!(todo, [(seed, :swap, su.survival[2], true) for seed in (35, 37)])
for (seed, arm, sch, named) in todo
    t0 = time(); r = run_one(org(seed, su, arm), p, sch)
    push!(named ? res["named"] : res["runs"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "events" => r.events, "alive_at_H" => r.alive_at_H, "death_main" => r.death_main))
    ev = r.events
    println("seed=$seed $arm $(rpad(sch.name, 11))$(named ? " [named]" : "") a=$(summ(ev, "a")) b=$(summ(ev, "b")) need=$(summ(ev, "need")) c=$(summ(ev, "c")) R2c=$(summ(ev, "R2c")) ($(round(time() - t0; digits = 1)) s)")
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-envresp.json"))
write(out, JSON.json(res, 2))
println("written ", out)
