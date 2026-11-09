# S33 (spec discussion/specs/S33-body-rest.md r1): the rest motor m0, first stage. Lineage R (m0 from birth) and N0 (no m0)
# on the same seeds and curriculum. For R: per-step records (m0's candidacy and class, patch acts, answers, m0's edges),
# 32-step windows with the release branch (REST_OFF over the whole window), DC and survival per window, rest intervals,
# restart, and the alpha check of m0 (sil m0 at its sole-candidate acts, with P18). Writes results-rest.json.
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(411:420, ",")), ","))
const ARMS = Symbol.(split(get(ENV, "ARMS", "std,swap"), ","))
const GSEED = parse(Int, get(ENV, "GSEED", "411"))
const H = 392; const WL = 32; const NW = 12; const NALPHA = 3

org(seed, su, cur; rest) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                       contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = rest)
alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))
prestate(c) = (active = copy(c.active), q = copy(c.q), sg = copy(c.sg), lastM = c.lastM === nothing ? nothing : copy(c.lastM), now = c.t + 1)
fields(x) = Tuple(deepcopy(getfield(x, f)) for f in fieldnames(typeof(x)))

"""Per-step facts from the state before (`pre`) and step!'s result `o` (the candidate formula of S32)."""
function facts(b, pre, o, c, m0)
    mot = [m for m in eachindex(b.names) if b.kind[m] == 'M']
    tot(m) = count(k -> o.drove[k], b.ins[m]); core(m) = any(k -> o.drove[k] && b.kind[b.edges[k][1]] == 'C', b.ins[m])
    cand = [m for m in mot if tot(m) >= b.theta[m] && core(m)]
    patchc = [m for m in cand if b.patch[m] <= 2]
    acting = collect(o.acting); pact = [m for m in acting if b.patch[m] <= 2]
    k0 = b.ins[m0]
    cls = nothing
    if m0 in acting
        idle(m) = pre.lastM !== nothing && pre.now - pre.lastM[m] > LC.FORGET
        cls = isempty(patchc) ? "a_no_patch_candidate" : (idle(m0) && !any(idle, patchc)) ? "b_idle" : "c_rank"
    end
    Dict("m0_cand" => m0 in cand, "m0_act" => m0 in acting, "sole" => cand == [m0], "class" => cls, "patch_acts" => length(pact),
         "d" => collect(o.d), "m0_conf" => any(k -> o.confirmed_patch[k], k0), "m0_qsg" => maximum(c.q[k0]) + maximum(c.sg[k0]),
         "m0_drop" => any(k -> c.q[k] < pre.q[k] || c.sg[k] < pre.sg[k], k0))
end

function raising(s, seed, cur)
    b = LC.newborn(false; rest = true); c = LC.init(b); noise = LC.Mulberry(seed); m0 = LC.unit(b, "m0"); recs = Any[]
    for y in LBA.curriculum(cur)
        pre = prestate(c)
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = noise, contrast = s.contrast, idle_first = s.idle_first, core_gate = s.core_gate,
                     seen_both = s.seen_both, sed_fade = s.sed_fade, sed_fade_drive = LBA.SEDFADE_DRIVE[])
        push!(recs, facts(b, pre, o, c, m0))
    end
    same = b.edges == s.b.edges && all(f -> isequal(getfield(c, f), getfield(s.raised, f)), fieldnames(typeof(c))) &&
           all(f -> isequal(getfield(noise, f), getfield(s.noise, f)), fieldnames(typeof(noise)))
    (recs = recs, same = same)
end

const PRE = Ref{Any}(nothing); const SINK = Ref{Any}(nothing)
LBA.CLAMP[] = (st, y) -> (SINK[] === nothing || (PRE[] = prestate(SINK[].s.side[st].c)); (y, nothing))   # read only
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[].f(st, o, c, y))

"""Run n updates from `snap` (or from the initial state when nothing), with `restoff`, silencing `sil(τ)`; returns records."""
function go(s, p, sch, snap, t0, n; restoff = false, sil = τ -> Set{Int}(), keepsnaps = false)
    st, S = snap === nothing ? (x = AS.initial_state(s, p); (x, s.side[x])) : deepcopy(snap); s.side[st] = S
    m0 = LC.unit(s.b, "m0"); recs = Any[]; snaps = Dict{Int,Any}(); dead = false
    keepsnaps && (snaps[t0] = deepcopy((st, S)))
    LBA.REST_OFF[] = restoff ? (st_ -> st_ === st) : nothing
    SINK[] = (s = s, f = (st_, o, c, y) -> st_ === st && push!(recs, merge(m0 === nothing ? Dict{String,Any}() : facts(s.b, PRE[], o, c, m0),
                 Dict("t" => st_.t + 1, "dc" => LC.dc_record(s.b, o, c; partner_live = false, y = y, phase = "world"), "acts" => collect(o.acting)))))
    after = Any[]
    for τ in t0+1:t0+n
        k = length(recs)
        AS.step!(st, s, p, sch, sil(τ))
        length(recs) == k && push!(recs, nothing)
        a = alive(s, st); a || (dead = true)
        push!(after, (alive = a, pool = copy(S.pool), w = (A = copy(S.w.A), B = copy(S.w.B), C = copy(S.w.C)), noise = fields(S.noise),
                      recep = [S.c.active[u] for u in eachindex(s.b.names) if s.b.kind[u] == 'R']))
        keepsnaps && a && τ % WL == 0 && (snaps[τ] = deepcopy((st, S)))
    end
    SINK[] = nothing; LBA.REST_OFF[] = nothing; delete!(s.side, st)
    (recs = recs, after = after, snaps = snaps, dead = dead)
end

function run_R(s, p, sch)
    main = go(s, p, sch, nothing, 0, H; keepsnaps = true)
    recs = main.recs; m0 = LC.unit(s.b, "m0")
    pa(r) = r === nothing ? 0 : r["patch_acts"]
    wins = Any[]
    for w in 1:NW
        lo = (w - 1) * WL; rng = lo+1:lo+WL
        Aw = sum(pa, recs[rng])
        snap = lo == 0 ? nothing : get(main.snaps, lo, nothing)
        rel = (snap === nothing && lo > 0) ? nothing : go(s, p, sch, snap, lo, WL; restoff = true)
        Ar = rel === nothing ? nothing : sum(pa, rel.recs)
        livew = all(i -> main.after[i].alive, rng) && all(r -> r !== nothing, recs[rng])
        dc = livew ? LC.check_dc(s.b, LC.dc_window(s.b, [r["dc"] for r in recs[rng]])).dc : false
        m0acts = count(r -> r !== nothing && r["m0_act"], recs[rng])
        push!(wins, Dict("w" => w, "A" => Aw, "A_release" => Ar, "i" => Ar !== nothing && Ar > Aw, "ii" => livew && dc, "alive" => livew, "dc" => dc,
                         "m0_acts" => m0acts, "release_m0_qsg" => rel === nothing ? nothing : maximum(r -> r === nothing ? 0 : r["m0_qsg"], rel.recs),
                         "release_m0_confdrop" => rel === nothing ? nothing : any(r -> r !== nothing && (r["m0_conf"] || r["m0_drop"]), rel.recs),
                         "release_m0_act" => rel === nothing ? nothing : count(r -> r !== nothing && r["m0_act"], rel.recs)))
    end
    # rest intervals (maximal runs of windows with (i) and (ii)) and restart within the next 3 complete windows
    Is = Any[]; w = 1
    while w <= NW
        if wins[w]["i"] && wins[w]["ii"]
            a = w; while w + 1 <= NW && wins[w+1]["i"] && wins[w+1]["ii"]; w += 1; end
            e = w; last = wins[e]["A"]
            if e == NW
                verdict = "ongoing"
            else
                nxt = e+1:min(e + 3, NW)
                hit = any(j -> wins[j]["A"] > last && wins[j]["ii"], nxt)
                verdict = hit ? "restart_observed" : (length(nxt) == 3 ? "not_observed_within_Hr" : "undetermined")
            end
            push!(Is, Dict("from" => a, "to" => e, "restart" => verdict))
        end
        w += 1
    end
    # alpha check: the first NALPHA steps where m0 was the sole candidate and acted (chosen from the record only)
    us = [r["t"] for r in recs if r !== nothing && r["sole"] && r["m0_act"]][1:min(NALPHA, end)]
    al = Any[]
    for u in us
        lo = WL * ((u - 1) ÷ WL); base = lo == 0 ? nothing : main.snaps[lo]
        # the snapshot at u - 1: replay from the window snapshot (deterministic)
        st, S = base === nothing ? (x = AS.initial_state(s, p); (x, s.side[x])) : deepcopy(base); s.side[st] = S
        for τ in lo+1:u-1; AS.step!(st, s, p, sch, Set{Int}()); end
        snap = deepcopy((st, S)); delete!(s.side, st)
        C = go(s, p, sch, snap, u - 1, 2); B = go(s, p, sch, snap, u - 1, 2; sil = τ -> τ == u ? Set([m0]) : Set{Int}())
        ok = C.recs[1] !== nothing && B.recs[1] !== nothing && C.recs[2] !== nothing && B.recs[2] !== nothing
        c_m0 = ok && C.recs[1]["m0_act"]
        others = ok && [m for m in C.recs[1]["acts"] if m != m0] == [m for m in B.recs[1]["acts"] if m != m0]
        b_none = ok && isempty(B.recs[1]["acts"])   # sil took effect: nothing acted at u in B (codex I-R 5)
        # the replay to u - 1 equals the main run (codex I-R 4): C's act at u and the state after u
        replay = ok && C.recs[1]["acts"] == recs[u]["acts"] && C.after[1].pool == main.after[u].pool && isequal(C.after[1].w, main.after[u].w) && isequal(C.after[1].noise, main.after[u].noise)
        p18 = ok && c_m0 && b_none && others && C.after[1].pool == B.after[1].pool && isequal(C.after[1].w, B.after[1].w) && isequal(C.after[1].noise, B.after[1].noise)
        diff = p18 ? count(i -> C.after[2].recep[i] != B.after[2].recep[i], eachindex(C.after[2].recep)) : nothing
        bq = maximum(r -> r === nothing ? 0 : r["m0_qsg"], vcat(C.recs, B.recs))
        bcd = any(r -> r !== nothing && (r["m0_conf"] || r["m0_drop"]), vcat(C.recs, B.recs))
        push!(al, Dict("u" => u, "branch_m0_qsg" => bq, "branch_m0_confdrop" => bcd, "replay_ok" => replay, "B_none" => b_none, "C_m0_acted" => c_m0, "B_acts" => ok ? B.recs[1]["acts"] : nothing, "others_same" => others, "P18" => p18, "recep_diff" => diff))
    end
    (recs = [r === nothing ? nothing : Dict(k => v for (k, v) in r if k != "dc") for r in recs], windows = wins, intervals = Is, alpha = al,
     survived = !main.dead, A_total = sum(pa, recs))
end
function run_N0(s, p, sch)
    m = go(s, p, sch, nothing, 0, H)
    (survived = !m.dead, A_total = count(r -> r !== nothing && any(u -> s.b.patch[u] <= 2, r["acts"]), m.recs))
end

res = Dict{String,Any}("spec" => "discussion/specs/S33-body-rest.md r1", "rule" => "sf", "seeds" => SEEDS, "gseed" => GSEED, "H" => H,
                       "arms" => String.(ARMS), "R" => Any[], "N0" => Any[], "raising" => Any[])
su = LBA.setup_with(H); p = su.params
g = org(GSEED, su, :std; rest = true)
x1 = run_R(g, p, su.survival[1]); x2 = run_R(g, p, su.survival[1])
res["G2_repeat"] = isequal(x1.recs, x2.recs) && isequal(x1.windows, x2.windows)
LBA.REST_OFF[] = nothing
y1 = go(g, p, su.survival[1], nothing, 0, H).recs
function go_false(s, p, sch)   # G3: REST_OFF always false equals nothing
    st = AS.initial_state(s, p); S = s.side[st]; recs = Any[]; m0 = LC.unit(s.b, "m0")
    SINK[] = (s = s, f = (st_, o, c, y) -> st_ === st && push!(recs, collect(o.acting)))
    LBA.REST_OFF[] = st_ -> false
    for t in 1:H; AS.step!(st, s, p, sch, Set{Int}()); end
    LBA.REST_OFF[] = nothing; SINK[] = nothing; delete!(s.side, st); recs
end
res["G3_restoff_false"] = go_false(g, p, su.survival[1]) == [r === nothing ? nothing : r["acts"] for r in y1 if r !== nothing]
println("G2 ", res["G2_repeat"], " G3 ", res["G3_restoff_false"])
for seed in SEEDS, arm in ARMS
    sR = org(seed, su, arm; rest = true); sN = org(seed, su, arm; rest = false)
    Rr = raising(sR, seed, arm)
    push!(res["raising"], Dict("seed" => seed, "arm" => String(arm), "same" => Rr.same, "steps" => Rr.recs))
    for sch in su.survival
        x = run_R(sR, p, sch); n = run_N0(sN, p, sch)
        push!(res["R"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "steps" => x.recs, "windows" => x.windows,
                             "intervals" => x.intervals, "alpha" => x.alpha, "survived" => x.survived, "A_total" => x.A_total))
        push!(res["N0"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "survived" => n.survived, "A_total" => n.A_total))
        println("seed=$seed $arm $(rpad(sch.name, 11)) m0 acts $(count(r -> r !== nothing && r["m0_act"], x.recs)) (i) $(count(w -> w["i"], x.windows)) I $(length(x.intervals)) alpha $(length(x.alpha)) surv R $(x.survived) N0 $(n.survived)")
    end
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-rest.json"))
write(out, JSON.json(res))
println("written ", out)
