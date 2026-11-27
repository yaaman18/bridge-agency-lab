# S89 two-layer learner L2L-T at finite capacity with oldest-out eviction D1, and the N3 reverse-bias diagnosis
# (discussion/specs/S89-draft-l2l-finite-c-and-n3.md r2; predictions frozen in predictions.toml / freeze-s89.txt).
# Seen 48 lives only; no new seeds; law numbers unchanged; capacities C in {0, 1, 2, inf} (plan D1, decisions-log #89).
# Includes s88_l2l/l2l.jl unchanged (and through it s87 / s84 ...); its main block does not run when included.
# usage: julia --project=. -t 8 experiments/s89_l2l_d1/l2l_d1.jl [smoke|run]
include(joinpath(@__DIR__, "..", "s88_l2l", "l2l.jl"))
const PRED89 = joinpath(@__DIR__, "predictions.toml"); const OUT89 = joinpath(@__DIR__, "out"); mkpath(OUT89)
const FREEZE89 = joinpath(@__DIR__, "..", "freeze-s89.txt")
const SPEC89 = joinpath(@__DIR__, "..", "..", "discussion", "specs", "S89-draft-l2l-finite-c-and-n3.md")
const CS89 = (0, 1, 2, typemax(Int)); const IINF = 4
cn(C) = C == typemax(Int) ? "inf" : string(C)

# ---- D1 (FIFO): C = 0 never stores; C >= 1 changes M only when R1 keeps, and then drops the head (oldest) iff full
forget_first!(M::Mem) = ((t, k, a, y) = popfirst!(M.list); M.m[k] -= 1; M.m1[k] -= y; M.ma[a] -= 1; M.ma1[a] -= y; M)
function d1_fifo!(M::Mem, C, kp, t, k, a, y)
    (C == 0 || !kp) && return 0
    ev = 0; length(M.list) == C && (forget_first!(M); ev = 1)
    remember!(M, t, k, a, y); return ev
end
d1!(M::Mem, C, kp, t, k, a, y) = d1_fifo!(M, C, kp, t, k, a, y)    # negative controls redefine this method only

# O1 before the clip (same expression order as o1 in s88)
o1raw(c::Cn, M::Mem, k) = (a = akey(k); rate = (c.n1[a] + M.ma1[a] + 1) / (c.n[a] + M.ma[a] + 2); (c.rn1[k] + M.m1[k] + ALPHA_R1 * rate) / (c.rn[k] + M.m[k] + ALPHA_R1))
gt(p) = (s = 0.0; for k in eachindex(p); s += abs(p[k] - 0.5); end; s)      # G_T = sum_k |p_k - 1/2|

# one step of an L2L-T branch at capacity C; G5 (R1 independent form) and G6 (a)(b)(c) for finite C in (1, 2)
function step89!(c::Cn, M::Mem, C, t, k, a, y, lam)
    p = o1(c, M, k); kp = r1(p, y); kp == r1ind(p, y) || error("G5 R1 independent check C=$(cn(C)) t=$t")
    fin = C == 1 || C == 2; pre = fin ? copy(M.list) : M.list
    kstep!(c, k, a, y, lam); ev = d1!(M, C, kp, t, k, a, y)
    if fin
        e = (t, k, a, Int(y))
        length(M.list) <= C || error("G6(a) length > C C=$C t=$t")
        if !kp
            M.list == pre || error("G6(b) list changed on a step R1 did not keep C=$C t=$t")
        elseif length(pre) == C
            (pre[1][1] == minimum(first, pre) && M.list == vcat(pre[2:end], [e])) || error("G6(c) full: not head-out / order / tail C=$C t=$t")
        else
            M.list == vcat(pre, [e]) || error("G6(c) not full: plain append C=$C t=$t")
        end
    end
    return kp, p, ev
end

# ---- G6 independent reference: own counters (TabL through upd!), own R1, M_ref = last(hist, C); O1 recounted from the list
mutable struct Ref89; K::TabL; hist::Vector{NTuple{4,Int}}; end
newref(lam) = Ref89(TabL(zeros(2), zeros(2), zeros(NK), zeros(NK), lam), NTuple{4,Int}[])
refM(r::Ref89, C) = (n = length(r.hist); r.hist[(n - min(C, n) + 1):n])
function o1ref(K::TabL, L, k)
    a = akey(k); m = 0; m1 = 0; ma = 0; ma1 = 0
    for (_, kk, aa, y) in L; kk == k && (m += 1; m1 += y); aa == a && (ma += 1; ma1 += y); end
    rate = (K.n1[a] + ma1 + 1) / (K.n[a] + ma + 2)
    return clip((K.rn1[k] + m1 + ALPHA_R1 * rate) / (K.rn[k] + m + ALPHA_R1))
end
function refcheck!(r::Ref89, M::Mem, C, kp, t, k, a, y, wh)
    p = o1ref(r.K, refM(r, C), k); kr = y == 1 ? p < 0.5 : p > 0.5
    upd!(r.K, k, a, y); kr && push!(r.hist, (t, k, a, Int(y)))
    (kr == kp && M.list == refM(r, C)) || error("G6 reference C=$(cn(C)) $wh t=$t")
end

# ---- N3 at a read point (life, t) in U: same K, O1 with M empty vs with M_t; G3 and G9 here
function n3point(c::Cn, M::Mem, C, t, R)
    E = newmem(); pK = tab1(c, E); pKM = tab1(c, M)
    sameb(pK, view(R.Tab, :, t + 1)) || error("G9 p_K = FGT table C=$(cn(C)) t=$t")
    pKr = [o1raw(c, E, k) for k in 1:NK]; pKMr = [o1raw(c, M, k) for k in 1:NK]
    (sameb(clip.(pKr), pK) && sameb(clip.(pKMr), pKM)) || error("G9 raw/clip C=$(cn(C)) t=$t")
    recount_ok(M) || error("G3 U read point C=$(cn(C)) t=$t")
    dG = gt(pKM) - gt(pK); dGd = 0.0; dGr = 0.0; ks = NamedTuple[]
    for k in 1:NK
        dk = M.m[k] > 0; dk == any(e -> e[2] == k, M.list) || error("G9 key class C=$(cn(C)) t=$t k=$k")
        g = abs(pKM[k] - 0.5) - abs(pK[k] - 0.5)
        dk ? (dGd += g) : (dGr += g)
        if dk && pK[k] != 0.5
            sg = sign(pK[k] - 0.5)
            push!(ks, (dout = sg * (pKM[k] - pK[k]), dg = g, cross = (pK[k] - 0.5) * (pKM[k] - 0.5) < 0, up = pK[k] > 0.5,
                         inK = LO < pKr[k] < HI, inKM = LO < pKMr[k] < HI))
        end
    end
    abs(dG - (dGd + dGr)) < 1e-12 || error("G9 dG_O1 = direct + rate-only C=$(cn(C)) t=$t")
    C == 0 && (dG == 0.0 || error("G9 C=0 dG_O1 != 0 t=$t"))
    return (pt = (t = t, dG = dG, dGd = dGd, dGr = dGr, nM = length(M.list)), keys = ks)
end

function life89(x; tmax = typemax(Int))
    O = origins84(x); orig = Set{Int}(vcat([O[(g, h)] for g in GR88, h in HS84]...))
    R = replay84(x.lf, x.life, x.P, orig)                                   # S84 gates on the official law
    F = field87(x); qk = qkeys(F); N = min(F.N, tmax); K = F.K; A = F.A; Y = F.Y; lam = R.lam; nC = length(CS89)
    rd = Dict{Int,Set{Int}}(); for t0 in orig, h in HS84; t0 + h + 1 <= N && push!(get!(rd, t0, Set{Int}()), h); end
    need = Set{Int}(t0 + h + 1 for (t0, hs) in rd for h in hs); for t0 in keys(rd); push!(need, t0, t0 + 1); end
    Uset = Set{Int}(t0 + 1 + h for g in GR88, h in HS84 for t0 in O[(g, h)] if t0 + 1 + h <= N)   # unique (life, t), weight 1
    cf = learner87("FGT", x.life); cf.lam == lam || error("lam")
    cs = [newcn() for _ in 1:nC]; Ms = [newmem() for _ in 1:nC]; rf = [newref(lam) for _ in 1:nC]
    kept = [falses(N) for _ in 1:nC]; nev = zeros(Int, nC)
    Tm = [Dict{Int,Vector{Float64}}(0 => tab1(newcn(), newmem())) for _ in 1:nC]
    Ml = [Dict{Int,Vector{NTuple{4,Int}}}(0 => NTuple{4,Int}[]) for _ in 1:nC]; St = [Dict{Int,Any}() for _ in 1:nC]
    for i in 1:nC; 0 in orig && (St[i][0] = deepcopy((cs[i], Ms[i], rf[i]))); end
    sameb(tab1(cs[1], Ms[1]), view(R.Tab, :, 1)) || error("G2 t=0")
    pts = [NamedTuple[] for _ in 1:nC]; kys = [NamedTuple[] for _ in 1:nC]
    for t in 1:N
        update2!(cf, x.lf, t:t, F.maps[F.seg[t]])                            # FGT side on the official law
        for i in 1:nC
            C = CS89[i]; c = cs[i]; M = Ms[i]
            kp, _, ev = step89!(c, M, C, t, K[t], A[t], Y[t], lam); kept[i][t] = kp; nev[i] += ev
            samec(c, cf) || error("G1 main C=$(cn(C)) t=$t")
            C == 0 && (sameb(tab1(c, M), view(R.Tab, :, t + 1)) || error("G2 C=0 table = replay84 t=$t"))
            refcheck!(rf[i], M, C, kp, t, K[t], A[t], Y[t], "main")
            C >= 1 && kp && (last(M.list) == (t, K[t], A[t], Int(Y[t])) || error("G5 kept tail C=$(cn(C)) t=$t"))
            t in need && (Tm[i][t] = tab1(c, M); Ml[i][t] = copy(M.list))
            t in orig && (St[i][t] = deepcopy((c, M, rf[i])))
            if t in Uset; q = n3point(c, M, C, t, R); push!(pts[i], q.pt); append!(kys[i], q.keys); end
        end
    end
    for i in 1:nC; recount_ok(Ms[i]) || error("G3 end of life C=$(cn(CS89[i]))"); end
    rows = NamedTuple[]
    for t0 in sort!(collect(keys(rd)))
        hs = rd[t0]; hmax = maximum(hs); s = t0 + 1
        fA = tabl(Cn(deepcopy(R.st0[t0])...), lam); fU = tabl(Cn(deepcopy(R.st0[t0])...), lam)
        bA = Vector{Any}(undef, nC); bU = Vector{Any}(undef, nC); ps = zeros(nC); M0 = Vector{Any}(undef, nC)
        for i in 1:nC
            c0, m0, r0 = St[i][t0]; samec(fA, c0) || error("FGT origin state C=$(cn(CS89[i])) t0=$t0")
            bA[i] = deepcopy((c0, m0, r0)); bU[i] = deepcopy((c0, m0, r0)); ps[i] = o1(c0, m0, K[s]); M0[i] = copy(m0.list)
        end
        keepM = [kept[i][s] for i in 1:nC]; keepT = falses(nC); out = [Dict{Int,NamedTuple}() for _ in 1:nC]
        for t in s:(t0 + hmax + 1)
            y = t == s ? 1 - Y[t] : Int(Y[t]); h = t - s
            upd!(fA, K[t], A[t], y); upd!(fU, K[t], A[t], Y[t])
            ff = tab1(Cn(fA.n, fA.n1, fA.rn, fA.rn1), newmem())
            for i in 1:nC
                C = CS89[i]; cA, MA, rA = bA[i]; cU, MU, rU = bU[i]
                kp, _, _ = step89!(cA, MA, C, t, K[t], A[t], y, lam); t == s && (keepT[i] = kp)
                samec(cA, fA) || error("G1 twin C=$(cn(C)) t0=$t0 t=$t")
                C == 0 && (sameb(tab1(cA, MA), ff) || error("G2 C=0 twin table = FGT twin t0=$t0 t=$t"))
                refcheck!(rA, MA, C, kp, t, K[t], A[t], y, "twin t0=$t0")
                ku, _, _ = step89!(cU, MU, C, t, K[t], A[t], Y[t], lam)
                samec(cU, fU) || error("G1 unflipped twin C=$(cn(C)) t0=$t0 t=$t")
                refcheck!(rU, MU, C, ku, t, K[t], A[t], Y[t], "unflipped twin t0=$t0")
                if t == s                                                       # G5 at the origin
                    tl(L) = !isempty(L) && last(L)[1] == s
                    if ps[i] != 0.5
                        xor(keepM[i], keepT[i]) || error("G5 exactly one branch keeps s C=$(cn(C)) t0=$t0")
                        C >= 1 && (tl(Ml[i][s]) == keepM[i] && tl(MA.list) == keepT[i] || error("G5 tail is s only in the keeping branch C=$(cn(C)) t0=$t0"))
                    else
                        (!keepM[i] && !keepT[i]) || error("G5 p=1/2 keeps s C=$(cn(C)) t0=$t0")
                        C >= 1 && (Ml[i][s] == M0[i] && MA.list == M0[i] || error("G5 p=1/2 list changed C=$(cn(C)) t0=$t0"))
                    end
                end
                if h in hs
                    tw = tab1(cA, MA); tu = tab1(cU, MU); tm = Tm[i][t]; fm = view(R.Tab, :, t + 1)
                    (sameb(tu, tm) && MU.list == Ml[i][t]) || error("G4 unflipped twin = main (table and M.list) C=$(cn(C)) t0=$t0 h=$h")
                    (recount_ok(MA) && recount_ok(MU)) || error("G3 twin C=$(cn(C)) t0=$t0 h=$h")
                    o = (DL = l1(tm, tw), DF = l1(fm, ff), QL = dist(tm[qk], tw[qk]), QF = dist(fm[qk], ff[qk]),
                         NL = l1(Tm[i][t0], tm), GL = l1(tm, view(R.Tab, :, 1)), GF = l1(fm, view(R.Tab, :, 1)),
                         sM = any(e -> e[1] == s, Ml[i][t]), sT = any(e -> e[1] == s, MA.list))
                    C == 0 && (bits(o.DL) == bits(o.DF) && bits(o.QL) == bits(o.QF) || error("G2 C=0 twin D_s = FGT t0=$t0 h=$h"))
                    out[i][h] = o
                end
            end
        end
        push!(rows, (t0 = t0, ps = ps, keepM = keepM, keepT = keepT, out = out))
    end
    fset = Set{Int}(t for i in x.S for t in formwin(i, L83) if 1 <= t <= N); rset = Set{Int}(t for w in routinewins(x.N, L83) for t in w if 1 <= t <= N)
    e3 = [(fk = count(t -> kept[i][t], fset), fn = length(fset), rk = count(t -> kept[i][t], rset), rn = length(rset)) for i in 1:nC]
    return (id = x.id, O = O, rows = rows, e3 = e3, N = N, nfire = [count(kept[i]) for i in 1:nC], nev = nev,
            nmem = [length(Ms[i].list) for i in 1:nC], listinf = copy(Ms[IINF].list), tabinf = tab1(cs[IINF], Ms[IINF]),
            pts = pts, kys = kys, nU = length(Uset))
end

# G7 (smoke): C = inf against s88 life88 rows (bitwise) and the s88 l2lstep! replay (terminal M.list and table T, bitwise)
function g7smoke(x, r; tmax)
    r8 = life88(x; tmax = tmax)
    (r8.N == r.N && r8.nmem == r.nmem[IINF] && r8.e3 == r.e3[IINF] && length(r8.rows) == length(r.rows)) || error("G7 life88 summary $(x.id)")
    for (a, b) in zip(r8.rows, r.rows)
        (a.t0 == b.t0 && bits(a.ps) == bits(b.ps[IINF]) && a.keepM == b.keepM[IINF] && a.keepT == b.keepT[IINF] && keys(a.out) == keys(b.out[IINF])) || error("G7 life88 row $(x.id) t0=$(a.t0)")
        for h in keys(a.out), f in (:DL, :DF, :QL, :QF, :NL, :GL, :GF)
            bits(getfield(a.out[h], f)) == bits(getfield(b.out[IINF][h], f)) || error("G7 life88 $f $(x.id) t0=$(a.t0) h=$h")
        end
    end
    F = field87(x); c = newcn(); M = newmem(); lam = learner87("FGT", x.life).lam
    for t in 1:r.N; l2lstep!(c, M, t, F.K[t], F.A[t], F.Y[t], lam); end
    (M.list == r.listinf && sameb(tab1(c, M), r.tabinf)) || error("G7 s88 l2lstep! terminal M.list / table $(x.id)")
end

const GATES89 = "G1 K = official FGT counters bitwise (all C, main, flipped and unflipped twins, every step); G2 C=0 table = replay84 every main step, C=0 twin table = FGT twin every step, C=0 twin D_s(T, Q) = FGT bitwise; G3 M aggregates = recount from M.list (end of life, every twin read point, every U point); G4 unflipped twin table and M.list = main at every read point; G5 R1 independent form every step of every branch, at s exactly one branch keeps when p_s != 1/2 (C>=1: tail is s only there), none and M.list unchanged when p_s = 1/2; G6 independent reference (own counters, own R1, M_ref = last(hist, C)) = M.list on every main and twin step incl. s, finite C in (1, 2): length <= C, unchanged when R1 does not keep, head-out + order + tail when full, main evictions > 0 at C=1 and C=2; G9 p_K = FGT table, C=0 dG_O1 == 0.0, key class m>0 = any in M.list, |dG_O1 - (direct + rate-only)| < 1e-12 at every U point"

function smoke89()
    LV = lives83(); xs = [LV[1], LV[end]]; tm = 12000
    io = IOBuffer(); ev = zeros(Int, length(CS89))
    for x in xs
        r = life89(x; tmax = tm); g7smoke(x, r; tmax = tm); ev .+= r.nev
        println(io, "smoke $(x.id) prefix $(r.N): G1-G6, G9 ok; G7 (life88 rows, s88 l2lstep! terminal M.list and T, C=inf) ok; origins twinned $(length(r.rows)); |U| $(r.nU)")
    end
    (ev[2] > 0 && ev[3] > 0) || error("G6 main evictions > 0 at C=1 and C=2")
    println(io, "G6 main evictions > 0 at C=1 and C=2: ok")
    println(io, "gates: ", GATES89)
    println(io, "note: smoke prints no S89-E1..E3 quantity and no N3 / D_s value; G8 and the printed-digit part of G7 run only in run.")
    s = String(take!(io)); print(s); write(joinpath(OUT89, "smoke.out"), s)
end

function frozen89()
    fz = split(read(FREEZE89, String), "\n")
    ok(path, name) = (h = bytes2hex(sha256(read(path))); any(==("$h  $name"), fz))
    ok(PRED89, "experiments/s89_l2l_d1/predictions.toml") && ok(SPEC89, "discussion/specs/S89-draft-l2l-finite-c-and-n3.md")
end
fm4(x) = isnan(x) ? "NA" : string(round(x; sigdigits = 4))
mn(v) = isempty(v) ? NaN : mean(v)
q3s(v) = isempty(v) ? "NA" : q3(v)
verdict(parts) = any(==(:miss), parts) ? "miss" : any(==(:empty), parts) ? "undecidable" : "hit"
function kdesc(v)
    isempty(v) && return "n 0"
    d = [a.dout for a in v]
    "n $(length(v))  mean d_out $(fm4(mean(d)))  d_out $(q3(d))  mean dg $(fm4(mean([a.dg for a in v])))  1/2-crossings $(count(a -> a.cross, v))"
end

function run89()
    frozen89() || error("predictions not frozen")
    LV = lives83(); length(LV) == 48 || error("48 lives")
    res = tmapv(life89, LV)
    nC = length(CS89); io = IOBuffer()
    (sum(r.nev[2] for r in res) > 0 && sum(r.nev[3] for r in res) > 0) || error("G6 main evictions > 0 at C=1 and C=2")
    pool(i, g, h, f) = [f(r, row) for r in res for row in r.rows if row.t0 in r.O[(g, h)] && haskey(row.out[i], h)]
    exc(g, h) = sum(count(t0 -> t0 + h + 1 > r.N, r.O[(g, h)]) for r in res)
    # G8: FGT D on T / Q quartiles = S86 / S87 printed (4 digits)
    for g in GR88, h in HS84
        qT = q3(pool(IINF, g, h, (r, w) -> w.out[IINF][h].DF)); qQ = q3(pool(IINF, g, h, (r, w) -> w.out[IINF][h].QF))
        e86 = parse_q(joinpath(@__DIR__, "..", "s86_bisim", "out", "bisim.out"), "  $g h=$h: n ")
        e87 = parse_q(joinpath(@__DIR__, "..", "s87_contents", "out", "contents.out"), "  FGT $g h=$h: n ")
        (qT == e86 && qQ == e87) || error("G8 FGT quartiles $g h=$h: T $qT vs S86 $e86, Q $qQ vs S87 $e87")
    end
    # group lines (S88 format); G7: the C = inf lines and the S88 E1-E3 lines must appear verbatim in s88 l2l.out
    function gline(i, g, h)
        v = pool(i, g, h, (r, w) -> w.out[i][h]); isempty(v) && return nothing
        "  $g h=$h: n $(length(v)) (excluded $(exc(g, h)))  T: FGT $(q3([a.DF for a in v]))  L2L $(q3([a.DL for a in v]))  L2L-FGT $(q3([a.DL - a.DF for a in v]))  L2L D=0: $(count(a -> a.DL == 0, v))  |  Q: FGT $(q3([a.QF for a in v]))  L2L $(q3([a.QL for a in v]))  L2L D=0: $(count(a -> a.QL == 0, v))  |  N_T L2L $(q3([a.NL for a in v]))  G_T FGT $(q3([a.GF for a in v])) L2L $(q3([a.GL for a in v]))"
    end
    s88_lines = readlines(joinpath(@__DIR__, "..", "s88_l2l", "out", "l2l.out"))
    g7 = String[]
    count(l -> any(g -> startswith(l, "  $g h="), GR88), s88_lines) == length(GR88) * length(HS84) || error("G7 s88 l2l.out group lines != $(length(GR88) * length(HS84))")
    s88 = Set(s88_lines)
    for g in GR88, h in HS84; ln = gline(IINF, g, h); ln === nothing && error("G7 missing group $g h=$h"); push!(g7, ln); end
    tg = [(r.id, w) for r in res for w in r.rows if w.ps[IINF] != 0.5 && haskey(w.out[IINF], 1000) && any(g -> w.t0 in r.O[(g, 1000)], GR88)]
    allo = sum(length(Set(vcat([r.O[(g, 1000)] for g in GR88]...))) for r in res); half = count(w -> w.ps[IINF] == 0.5, [w for r in res for w in r.rows])
    d = [w.out[IINF][1000].DL - w.out[IINF][1000].DF for (_, w) in tg]
    e1 = isempty(d) ? "undecidable" : mean(d) > 0 ? "hit" : "miss"
    z2 = count(((_, w),) -> w.out[IINF][1000].DL == 0, tg); e2 = isempty(tg) ? "undecidable" : z2 == 0 ? "hit" : "miss"
    km = count(((_, w),) -> w.keepM[IINF], tg)
    push!(g7, "E1: targets $(length(tg)) of $allo h=1000 origins (p_s = 1/2 origins overall: $half); mean paired difference D_L2L - D_FGT on T = $(round(isempty(d) ? NaN : mean(d), sigdigits = 4)) (quartiles $(q3(d))) -> $e1")
    push!(g7, "E2: targets with L2L-T D_s(s+1000) = 0 on T: $z2 / $(length(tg)) -> $e2   (s kept by main $km, by twin $(length(tg) - km))")
    fk = sum(r.e3[IINF].fk for r in res); fn = sum(r.e3[IINF].fn for r in res); rk = sum(r.e3[IINF].rk for r in res); rn = sum(r.e3[IINF].rn for r in res)
    e3 = (fn == 0 || rn == 0) ? "undecidable" : fk / fn > rk / rn ? "hit" : "miss"
    wins = count(r -> r.e3[IINF].fn > 0 && r.e3[IINF].rn > 0 && r.e3[IINF].fk / r.e3[IINF].fn > r.e3[IINF].rk / r.e3[IINF].rn, res)
    push!(g7, "E3: kept fraction formation $fk / $fn = $(round(fk / fn, digits = 4)), routine $rk / $rn = $(round(rk / rn, digits = 4)); lives with formation > routine $wins / $(length(res)) (not used for the verdict) -> $e3")
    push!(g7, "fragments at end of life (C = infinity): $(q3(Float64[r.nmem[IINF] for r in res])); fraction of examples $(q3([r.nmem[IINF] / r.N for r in res]))")
    push!(g7, "S88-E1: $e1", "S88-E2: $e2", "S88-E3: $e3")
    for ln in g7; ln in s88 || error("G7 C=inf line not in s88 l2l.out: $ln"); end
    println(io, "gate: S84 gates on the official law; ", GATES89, "; G7 C=inf group lines and S88 E1-E3 lines = s88 l2l.out verbatim ($(length(g7)) lines); G8 FGT D on T / Q quartiles = S86 bisim.out / S87 contents.out")
    println(io, "capacities C = 0, 1, 2, inf (D1 oldest-out). seen 48 lives; no capacity is selected from these results.")

    println(io, "== 1. D_s(s+h) per group (pooled; q1 / median / q3). T = L1 over 130 keys; Q = mean over 2000 probes. N_T, G_T as S88.")
    for i in 1:nC, g in GR88, h in HS84
        ln = gline(i, g, h)
        if ln === nothing
            println(io, "  C=$(cn(CS89[i]))  $g h=$h: n 0")
        else
            v = pool(i, g, h, (r, w) -> w.out[i][h])
            println(io, "  C=$(cn(CS89[i]))", ln, "  |  Q: L2L-FGT $(q3([a.QL - a.QF for a in v]))")
        end
    end

    println(io, "== 2. N3 same-K diagnosis on U (unique (life, t), weight 1)")
    P = [vcat([r.pts[i] for r in res]...) for i in 1:nC]; KY = [vcat([r.kys[i] for r in res]...) for i in 1:nC]
    nU = sum(r.nU for r in res); all(i -> length(P[i]) == nU, 1:nC) || error("U size")
    crs = String[]
    for i in 1:nC
        C = cn(CS89[i]); p = P[i]; dG = [a.dG for a in p]; dd = [a.dGd for a in p]; dr = [a.dGr for a in p]; nm = Float64[a.nM for a in p]
        sG = sum(dG); rat(x) = sG == 0 ? "NA" : fm4(sum(x) / sG)
        cr = (var(nm) == 0 || var(dG) == 0) ? "NA" : fm4(cor(nm, dG))
        println(io, "  C=$C |U| $(length(p)): dG_O1 mean $(fm4(mn(dG))) q $(q3s(dG)) | dG_direct mean $(fm4(mn(dd))) q $(q3s(dd)) share $(rat(dd)) | dG_rate_only mean $(fm4(mn(dr))) q $(q3s(dr)) share $(rat(dr)) | cor(|M_t|, dG_O1) $cr")
        kp = KY[i]; kin = filter(a -> a.inK, kp); kcl = filter(a -> !a.inK, kp)
        fr(v) = isempty(kp) ? "NA" : fm4(length(v) / length(kp))
        println(io, "    K+      : ", kdesc(kp))
        println(io, "    K+_in   : ", kdesc(kin), "  (fraction of K+ $(fr(kin)))")
        println(io, "    K+_clip : ", kdesc(kcl), "  (fraction of K+ $(fr(kcl)))")
        println(io, "    K+_in both-interior: ", kdesc(filter(a -> a.inKM, kin)), " | K+_in reaches the clip after: ", kdesc(filter(a -> !a.inKM, kin)))
        println(io, "    K+ p_K > 1/2: ", kdesc(filter(a -> a.up, kp)), " | K+ p_K < 1/2: ", kdesc(filter(a -> !a.up, kp)))
        println(io, "    K+_in p_K > 1/2: ", kdesc(filter(a -> a.up, kin)), " | K+_in p_K < 1/2: ", kdesc(filter(a -> !a.up, kin)))
        push!(crs, "  C=$C: |U| $(length(p))  mean dG_O1 $(fm4(mn(dG)))  direct $(fm4(mn(dd)))  rate_only $(fm4(mn(dr)))  |K+| $(length(kp))  |K+_in| $(length(kin))  mean d_out K+_in $(fm4(mn([a.dout for a in kin])))  mean |M_t| $(fm4(mn(nm)))  cor $cr")
    end
    println(io, "  -- across capacities:"); foreach(l -> println(io, l), crs)

    println(io, "== 3. D1 eviction and keeping (main trajectory)")
    for i in 1:nC
        C = cn(CS89[i]); fk = sum(r.e3[i].fk for r in res); fn = sum(r.e3[i].fn for r in res); rk = sum(r.e3[i].rk for r in res); rn = sum(r.e3[i].rn for r in res)
        println(io, "  C=$C: R1 fires total $(sum(r.nfire[i] for r in res)) (per life $(q3(Float64[r.nfire[i] for r in res])))  evictions total $(sum(r.nev[i] for r in res)) (per life $(q3(Float64[r.nev[i] for r in res])))  |M| at end $(q3(Float64[r.nmem[i] for r in res]))  R1 fired formation $fk / $fn = $(round(fk / fn, digits = 4)) routine $rk / $rn = $(round(rk / rn, digits = 4))")
        for h in HS84
            v = [w.out[i][h] for r in res for w in r.rows if w.ps[i] != 0.5 && haskey(w.out[i], h) && any(g -> w.t0 in r.O[(g, h)], GR88)]
            println(io, "    internal audit (out of type, TRACE-1 not used) h=$h: s fragment still in main or twin M $(count(a -> a.sM || a.sT, v)) / $(length(v))  (main $(count(a -> a.sM, v)), twin $(count(a -> a.sT, v)))")
        end
    end

    println(io, "== 4. E3 supplement and N2a stratification (h = 1000, T and Q). C=0 keeps nothing: 'main / twin keep' there means R1 fired at s.")
    base = [(r, w) for r in res for w in r.rows if haskey(w.out[IINF], 1000) && any(g -> w.t0 in r.O[(g, 1000)], GR88)]
    elig(i) = Set((r.id, w.t0) for (r, w) in base if w.ps[i] != 0.5)
    Sc = intersect(elig(2), elig(3), elig(IINF))
    dD(i, S) = [w.out[i][1000].DL - w.out[i][1000].DF for (r, w) in base if (r.id, w.t0) in S]
    println(io, "  h=1000 readable origins $(length(base)); |S_common| (C = 1, 2, inf) $(length(Sc))")
    for i in 1:nC
        S = elig(i); v = [(w.keepM[i], w.out[i][1000]) for (r, w) in base if (r.id, w.t0) in S]
        println(io, "  C=$(cn(CS89[i])): p_s = 1/2 excluded $(length(base) - length(S)); own eligible set $(length(S)): mean D_L2L - D_FGT on T $(fm4(mn(dD(i, S))))")
        for (lab, sel) in (("main keep", true), ("twin keep", false))
            u = [o for (k, o) in v if k == sel]; dl = [o.DL for o in u]; ql = [o.QL for o in u]
            println(io, "    $lab: n $(length(u))  D_s(s+1000) T mean $(fm4(mn(dl))) q $(q3s(dl))  Q mean $(fm4(mn(ql))) q $(q3s(ql))")
        end
    end

    # ---- verdicts (common rule: equality is a miss; any miss -> miss; else any empty -> undecidable; else hit)
    println(io, "== verdicts on the frozen predictions")
    j1 = Symbol[]; s1 = String[]
    for i in 2:nC
        dG = [a.dG for a in P[i]]; push!(j1, isempty(dG) ? :empty : mean(dG) < 0 ? :hit : :miss); push!(s1, "C=$(cn(CS89[i])) n $(length(dG)) mean $(fm4(mn(dG)))")
    end
    println(io, "S89-E1 (mean dG_O1 < 0 on U at C = 1, 2, inf): ", join(s1, "; "), " -> ", verdict(j1))
    j2 = Symbol[]; s2 = String[]
    for i in 2:nC
        dv = [a.dout for a in KY[i] if a.inK]; push!(j2, isempty(dv) ? :empty : mean(dv) < 0 ? :hit : :miss); push!(s2, "C=$(cn(CS89[i])) n $(length(dv)) mean $(fm4(mn(dv)))")
    end
    println(io, "S89-E2 (mean d_out < 0 on K+_in at C = 1, 2, inf): ", join(s2, "; "), " -> ", verdict(j2))
    di = dD(IINF, Sc); j3 = Symbol[]; s3 = String[]
    for i in 2:3
        dc = dD(i, Sc); push!(j3, isempty(Sc) ? :empty : mean(dc) < mean(di) ? :hit : :miss); push!(s3, "C=$(cn(CS89[i])) $(fm4(mn(dc)))")
    end
    println(io, "S89-E3 (on S_common, n $(length(Sc)): mean dD_C < mean dD_inf = $(fm4(mn(di))) for C = 1, 2): ", join(s3, "; "), " -> ", verdict(j3))
    println(io, "note: seen lives only. E1-E3 judged at C = 1, 2, inf; C = 0 is the construction control. No R1/O1 change and no capacity choice follow from these alone.")
    s = String(take!(io)); print(s); write(joinpath(OUT89, "l2l_d1.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    (isempty(ARGS) || ARGS[1] == "smoke") ? smoke89() : ARGS[1] == "run" ? run89() : error("smoke|run")
end
