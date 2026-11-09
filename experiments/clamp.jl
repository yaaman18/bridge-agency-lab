# S12 (spec discussion/specs/S12-body-clamp.md r2): the sense and answer channels separated (D3a CLAMP). Q-A (series A, B
# with the identity control), Q-B (alpha check in two levels, near threshold), Q-C (types, answer change, latency).
# Writes experiments/results-clamp.json. Predictions: predictions-clamp.md (frozen before the first run).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, split(get(ENV, "SEEDS", join(51:60, ",")), ","))
const H = 392
const ARMS = Symbol.(split(get(ENV, "ARMS", "std,swap"), ","))
const NAMED = get(ENV, "NAMED", "1") == "1"
const EXTRAS = get(ENV, "EXTRAS", "1") == "1"
const W = 15
const COUPLED = ["r1", "r2", "r3", "r4", "r7", "r8"]
const RECEPTORS = ["r$i" for i in 1:8]
const DECLARED = Dict("m1" => Set(["r1", "r3", "r7", "r8"]), "m2" => Set(["r2", "r4", "r7", "r8"]))

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
                                 contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015)
const SINK = Ref{Any}(nothing)
LBA.ON_STEP[] = (st, o, c, y) -> (SINK[] === nothing || SINK[](st, o, c, y))
const CLAMPS = IdDict{Any,Any}()   # AS state -> (st, y) -> (y_sense, y_offer)
LBA.CLAMP[] = (st, y) -> haskey(CLAMPS, st) ? CLAMPS[st](st, y) : (y, nothing)
alive(s, st) = !isempty(LBA.body_sites(s.side[st].w))
units(s, names) = Set{Int}(LC.unit(s.b, n) for n in names)
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

"""A branch from the snapshot at t for n updates. `sil(τ)`; `swap_pool`; `pool_set` = (k, value) set before t+1;
`yoke` = (sense, answer, yN) with yN the real yields N read at t+1..t+n. Records per update: acting patches, motors, real y, d."""
function branch(s, p, sch, snap, t, n, sil; swap_pool = false, pool_set = nothing, yoke = nothing)
    st, S = deepcopy(snap); s.side[st] = S
    swap_pool && (S.pool .= reverse(S.pool))
    pool_set === nothing || (S.pool[pool_set[1]] = pool_set[2])
    if yoke !== nothing
        sense, answer, yN = yoke
        CLAMPS[st] = (st_, y) -> (i = st_.t - t + 1; (sense ? yN[i] : y, answer ? yN[i] : y))
    end
    rec = Any[]; dead = false; after = Any[]
    SINK[] = (st_, o, c, y) -> st_ === st && push!(rec, (acts = Set(s.b.patch[m] for m in o.acting if s.b.patch[m] <= 2), motors = Set(o.acting), y = copy(y), d = copy(o.d)))
    for τ in t+1:t+n
        k = length(rec)
        AS.step!(st, s, p, sch, sil(τ))
        length(rec) == k && push!(rec, (acts = Set{Int}(), motors = Set{Int}(), y = nothing, d = nothing))
        alive(s, st) || (dead = true)
        push!(after, (recep = Dict(r => S.c.active[LC.unit(s.b, r)] for r in RECEPTORS), pool = copy(S.pool)))
    end
    out = (rec = rec, dead = dead, after = after, cs = cstate(S.c), noise = rngstate(S.noise), pool0 = nothing)
    SINK[] = nothing; delete!(CLAMPS, st); delete!(s.side, st)
    out
end
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
function shift(N, Z, schN, schZ, t)
    a, b = hl(N.rec, schN, t), hl(Z.rec, schZ, t)
    (a.n == 0 || b.n == 0) ? "undetermined" : (a.h > a.l && b.h > b.l) ? "holds" : "fails"
end
Dacts(N, Z) = count(i -> N.rec[i].acts != Z.rec[i].acts, eachindex(N.rec))

"""Q-A at t, one series (sil0 = the silenced set of every branch from t+1)."""
function qa(s, p, sch, snap, t, sil0)
    schZ = swapped(sch); sil = τ -> sil0
    N = branch(s, p, sch, snap, t, W, sil)
    yN = [r.y for r in N.rec]
    Zs = Dict("o" => branch(s, p, schZ, snap, t, W, sil; swap_pool = true))
    N.dead || any(y -> y === nothing, yN) || for (k, se, an) in (("i", true, false), ("ii", false, true), ("iii", true, true))
        Zs[k] = branch(s, p, schZ, snap, t, W, sil; swap_pool = true, yoke = (se, an, yN))
    end
    common = !N.dead && length(Zs) == 4 && all(!z.dead for z in values(Zs))
    common || return (common = false, N = N, Zs = Zs)
    res = Dict(k => Dict("shift" => shift(N, z, sch, schZ, t), "D" => Dacts(N, z)) for (k, z) in Zs)
    ident = [r.motors for r in Zs["iii"].rec] == [r.motors for r in N.rec] && isequal(Zs["iii"].cs, N.cs)   # all acting units, and every field of CState (codex I-R P4)
    (common = true, res = res, identity = ident, N = N, Zs = Zs)
end

"""Q-B at t for motor m: one-step alpha check in two levels (pool, y, receptors); `nt` puts m's pool at 3U first."""
function qb(s, p, sch, snap, t, mname; nt = false)
    m = LC.unit(s.b, mname); pk = s.b.patch[m]; ps = nt ? (pk, 3 * s.U) : nothing
    C = branch(s, p, sch, snap, t, 2, τ -> Set{Int}(); pool_set = ps)
    B = branch(s, p, sch, snap, t, 2, τ -> τ == t + 1 ? Set([m]) : Set{Int}(); pool_set = ps)
    (length(C.rec) == 2 && C.rec[2].y !== nothing && B.rec[2].y !== nothing && !C.dead && !B.dead) || return (usable = false, why = "short or dead")   # codex I-R P6
    m in C.rec[1].motors || return (usable = false, why = "m did not act at t+1")
    setdiff(C.rec[1].motors, [m]) == setdiff(B.rec[1].motors, [m]) || return (usable = false, why = "other acts differ")
    C.after[1].pool[3-pk] == B.after[1].pool[3-pk] || return (usable = false, why = "other pool differs")
    C.noise == B.noise || return (usable = false, why = "noise state differs")
    diff = [r for r in RECEPTORS if C.after[2].recep[r] != B.after[2].recep[r]]
    feat(y) = (y[pk] >= 3, y[pk] == 0, y[1] > y[2], y[2] > y[1])
    (usable = true, why = "", pool_diff = B.after[1].pool[pk] - C.after[1].pool[pk], y1 = (C.rec[1].y, B.rec[1].y), y2 = (C.rec[2].y, B.rec[2].y),
     saturated = C.rec[2].y[pk] == 5 && B.rec[2].y[pk] == 5, crossed = feat(C.rec[2].y) != feat(B.rec[2].y), diff = diff,
     mismatch = [r for r in diff if !(r in DECLARED[mname]) && r in COUPLED], realized = [r for r in diff if r in DECLARED[mname]])
end

"""Q-C at t: type of m*, the condition V (Z with the sense channel yoked to N, answers and pools real)."""
function qc(s, p, sch, snap, t, N)
    schZ = swapped(sch)
    cnt = Dict(k => count(r -> k in r.acts, N.rec) for k in (1, 2))
    mstar = cnt[1] == cnt[2] ? nothing : (cnt[1] > cnt[2] ? 1 : 2)
    mstar === nothing && return Dict("type" => "other", "why" => "tie or no acts")
    g1, g2 = AS.yield_of(schZ, 1, t), AS.yield_of(schZ, 2, t)
    g1 == g2 && return Dict("type" => "other", "why" => "Z schedule tie at t+1")
    hiZ = g1 > g2 ? 1 : 2
    hiZ == mstar && return Dict("type" => "excluded", "why" => "Z's high patch is m*'s")
    st, S = snap; mu = LC.unit(s.b, "m$mstar")
    ks = [k for (k, (a, c, _)) in enumerate(s.edges) if c == mu && s.b.kind[a] == 'R']
    ty = any(k -> S.c.q[k] >= 1, ks) ? "q" : any(k -> S.c.sg[k] >= 1, ks) ? "sg" : "other"
    yN = [r.y for r in N.rec]
    any(y -> y === nothing, yN) && return Dict("type" => ty, "why" => "N died")
    V = branch(s, p, schZ, snap, t, W, τ -> Set{Int}(); swap_pool = true, yoke = (true, false, yN))
    V.dead && return Dict("type" => ty, "why" => "V died")
    dval = [r.d for r in V.rec] != [r.d for r in N.rec]; dpos = [r.d .> 0 for r in V.rec] != [r.d .> 0 for r in N.rec]
    lat = findfirst(r -> hiZ in r.acts, V.rec)
    Dict("type" => ty, "why" => "", "m_star" => mstar, "answer_d_differs" => dval, "answer_sign_differs" => dpos,
         "latency" => lat === nothing ? 15 : lat, "switched" => lat !== nothing)
end

function run_one(s, p, sch)
    snaps = main_run(s, p, sch); ev = Any[]
    Cp = units(s, COUPLED)
    for t in sort(collect(keys(snaps)))
        A = qa(s, p, sch, snaps[t], t, Set{Int}()); Bq = qa(s, p, sch, snaps[t], t, Cp)
        e = Dict{String,Any}("t" => t, "A_common" => A.common, "B_common" => Bq.common)
        A.common && (e["A"] = A.res; e["A_identity"] = A.identity)
        Bq.common && (e["B"] = Bq.res; e["B_identity"] = Bq.identity)
        for nt in (false, true), mn in ("m1", "m2")
            x = qb(s, p, sch, snaps[t], t, mn; nt)
            e["QB_$(nt ? "nt" : "one")_$mn"] = Dict(String(k) => v for (k, v) in pairs(x))
        end
        e["QC"] = qc(s, p, sch, snaps[t], t, A.N)
        push!(ev, e)
    end
    ev
end

res = Dict{String,Any}("spec" => "discussion/specs/S12-body-clamp.md r2", "rule" => "sf", "seeds" => SEEDS, "H" => H, "arms" => String.(ARMS), "runs" => Any[], "named" => Any[])
su = LBA.setup_with(H); p = su.params
if EXTRAS   # (i) explicit y_offer = y equals the default; (iii) repeat; (iv) seed 1 is outside the claim seeds
    s = org(1, su, :std); sch = su.survival[1]
    endst(f) = (st = AS.initial_state(s, p); f === nothing || (CLAMPS[st] = f);
                for _ in 1:H; AS.step!(st, s, p, sch, Set{Int}()); end; x = (cstate(s.side[st].c), copy(s.side[st].pool)); delete!(CLAMPS, st); delete!(s.side, st); x)
    i_ok = isequal(endst(nothing), endst((st, y) -> (y, y)))
    r1 = run_one(org(1, su, :std), p, sch); r2 = run_one(org(1, su, :std), p, sch)
    res["controls"] = Dict("i_explicit_y_offer_equals_default" => i_ok, "iii_repeat" => isequal(r1, r2))
    res["controls_ok"] = i_ok && isequal(r1, r2)
    println("controls ", res["controls"])
end
todo = vec([(seed, arm, sch, false) for seed in SEEDS, arm in ARMS, sch in su.survival])
NAMED && append!(todo, [(seed, arm, su.survival[2], true) for seed in (35, 37) for arm in (:swap, :std)])
for (seed, arm, sch, named) in todo
    t0 = time(); ev = run_one(org(seed, su, arm), p, sch)
    push!(named ? res["named"] : res["runs"], Dict("seed" => seed, "arm" => String(arm), "schedule" => sch.name, "events" => ev))
    idA = [e["A_identity"] for e in ev if e["A_common"]]; idB = [e["B_identity"] for e in ev if e["B_common"]]
    println("seed=$seed $arm $(rpad(sch.name, 11))$(named ? " [named]" : "") commonA $(length(idA)) idA $(all(idA)) commonB $(length(idB)) idB $(all(idB)) ",
            "A(ii) shift $(count(e -> e["A_common"] && e["A"]["ii"]["shift"] == "holds", ev)) B(o) shift $(count(e -> e["B_common"] && e["B"]["o"]["shift"] == "holds", ev)) ($(round(time() - t0; digits = 1)) s)")
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-clamp.json"))
write(out, JSON.json(res, 2))
println("written ", out)
