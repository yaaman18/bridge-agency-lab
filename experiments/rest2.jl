# S34 (spec discussion/specs/S34-body-rest2.md r1): the rest motor m0 with the body receptor rb and innate edges (α).
# Lineages N0 (no m0), RA (rb -> m0 innate), RB (rb, c1, c2 -> m0 innate). Records per living step (exempt edges' q, m0's
# candidacy and act, rb's previous reading), the one-step reversal (copies of the circuit and rng with old[rb] true / false;
# the main run is not advanced), and for RB the 32-step windows with the rb clamp (true / false) and the release
# (REST_OFF) for the rest intervals. Writes results-rest2.json.
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(421:430, ",")), ","))
const ARMS = Symbol.(split(get(ENV, "ARMS", "std,swap"), ","))
const GSEED = parse(Int, get(ENV, "GSEED", "421"))
const H = 392; const WL = 32; const NW = 12

org(seed, su, cur; rest = false, rest_body = nothing) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0,
    idle_first = true, contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = rest, rest_body = rest_body)
alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))
exempt(b) = [k for k in eachindex(b.edges) if b.patch[b.edges[k][2]] == 4 && b.q0[k] > 0]
iscand(b, o, m) = count(k -> o.drove[k], b.ins[m]) >= b.theta[m] && any(k -> o.drove[k] && b.kind[b.edges[k][1]] == 'C', b.ins[m])

function facts(b, pre_active, o, c)
    m0 = LC.unit(b, "m0"); rb = LC.unit(b, "rb"); ex = exempt(b)
    m0 === nothing && return Dict{String,Any}("patch_acts" => count(m -> b.patch[m] <= 2, o.acting), "m0_act" => false)   # N0
    Dict{String,Any}("m0_cand" => iscand(b, o, m0), "m0_act" => m0 in o.acting, "patch_acts" => count(m -> b.patch[m] <= 2, o.acting),
                     "rb_old" => pre_active[rb], "exempt_ok" => all(k -> c.q[k] == 1, ex),
                     "exempt_q" => [(b.names[b.edges[k][1]], c.q[k]) for k in ex])   # codex I-R 7: which edge, which value
end

function raising(s, seed, cur, rest_body)
    b = LC.newborn(false; rest = true, rest_body = rest_body); c = LC.init(b); noise = LC.Mulberry(seed); recs = Any[]
    for y in LBA.curriculum(cur)
        pa = copy(c.active)
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = noise, contrast = s.contrast, idle_first = s.idle_first, core_gate = s.core_gate,
                     seen_both = s.seen_both, sed_fade = s.sed_fade, sed_fade_drive = LBA.SEDFADE_DRIVE[])
        push!(recs, facts(b, pa, o, c))
    end
    same = b.edges == s.b.edges && all(f -> isequal(getfield(c, f), getfield(s.raised, f)), fieldnames(typeof(c))) &&
           all(f -> isequal(getfield(noise, f), getfield(s.noise, f)), fieldnames(typeof(noise)))
    (recs = recs, same = same)
end

const HOOK = Ref{Any}(nothing)   # (s, st, flip::Bool, recs)
const PRE = Ref{Any}(nothing)
"""The one-step reversal at the update about to run: copies of the circuit and rng, old[rb] = true / false."""
function reversal(s, S, y)
    b = s.b; rb = LC.unit(b, "rb"); m0 = LC.unit(b, "m0")
    LBA.BODY_CLAMP[] === nothing || error("the reversal is computed on unclamped main runs only")
    bf = LBA.body_quantity(S.w) >= S.Q0   # the main run's own reading at this update
    S.c.prev === nothing && error("prev is nothing: the reversal would change onset (codex I-R 2)")   # the raised state always has prev
    out = Any[]
    for v in (true, false)
        c = deepcopy(S.c); nz = deepcopy(S.noise); c.active[rb] = v
        o = LC.step!(c, b, [y[1], y[2], 0.0]; noise = nz, contrast = s.contrast, idle_first = s.idle_first, core_gate = s.core_gate,
                     seen_both = s.seen_both, sed_fade = s.sed_fade, sed_fade_drive = LBA.SEDFADE_DRIVE[], body_flag = bf)
        push!(out, m0 in o.acting ? "m0" : any(m -> b.patch[m] <= 2, o.acting) ? "patch" : "none")
    end
    out   # [the winner with old[rb] true, with false]: "m0" / "patch" / "none"
end
LBA.CLAMP[] = (st, y) -> (h = HOOK[]; h === nothing || (S = h.s.side[st]; PRE[] = (active = copy(S.c.active), rev = h.flip && st === h.st ? reversal(h.s, S, y) : nothing)); (y, nothing))
LBA.ON_STEP[] = (st, o, c, y) -> (h = HOOK[]; (h === nothing || st !== h.st) || push!(h.recs, merge(facts(h.s.b, PRE[].active, o, c), Dict("t" => st.t + 1, "rev" => PRE[].rev))))

"""n updates from `snap` (nothing = the trial's initial state); `flip` computes the reversal; `restoff`, `clampv` (rb's reading)."""
function go(s, p, sch, snap, t0, n; flip = false, restoff = false, clampv = nothing, keepsnaps = false)
    st, S = snap === nothing ? (x = AS.initial_state(s, p); (x, s.side[x])) : deepcopy(snap); s.side[st] = S
    recs = Any[]; snaps = Dict{Int,Any}(); after = Bool[]; death = nothing
    HOOK[] = (s = s, st = st, flip = flip, recs = recs)
    LBA.REST_OFF[] = restoff ? (st_ -> st_ === st) : nothing
    LBA.BODY_CLAMP[] = clampv === nothing ? nothing : (st_ -> st_ === st ? clampv : nothing)
    for τ in t0+1:t0+n
        k = length(recs)
        AS.step!(st, s, p, sch, Set{Int}())
        length(recs) == k && push!(recs, nothing)
        a = alive(s, st); push!(after, a); (!a && death === nothing) && (death = τ)
        keepsnaps && a && τ % WL == 0 && (snaps[τ] = deepcopy((st, S)))
    end
    HOOK[] = nothing; LBA.REST_OFF[] = nothing; LBA.BODY_CLAMP[] = nothing; delete!(s.side, st)
    (recs = recs, snaps = snaps, after = after, death = death)
end
pa(r) = r === nothing ? 0 : r["patch_acts"]
m0a(r) = r !== nothing && r["m0_act"]

function windows_RB(s, p, sch, main)
    wins = Any[]
    for w in 1:NW
        lo = (w - 1) * WL; rng = lo+1:lo+WL
        snap = lo == 0 ? nothing : get(main.snaps, lo, nothing)
        (lo > 0 && snap === nothing) && (push!(wins, Dict("w" => w, "dead_at_start" => true)); continue)
        T = go(s, p, sch, snap, lo, WL; clampv = true); F = go(s, p, sch, snap, lo, WL; clampv = false)
        R = go(s, p, sch, snap, lo, WL; restoff = true)
        Aw = sum(pa, main.recs[rng]); livew = all(main.after[rng]) && all(r -> r !== nothing, main.recs[rng])
        push!(wins, Dict("w" => w, "dead_at_start" => false, "A" => Aw, "A_release" => sum(pa, R.recs), "alive" => livew,
                         "m0_true" => count(m0a, T.recs), "m0_false" => count(m0a, F.recs), "A_true" => sum(pa, T.recs), "A_false" => sum(pa, F.recs),
                         "m0_acts" => count(m0a, main.recs[rng])))
    end
    wins
end

res = Dict{String,Any}("spec" => "discussion/specs/S34-body-rest2.md r1", "rule" => "sf", "seeds" => SEEDS, "gseed" => GSEED, "H" => H,
                       "arms" => String.(ARMS), "N0" => Any[], "RA" => Any[], "RB" => Any[], "raising" => Any[])
su = LBA.setup_with(H); p = su.params
g = org(GSEED, su, :std; rest = true, rest_body = :B); sch1 = su.survival[1]
strip(rs) = [r === nothing ? nothing : Dict(k => v for (k, v) in r if k != "rev") for r in rs]
x1 = go(g, p, sch1, nothing, 0, H; flip = true); x2 = go(g, p, sch1, nothing, 0, H; flip = true); x3 = go(g, p, sch1, nothing, 0, H)
res["G2_repeat"] = isequal(x1.recs, x2.recs)
res["G3_flip_does_not_touch_main"] = isequal(strip(x1.recs), strip(x3.recs))
LBA.BODY_CLAMP[] = nothing
function go_nat(s)
    st = AS.initial_state(s, p); recs = Any[]
    HOOK[] = (s = s, st = st, flip = false, recs = recs); LBA.BODY_CLAMP[] = st_ -> LBA.body_quantity(s.side[st_].w) >= s.side[st_].Q0
    for t in 1:H; AS.step!(st, s, p, sch1, Set{Int}()); end
    HOOK[] = nothing; LBA.BODY_CLAMP[] = nothing; delete!(s.side, st); recs
end
gn = go_nat(g); res["G4_clamp_natural_equals_nothing"] = isequal(gn, [r for r in x3.recs if r !== nothing])
println("G2 ", res["G2_repeat"], " G3 ", res["G3_flip_does_not_touch_main"], " G4 ", res["G4_clamp_natural_equals_nothing"])
for seed in SEEDS, arm in ARMS
    sN = org(seed, su, arm); sA = org(seed, su, arm; rest = true, rest_body = :A); sB = org(seed, su, arm; rest = true, rest_body = :B)
    for (lin, s) in (("RA", sA), ("RB", sB))
        R = raising(s, seed, arm, lin == "RA" ? :A : :B)
        push!(res["raising"], Dict("lineage" => lin, "seed" => seed, "arm" => String(arm), "same" => R.same, "steps" => R.recs))
    end
    for sch in su.survival
        n = go(sN, p, sch, nothing, 0, H)
        push!(res["N0"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "death" => n.death, "A_total" => sum(pa, n.recs)))
        a = go(sA, p, sch, nothing, 0, H)
        push!(res["RA"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "death" => a.death, "steps" => a.recs, "A_total" => sum(pa, a.recs)))
        b = go(sB, p, sch, nothing, 0, H; flip = true, keepsnaps = true)
        wb = windows_RB(sB, p, sch, b)
        push!(res["RB"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "death" => b.death, "steps" => b.recs, "windows" => wb, "A_total" => sum(pa, b.recs)))
        println("seed=$seed $arm $(rpad(sch.name, 11)) N0 death $(n.death)  RA death $(a.death) m0 $(count(m0a, a.recs))  RB death $(b.death) m0 $(count(m0a, b.recs)) rev $(count(r -> r !== nothing && (r["rev"][1] == "m0") != (r["rev"][2] == "m0"), b.recs))")
    end
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-rest2.json"))
write(out, JSON.json(res))
println("written ", out)
