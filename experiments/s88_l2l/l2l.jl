# S88 two-layer learner L2L-T vs L-FGT on the flip trace (discussion/specs/S88-draft-two-layer-trace.md; predictions frozen;
# codex S-R 2026-11-27 P1-P8; learner spec discussion/specs/L2L-draft-two-layer-learner.md). Seen 48 lives only; no new seeds;
# law numbers unchanged; capacity C = infinity (nothing is evicted). Includes s87_contents/contents.jl unchanged (and through it s84 ...).
# usage: julia --project=. -t 8 experiments/s88_l2l/l2l.jl [smoke|run]
include(joinpath(@__DIR__, "..", "s87_contents", "contents.jl"))
const PRED88 = joinpath(@__DIR__, "predictions.toml"); const OUT88 = joinpath(@__DIR__, "out"); mkpath(OUT88)
const FREEZE88 = joinpath(@__DIR__, "..", "freeze-s88.txt")
const GR88 = ("F", "R", "C")

# ---- state: K = L-FGT counters (same update as update2!: decay then add); M = kept examples (never decayed) and their aggregates
mutable struct Cn; n::Vector{Float64}; n1::Vector{Float64}; rn::Vector{Float64}; rn1::Vector{Float64}; end
newcn() = Cn(zeros(2), zeros(2), zeros(NK), zeros(NK))
mutable struct Mem; list::Vector{NTuple{4,Int}}; m::Vector{Float64}; m1::Vector{Float64}; ma::Vector{Float64}; ma1::Vector{Float64}; end
newmem() = Mem(NTuple{4,Int}[], zeros(NK), zeros(NK), zeros(2), zeros(2))
function kstep!(c::Cn, k, a, y, lam)
    if lam < 1; c.n .*= lam; c.n1 .*= lam; c.rn .*= lam; c.rn1 .*= lam; end
    c.n[a] += 1; c.n1[a] += y; c.rn[k] += 1; c.rn1[k] += y; return c
end
remember!(M::Mem, t, k, a, y) = (push!(M.list, (t, k, a, y)); M.m[k] += 1; M.m1[k] += y; M.ma[a] += 1; M.ma1[a] += y; M)
# O1: the L-FGT expression with M's counts added (weight 1). With M empty this is table! (s84) value for value.
o1(c::Cn, M::Mem, k) = (a = akey(k); rate = (c.n1[a] + M.ma1[a] + 1) / (c.n[a] + M.ma[a] + 2); clip((c.rn1[k] + M.m1[k] + ALPHA_R1 * rate) / (c.rn[k] + M.m[k] + ALPHA_R1)))
tab1(c, M) = [o1(c, M, k) for k in 1:NK]
r1(p, y) = (y == 1 && p < 0.5) || (y == 0 && p > 0.5)
r1ind(p, y) = (2 * Float64(y) - 1) * (2p - 1) < 0                  # independent form of R1 (G5, codex P7)
samec(c, d) = sameb(c.n, d.n) && sameb(c.n1, d.n1) && sameb(c.rn, d.rn) && sameb(c.rn1, d.rn1)
function recount_ok(M::Mem)                                          # G3
    m = zeros(NK); m1 = zeros(NK); ma = zeros(2); ma1 = zeros(2)
    for (t, k, a, y) in M.list; m[k] += 1; m1[k] += y; ma[a] += 1; ma1[a] += y; end
    sameb(m, M.m) && sameb(m1, M.m1) && sameb(ma, M.ma) && sameb(ma1, M.ma1)
end
tabl(c::Cn, lam) = TabL(copy(c.n), copy(c.n1), copy(c.rn), copy(c.rn1), lam)

# one step of an L2L-T branch: returns whether example t was kept (G5 checks R1 independently, every step)
function l2lstep!(c, M, t, k, a, y, lam)
    p = o1(c, M, k); kp = r1(p, y); kp == r1ind(p, y) || error("G5 R1 independent check t=$t")
    kstep!(c, k, a, y, lam); kp && remember!(M, t, k, a, y); return kp, p
end

function life88(x; tmax = typemax(Int))
    O = origins84(x); orig = Set{Int}(vcat([O[(g, h)] for g in GR88, h in HS84]...))
    R = replay84(x.lf, x.life, x.P, orig)                                   # S84 gates on the official law
    F = field87(x); qk = qkeys(F); N = min(F.N, tmax); K = F.K; A = F.A; Y = F.Y; lam = R.lam
    rd = Dict{Int,Set{Int}}(); for t0 in orig, h in HS84; t0 + h + 1 <= N && push!(get!(rd, t0, Set{Int}()), h); end
    need = Set{Int}(t0 + h + 1 for (t0, hs) in rd for h in hs); for t0 in keys(rd); t0 >= 1 && push!(need, t0); end
    cf = learner87("FGT", x.life); cf.lam == lam || error("lam"); c = newcn(); M = newmem(); kept = falses(N)
    Tm = Dict{Int,Vector{Float64}}(0 => tab1(newcn(), newmem())); St = Dict{Int,Tuple{Cn,Mem}}()
    0 in orig && (St[0] = (deepcopy(c), deepcopy(M)))
    sameb(tab1(c, newmem()), view(R.Tab, :, 1)) || error("G2 t=0")
    for t in 1:N
        kp, _ = l2lstep!(c, M, t, K[t], A[t], Y[t], lam); kept[t] = kp
        update2!(cf, x.lf, t:t, F.maps[F.seg[t]])                          # FGT side on the official law (codex I-R P2)
        samec(c, cf) || error("G1 main t=$t")
        sameb(tab1(c, newmem()), view(R.Tab, :, t + 1)) || error("G2 FGT/C=0 table t=$t")    # C = 0: M unused
        t in need && (Tm[t] = tab1(c, M))
        t in orig && (St[t] = (deepcopy(c), deepcopy(M)))
    end
    recount_ok(M) || error("G3 end of life")
    # G7: FGT O_Q (S87 obsQ through predict2) = table T read at qkeys, at birth and at the first origin
    for t in (0, minimum(orig))
        cc = t == 0 ? newcn() : R.st0[t] |> (q -> Cn(q...))
        sameb(obsQ(tabl(cc, lam), F), tab1(cc, newmem())[qk]) || error("G7 FGT O_Q = T[qk] t=$t")
    end
    rows = NamedTuple[]
    for t0 in sort!(collect(keys(rd)))
        hs = rd[t0]; hmax = maximum(hs); s = t0 + 1
        c0, M0 = St[t0]; cA = deepcopy(c0); MA = deepcopy(M0); cU = deepcopy(c0); MU = deepcopy(M0)
        fA = tabl(Cn(deepcopy(R.st0[t0])...), lam); samec(fA, c0) || error("FGT origin state t0=$t0")
        ps = o1(c0, M0, K[s]); keepT = false; keepM = kept[s]
        out = Dict{Int,NamedTuple}()
        for t in s:(t0 + hmax + 1)
            y = t == s ? 1 - Y[t] : Y[t]
            kp, _ = l2lstep!(cA, MA, t, K[t], A[t], y, lam); t == s && (keepT = kp)
            l2lstep!(cU, MU, t, K[t], A[t], Y[t], lam)
            upd!(fA, K[t], A[t], y)                                          # = update2! with the outcome given (S87 I-R P3)
            samec(cA, fA) || error("G1 twin t0=$t0 t=$t")
            h = t - s
            if h in hs
                tw = tab1(cA, MA); tu = tab1(cU, MU); tm = Tm[t]; ff = tab1(Cn(fA.n, fA.n1, fA.rn, fA.rn1), newmem()); fm = view(R.Tab, :, t + 1)
                sameb(tu, tm) || error("G4 unflipped twin t0=$t0 h=$h")
                recount_ok(MA) && recount_ok(MU) || error("G3 twin t0=$t0 h=$h")
                out[h] = (DL = l1(tm, tw), DF = l1(fm, ff), QL = dist(tm[qk], tw[qk]), QF = dist(fm[qk], ff[qk]),
                          NL = l1(Tm[t0], tm), GL = l1(tm, view(R.Tab, :, 1)), GF = l1(fm, view(R.Tab, :, 1)))
            end
        end
        if ps != 0.5
            xor(keepM, keepT) || error("G5 exactly one branch keeps s t0=$t0")
        else
            (!keepM && !keepT) || error("G5 p=1/2 keeps s t0=$t0")
        end
        push!(rows, (t0 = t0, ps = ps, keepM = keepM, keepT = keepT, out = out))
    end
    # E3 windows (S83): formation = formwin(i, L83) for selected switches; routine = routinewins(N, L83); unit (life, t) once per kind
    fset = Set{Int}(t for i in x.S for t in formwin(i, L83) if 1 <= t <= N); rset = Set{Int}(t for w in routinewins(x.N, L83) for t in w if 1 <= t <= N)
    e3 = (fk = count(t -> kept[t], fset), fn = length(fset), rk = count(t -> kept[t], rset), rn = length(rset))
    return (id = x.id, O = O, rows = rows, e3 = e3, nmem = length(M.list), N = N)
end

function smoke88()
    LV = lives83(); xs = [LV[1], LV[end]]
    io = IOBuffer()
    for x in xs
        r = life88(x; tmax = 12000)
        println(io, "smoke $(x.id) prefix $(r.N): gates G1-G5, G7 ok; origins twinned $(length(r.rows))")
    end
    s = String(take!(io)); print(s); write(joinpath(OUT88, "smoke.out"), s)
end

function frozen88()
    h = bytes2hex(sha256(read(PRED88))); any(==("$h  experiments/s88_l2l/predictions.toml"), split(read(FREEZE88, String), "\n"))
end
function parse_q(path, pat)                                         # quartile string after "D " on the line matching pat
    for ln in eachline(path); occursin(pat, ln) || continue; m = match(r"  D ([0-9.]+ / [0-9.]+ / [0-9.]+)", ln); m === nothing || return m[1]; end
    return nothing
end

function run88()
    frozen88() || error("predictions not frozen")
    LV = lives83(); length(LV) == 48 || error("48 lives")
    res = tmapv(life88, LV)
    io = IOBuffer()
    pool(g, h, f) = [f(r, row) for r in res for row in r.rows if row.t0 in r.O[(g, h)] && haskey(row.out, h)]
    exc(g, h) = sum(count(t0 -> t0 + h + 1 > r.N, r.O[(g, h)]) for r in res)
    # G6 / G7 against S86 / S87 printed quartiles (4 digits)
    for g in GR88, h in HS84
        qT = q3(pool(g, h, (r, w) -> w.out[h].DF)); qQ = q3(pool(g, h, (r, w) -> w.out[h].QF))
        e86 = parse_q(joinpath(@__DIR__, "..", "s86_bisim", "out", "bisim.out"), "  $g h=$h: n ")
        e87 = parse_q(joinpath(@__DIR__, "..", "s87_contents", "out", "contents.out"), "  FGT $g h=$h: n ")
        qT == e86 || error("G6 FGT T quartiles $g h=$h: $qT vs S86 $e86")
        qQ == e87 || error("G7 FGT Q quartiles $g h=$h: $qQ vs S87 $e87")
    end
    println(io, "gate: S84 gates on the official law; G1 L2L-T K = FGT counters bitwise on every main step and every twin step; G2 C=0 table = replay84 table bitwise on every step; G3 M aggregates = recount from the list (end of life, every twin read point); G4 unflipped L2L-T twin = main table; G5 R1 rechecked independently on every step of every branch, exactly one branch keeps s when p_s != 1/2, none when p_s = 1/2; G6 FGT D on T quartiles = S86 bisim.out; G7 FGT O_Q = T[qkeys] and FGT D on Q quartiles = S87 contents.out")
    println(io, "== D_s(s+h) per group (pooled; q1 / median / q3). T = L1 over 130 keys (S86 rule); Q = mean over 2000 probes (S87 rule). C = infinity.")
    for g in GR88, h in HS84
        v = pool(g, h, (r, w) -> w.out[h]); isempty(v) && continue
        println(io, "  $g h=$h: n $(length(v)) (excluded $(exc(g, h)))  T: FGT $(q3([a.DF for a in v]))  L2L $(q3([a.DL for a in v]))  L2L-FGT $(q3([a.DL - a.DF for a in v]))  L2L D=0: $(count(a -> a.DL == 0, v))  |  Q: FGT $(q3([a.QF for a in v]))  L2L $(q3([a.QL for a in v]))  L2L D=0: $(count(a -> a.QL == 0, v))  |  N_T L2L $(q3([a.NL for a in v]))  G_T FGT $(q3([a.GF for a in v])) L2L $(q3([a.GL for a in v]))")
    end
    # targets for E1/E2: (life, s) once, p_s != 1/2, s+1000 readable
    tg = [(r.id, w) for r in res for w in r.rows if w.ps != 0.5 && haskey(w.out, 1000) && any(g -> w.t0 in r.O[(g, 1000)], GR88)]
    allo = sum(length(Set(vcat([r.O[(g, 1000)] for g in GR88]...))) for r in res); half = count(w -> w.ps == 0.5, [w for r in res for w in r.rows])
    d = [w.out[1000].DL - w.out[1000].DF for (_, w) in tg]
    e1 = isempty(d) ? "undecidable" : mean(d) > 0 ? "hit" : "miss"
    z2 = count(((_, w),) -> w.out[1000].DL == 0, tg); e2 = isempty(tg) ? "undecidable" : z2 == 0 ? "hit" : "miss"
    km = count(((_, w),) -> w.keepM, tg)
    println(io, "E1: targets $(length(tg)) of $allo h=1000 origins (p_s = 1/2 origins overall: $half); mean paired difference D_L2L - D_FGT on T = $(round(isempty(d) ? NaN : mean(d), sigdigits = 4)) (quartiles $(q3(d))) -> $e1")
    println(io, "E2: targets with L2L-T D_s(s+1000) = 0 on T: $z2 / $(length(tg)) -> $e2   (s kept by main $km, by twin $(length(tg) - km))")
    fk = sum(r.e3.fk for r in res); fn = sum(r.e3.fn for r in res); rk = sum(r.e3.rk for r in res); rn = sum(r.e3.rn for r in res)
    e3 = (fn == 0 || rn == 0) ? "undecidable" : fk / fn > rk / rn ? "hit" : "miss"
    wins = count(r -> r.e3.fn > 0 && r.e3.rn > 0 && r.e3.fk / r.e3.fn > r.e3.rk / r.e3.rn, res)
    println(io, "E3: kept fraction formation $fk / $fn = $(round(fk / fn, digits = 4)), routine $rk / $rn = $(round(rk / rn, digits = 4)); lives with formation > routine $wins / $(length(res)) (not used for the verdict) -> $e3")
    println(io, "fragments at end of life (C = infinity): $(q3(Float64[r.nmem for r in res])); fraction of examples $(q3([r.nmem / r.N for r in res]))")
    println(io, "S88-E1: $e1"); println(io, "S88-E2: $e2"); println(io, "S88-E3: $e3")
    println(io, "note: seen lives only, C = infinity. D>0 witnesses s < t; D=0 is not a proof of forgetting. E1-E3 judged only at C = infinity (codex P1).")
    s = String(take!(io)); print(s); write(joinpath(OUT88, "l2l.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    (isempty(ARGS) || ARGS[1] == "run") ? run88() : ARGS[1] == "smoke" ? smoke88() : error("smoke|run")
end
