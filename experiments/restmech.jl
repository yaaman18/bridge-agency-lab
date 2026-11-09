# S40 (spec discussion/specs/S40-rb-restmech.md r1): why m0 wins after the exchange Z on RB :swap (S39). Branches from
# the same state at t (after update t, before the input of t+1): N, Z (schedule and pools exchanged, S39), ZM (Z and
# the circuit state mirrored by μ: r1<->r2, r3<->r4, r7<->r8, c1<->c2, m1<->m2; r5, r6, m0, rb fixed). Per update of each
# branch: the input y, old (the units on before the update), the driven edges, the candidates after the core gate,
# conf / habit / total / key of every motor, lastM and the idle set, pref / win, the act, and how the choice was decided.
# Gates: μ is an involution that preserves the wiring; mirroring twice restores the state; one-update equivariance.
# Writes experiments/results-rb-restmech.json. Predictions: predictions-rb-restmech.md (frozen before the claim seeds).
include(joinpath(@__DIR__, "variant_horizon.jl"))
using .LabBodyAgency, JSON
const LBA = LabBodyAgency
const LC = LBA.LC
const LAB = normpath(joinpath(@__DIR__, ".."))

const SEEDS = parse.(Int, filter(!isempty, split(get(ENV, "SEEDS", join(471:480, ",")), ",")))
const H = 392
const W = 15
const MU = Dict("r1" => "r2", "r2" => "r1", "r3" => "r4", "r4" => "r3", "r7" => "r8", "r8" => "r7", "c1" => "c2", "c2" => "c1", "m1" => "m2", "m2" => "m1")
const FEATMU = Dict(1 => 2, 2 => 1, 3 => 4, 4 => 3, 7 => 8, 8 => 7)   # FEATURES: y1>=3/y2>=3, y1==0/y2==0, y1>y2/y2>y1

org(seed, su, cur) = LBA.BodyOrg(seed; structure = :constituents, abundant_r0 = su.choice_params.resource0, idle_first = true,
    contrast = :bin3, cur = cur, core_gate = true, sed_fade = true, KC_trial = 0.0015, rest = true, rest_body = :B)
swapped(sch) = AS.Schedule(sch.name * "-swap", reverse(sch.first), reverse(sch.second), sch.switch)

# ---------------------------------------------------------------- μ on units and edges
umap(b) = [LC.unit(b, get(MU, b.names[u], b.names[u])) for u in eachindex(b.names)]
function emap(b)
    um = umap(b)
    [only([k2 for k2 in eachindex(b.edges) if b.edges[k2][1] == um[b.edges[k][1]] && b.edges[k2][2] == um[b.edges[k][2]]]) for k in eachindex(b.edges)]
end
"""μ preserves the wiring: an involution on units and edges, with kind, theta, patch (1<->2), features, weights and q0 carried."""
function mu_ok(b)
    um = umap(b); em = emap(b)
    pm(p) = p == 1 ? 2 : p == 2 ? 1 : p
    all(u -> um[um[u]] == u && b.kind[um[u]] == b.kind[u] && b.theta[um[u]] == b.theta[u] && b.patch[um[u]] == pm(b.patch[u]) &&
             (b.kind[u] != 'R' || b.feat[um[u]] == get(FEATMU, b.feat[u], b.feat[u])), eachindex(b.names)) &&
    all(k -> em[em[k]] == k && b.edges[em[k]][3] == b.edges[k][3] && b.q0[em[k]] == b.q0[k], eachindex(b.edges)) &&
    b.perm == collect(eachindex(b.perm))
end
const EDGEF = (:q, :sg, :h, :cOn, :cOff, :lastC)
const UNITF = (:active, :off, :prev, :lastM)
"""The circuit state mirrored: new[μ(x)] = old[x] for every per-edge and per-unit field; the rest is kept."""
function mirror_c(b, c)
    um = umap(b); em = emap(b); d = deepcopy(c)
    for f in EDGEF; v = getfield(c, f); v === nothing && continue; w = getfield(d, f); for k in eachindex(v); w[em[k]] = v[k]; end; end
    for f in UNITF; v = getfield(c, f); v === nothing && continue; w = getfield(d, f); for u in eachindex(v); w[um[u]] = v[u]; end; end
    isempty(c.pend) || error("pend not empty (BODY has no call motor)")
    d
end
"""A branch state (st, S) mirrored: the circuit by μ, st.active by μ, the pools exchanged (the world's two patches)."""
function mirror_state(s, snap)
    st, S = deepcopy(snap); um = umap(s.b)
    S2 = merge(S, (c = mirror_c(s.b, S.c), pool = reverse(S.pool)))
    a = copy(st.active); for u in eachindex(a); a[um[u]] = st.active[u]; end
    st2 = AS.State(a, copy(st.strength), st.resource, st.t, st.dead)
    (st2, S2)
end

# ---------------------------------------------------------------- the decision record of one update
const PRE = Ref{Any}(nothing); const POST = Ref{Any}(nothing); const WATCH = Ref{Any}(nothing)
LBA.CLAMP[] = (st, y) -> (st === WATCH[] && (S = LBA_side(st); PRE[] = (q = copy(S.c.q), sg = copy(S.c.sg), old = copy(S.c.active), lastM = S.c.lastM === nothing ? nothing : copy(S.c.lastM), t = S.c.t, y = copy(y))); (y, nothing))
LBA.ON_STEP[] = (st, o, c, y) -> (st === WATCH[] && (POST[] = (acting = copy(o.acting), drove = copy(o.drove), choice = o.choice)))
const SREF = Ref{Any}(nothing)
LBA_side(st) = SREF[].side[st]
function decision(s, pre, post)
    b = s.b; motors = [u for u in eachindex(b.names) if b.kind[u] == 'M']
    conf = Dict(m => 0 for m in motors); habit = Dict(m => 0 for m in motors); total = Dict(m => 0 for m in motors)
    for (k, (a, c, w)) in enumerate(b.edges)
        b.kind[c] == 'M' && post.drove[k] || continue
        total[c] += w; pre.q[k] >= 1 ? (conf[c] += w) : pre.sg[k] >= 1 && (habit[c] += w)
    end
    on = Dict(m => total[m] >= b.theta[m] && any(k -> post.drove[k] && b.kind[b.edges[k][1]] == 'C', b.ins[m]) for m in motors)   # core_gate
    cand = sort([m for m in motors if on[m]])
    key(m) = conf[m] * 1_000_000 + habit[m] * 1_000 + total[m]
    now = pre.t + 1
    idl = pre.lastM === nothing ? Int[] : [m for m in cand if now - pre.lastM[m] > LC.FORGET]
    pool0 = isempty(idl) ? cand : idl
    how = if length(cand) <= 1
        isempty(cand) ? "no candidate" : "single candidate"
    else   # as core/circuit.jl:155–169: the idle ones first (if any), the largest key, then old, then the smallest patch number
        best = maximum(key, pool0); tied = [m for m in pool0 if key(m) == best]
        pv = [m for m in tied if pre.old[m]]; px = isempty(pv) ? tied : pv
        length(tied) == 1 ? (isempty(idl) ? "key" : "idle, then key") : length(px) == 1 ? "tie on key, decided by old" : "tie on key and old, decided by patch number"
    end
    nm(m) = b.names[m]
    # self-check against the circuit's own record (codex V1 9): the candidates of choice, and the act among them
    ok = (post.choice === nothing ? length(cand) <= 1 : sort(post.choice.cand) == cand) && all(m -> m in cand, post.acting)
    # codex I-R 2 #2: only a patch-number decision between m1 and m2 breaks μ (between m1 and m0 it commutes: 1 < 4 and 2 < 4)
    pxf = length(cand) <= 1 ? Int[] : (best = maximum(key, pool0); tied = [m for m in pool0 if key(m) == best]; pv = [m for m in tied if pre.old[m]]; isempty(pv) ? tied : pv)
    tie12 = how == "tie on key and old, decided by patch number" && any(m -> b.patch[m] == 1, pxf) && any(m -> b.patch[m] == 2, pxf)
    Dict("y" => pre.y[1:2], "old" => [nm(m) for m in motors if pre.old[m]], "cand" => nm.(cand), "idle" => nm.(idl),
         "conf" => Dict(nm(m) => conf[m] for m in motors), "habit" => Dict(nm(m) => habit[m] for m in motors), "total" => Dict(nm(m) => total[m] for m in motors),
         "pref" => post.choice === nothing ? nothing : nm(post.choice.pref), "win" => post.choice === nothing ? nothing : nm(post.choice.win),
         "act" => isempty(post.acting) ? "none" : join(sort(nm.(post.acting)), ","), "how" => how, "tie_by_patch" => tie12, "selfcheck" => ok)
end
"""A branch of W updates from the state (st, S) with schedule sch: the decision record of each update."""
branch(s, p, sch, snap) = branch_n(s, p, sch, snap, W)
mu_act(a) = a in ("m1", "m2") ? MU[a] : a
"""Equivariance of one update: mirror(step(X)) == step(mirror(X)) with the mirrored schedule (codex V1 8)."""
function equiv_one(s, p, sch, snap)
    r1, X1 = branch_n(s, p, sch, snap, 1); r2, X2 = branch_n(s, p, swapped(sch), mirror_state(s, snap), 1)
    A = mirror_state(s, X1)
    same = states_equal(A, X2)
    (same = same, tie = r1[1]["act"] != "dead" && r1[1]["tie_by_patch"] || r2[1]["act"] != "dead" && r2[1]["tie_by_patch"])
end
"""codex I-R 2 #3, #4: the whole state: AS.State (active, strength, resource, t, dead) and every side field (circuit, world,
noise, pools, Q0), compared structurally."""
states_equal(A, B) = all(f -> LBA_deq(getfield(A[1], f), getfield(B[1], f)), fieldnames(typeof(A[1]))) &&
                     keys(A[2]) == keys(B[2]) && all(k -> LBA_deq(A[2][k], B[2][k]), keys(A[2]))
"""Negative controls of states_equal: one side changed in one field group at a time must be detected."""
function states_equal_negtests(snap)
    base = deepcopy(snap); out = Dict{String,Bool}()
    pert = [("c.q", x -> (x[2].c.q[end] += 1)), ("noise", x -> (x[2].noise.s += UInt32(1))), ("pool", x -> (x[2].pool[1] += 0.5)),
            ("world", x -> (x[2].w.A[1] += 0.25)), ("st.t", x -> (x[1].t += 1)), ("st.strength", x -> (x[1].strength[1] = 1 - x[1].strength[1])),
            ("c.lastM", x -> (x[2].c.lastM[end] += 1)), ("st.active", x -> (x[1].active[1] = !x[1].active[1]))]
    out["same_itself"] = states_equal(base, deepcopy(snap))
    for (n, f) in pert; y = deepcopy(snap); f(y); out[n] = !states_equal(base, y); end
    out
end
"""n updates from a copy of the state (st, S): the decision records and a copy of the state after them."""
function branch_n(s, p, sch, snap, n)
    st, S = deepcopy(snap); s.side[st] = S; WATCH[] = st; SREF[] = s
    recs = Any[]
    for _ in 1:n
        PRE[] = nothing; POST[] = nothing
        AS.step!(st, s, p, sch, Set{Int}())
        push!(recs, (PRE[] === nothing || POST[] === nothing) ? Dict("act" => "dead") : decision(s, PRE[], POST[]))
    end
    WATCH[] = nothing; out = deepcopy((st, S)); delete!(s.side, st)
    recs, out
end
LBA_deq(a, b) = typeof(a) == typeof(b) && (a isa AbstractArray ? (size(a) == size(b) && all(LBA_deq(x, y) for (x, y) in zip(a, b))) :
    (isstructtype(typeof(a)) && !(a isa Number || a isa AbstractString || a isa Symbol || a isa Tuple)) ? all(f -> LBA_deq(getfield(a, f), getfield(b, f)), fieldnames(typeof(a))) : isequal(a, b))

function main_run(s, p, sch)
    st = AS.initial_state(s, p); snaps = Dict{Int,Any}(); every = Any[]
    for t in 1:H
        AS.step!(st, s, p, sch, Set{Int}())
        alive = !isempty(LBA.body_sites(s.side[st].w))
        alive && t % 32 == 0 && (snaps[t] = deepcopy((st, s.side[st])))
        alive && t % 8 == 4 && push!(every, deepcopy((st, s.side[st])))   # states for the equivariance gate (every 8 updates)
    end
    delete!(s.side, st)
    snaps, every
end

res = Dict{String,Any}("spec" => "discussion/specs/S40-rb-restmech.md r1", "rule" => "rb", "seeds" => SEEDS, "H" => H, "W" => W, "arm" => "swap", "runs" => Any[])
su = LBA.setup_with(H); p = su.params
let s1 = org(1, su, :swap), (sn, ev1) = main_run(s1, p, su.survival[1])   # seed 1 (outside the claim seeds): the comparator's negative controls
    res["states_equal_negtests"] = states_equal_negtests(sn[minimum(keys(sn))])
    println("states_equal negative controls ", res["states_equal_negtests"])
    # codex I-R 3 #2: tie12 from the decision rule itself on built inputs (not set by hand): m1 and m2 tied on key and both old
    # -> true; m1 and m0 tied (m2 lower) -> false
    b = s1.b; ne = length(b.edges); u(n) = LC.unit(b, n); e(a, c) = only([k for k in 1:ne if b.edges[k][1] == u(a) && b.edges[k][2] == u(c)])
    mk(drv, oldon) = (pre = (q = fill(1, ne), sg = zeros(Int, ne), old = [b.names[x] in oldon for x in eachindex(b.names)], lastM = zeros(Int, length(b.names)), t = 10, y = [3.0, 3.0]),
                      post = (acting = Int[], drove = [k in drv for k in 1:ne], choice = nothing))
    x1 = mk(Set([e("c1", "m1"), e("r1", "m1"), e("c2", "m2"), e("r2", "m2"), e("c1", "m0")]), ["m1", "m2"])
    x2 = mk(Set([e("c1", "m1"), e("r1", "m1"), e("c2", "m2"), e("c1", "m0"), e("c2", "m0")]), ["m1", "m0"])
    d1 = decision(s1, x1.pre, x1.post); d2 = decision(s1, x2.pre, x2.post)
    res["tie12_unit"] = Dict("m1_m2_tie" => d1["tie_by_patch"] && d1["how"] == "tie on key and old, decided by patch number",
                             "m1_m0_tie" => !d2["tie_by_patch"] && d2["how"] == "tie on key and old, decided by patch number")
    println("tie12 unit tests ", res["tie12_unit"], " ", d1["how"], " / ", d2["how"])
end
for seed in SEEDS
    s = org(seed, su, :swap)
    res["mu_wiring_ok"] = get(res, "mu_wiring_ok", true) && mu_ok(s.b)
    for sch in su.survival
        snaps, every = main_run(s, p, sch)
        inv = all(x -> (y = mirror_state(s, mirror_state(s, x)); LBA_deq(y[2].c, x[2].c) && y[2].pool == x[2].pool && y[1].active == x[1].active), every)
        eq = [equiv_one(s, p, sch, x) for x in every]
        events = Any[]
        for t in sort(collect(keys(snaps)))
            N, _ = branch(s, p, sch, snaps[t])
            Zs = deepcopy(snaps[t]); Zs[2].pool .= reverse(Zs[2].pool)      # Z as S39: the pools exchanged at t, the schedule swapped from t+1
            Z, _ = branch(s, p, swapped(sch), Zs)
            ZM, _ = branch(s, p, swapped(sch), mirror_state(s, snaps[t]))   # mirror_state also exchanges the pools
            push!(events, Dict("t" => t, "N" => N, "Z" => Z, "ZM" => ZM))
        end
        push!(res["runs"], Dict("seed" => seed, "schedule" => sch.name, "involution_ok" => inv, "equiv" => [Dict("same" => e.same, "tie" => e.tie) for e in eq], "events" => events))
        cnt(f) = sum(e -> count(r -> r["act"] == "m0", e[f]), events; init = 0)
        println("seed=$seed $(rpad(sch.name, 11)) inv=$inv equiv $(count(e -> e.same, eq))/$(length(eq)) (ties $(count(e -> e.tie, eq))) points $(length(events)) m0 N $(cnt("N")) Z $(cnt("Z")) ZM $(cnt("ZM"))")
    end
end
out = get(ENV, "OUT", joinpath(LAB, "experiments", "results-rb-restmech.json"))
write(out, JSON.json(res)); println("written ", out)
