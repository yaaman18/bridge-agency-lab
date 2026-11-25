# S79 §8 (discussion/specs/S79-draft-trace1-rates.md): contract r2 final. Pass: d_LB >= 10 f_UB and 1 - d_LB <= 0.1 (1 - f_UB);
# fail: d_UB < 10 f_LB or 1 - d_UB > 0.1 (1 - f_LB); else undecided. One-sided 97.5% Clopper-Pearson each (Bonferroni, pass pair >= 95%).
# Includes s79.jl unchanged (its main block does not run). Seeds 1600-1617 are not opened.
# usage: julia --project=. -t 4 experiments/s79_rates/s79b.jl run
include(joinpath(@__DIR__, "s79.jl"))

const PRED79B = joinpath(@__DIR__, "predictions-b.toml")
const A2 = 0.025; const LRP = 10.0; const LRN = 0.1
const BPP = (d = 10 / 11, f = 1 / 11)
const LOGF79 = cumsum(vcat(0.0, [log(k) for k in 1:5000]))       # LOGF79[n+1] = log n!
function bpmf(n, p)                                          # O(n) binomial pmf
    p == 0 && return [k == 0 ? 1.0 : 0.0 for k in 0:n]; p == 1 && return [k == n ? 1.0 : 0.0 for k in 0:n]
    lp = log(p); lq = log1p(-p)
    return [exp(LOGF79[n+1] - LOGF79[k+1] - LOGF79[n-k+1] + k * lp + (n - k) * lq) for k in 0:n]
end
function bis(g)
    lo = 0.0; hi = 1.0
    for _ in 1:80; m = (lo + hi) / 2; g(m) < 0 ? (lo = m) : (hi = m); end
    return (lo + hi) / 2
end
lb2(x, n) = x == 0 ? 0.0 : bis(p -> sum(@view bpmf(n, p)[x+1:end]) - A2)
ub2(x, n) = x == n ? 1.0 : bis(p -> A2 - sum(@view bpmf(n, p)[1:x+1]))
bounds(n) = ([lb2(x, n) for x in 0:n], [ub2(x, n) for x in 0:n])
passr(dl, fu) = dl >= LRP * fu && 1 - dl <= LRN * (1 - fu)
failr(du, fl) = du < LRP * fl || 1 - du > LRN * (1 - fl)
function verdict2(X, K, Z, W)
    dl, du, fl, fu = lb2(X, K), ub2(X, K), lb2(Z, W), ub2(Z, W)
    return (v = passr(dl, fu) ? "pass" : failr(du, fl) ? "fail" : "undecided", dl = dl, du = du, fl = fl, fu = fu)
end
function probs2(pX, pZ, BK, BW)
    pp = 0.0; pf = 0.0
    for x in eachindex(pX), z in eachindex(pZ)
        w = pX[x] * pZ[z]; w == 0 && continue
        passr(BK[1][x], BW[2][z]) ? (pp += w) : failr(BK[2][x], BW[1][z]) && (pf += w)
    end
    return (pass = pp, fail = pf, undec = 1 - pp - pf)
end
crit2(c) = (v = verdict2(c.X, c.K, c.Z, c.W); min(v.dl - LRP * v.fu, LRN * (1 - v.fu) - (1 - v.dl)))

function run79b()
    isfile(PRED79B) || error("predictions not frozen: $PRED79B")
    io = IOBuffer(); w0 = TOML.parsefile(W0_R3)["w0"]
    println(io, "== contract r2 final: LR+ >= $LRP, LR- <= $LRN, one-sided $(1 - A2) CP each")
    # gate: fast pmf == s79 binpmf, and probs2 masks == verdict2 at small n
    for n in (14, 60), p in (0.03, 0.5, 0.9); maximum(abs.(bpmf(n, p) .- binpmf(n, p))) < 1e-12 || error("pmf gate"); end
    for n in (4, 8)
        K = sum(kl(n)); W = 15n; BK = bounds(K); BW = bounds(W)
        for x in 0:K, z in 0:W
            v = verdict2(x, K, z, W).v; w = passr(BK[1][x+1], BW[2][z+1]) ? "pass" : failr(BK[2][x+1], BW[1][z+1]) ? "fail" : "undecided"
            v == w || error("verdict gate n=$n x=$x z=$z")
        end
    end
    let n = 40, K = sum(kl(n)), W = 15n, BK = bounds(K), BW = bounds(W)   # codex I-R P3: probs2 on point masses
        e(m, i) = [k == i ? 1.0 : 0.0 for k in 0:m]
        probs2(e(K, K), e(W, 0), BK, BW).pass == 1.0 || error("probs2 gate pass"); probs2(e(K, 0), e(W, W), BK, BW).fail == 1.0 || error("probs2 gate fail")
    end
    println(io, "gate: O(n) pmf == s79 binpmf; tabulated bounds == verdict2 for all (X, Z) at n = 4, 8; probs2 point masses at n = 40 give pass 1 / fail 1")
    v4 = verdict2(14, 14, 0, 60); println(io, "n=4 all detected, 0/60 false: d_LB=$(f4(v4.dl)) f_UB=$(f4(v4.fu)) -> $(v4.v)")
    println(io, "n\tK\tW\tG p/f/u\tG rho=0.3 p/f/u\tB'' p/f/u\tB(0.90,0.10) p/f/u\tD=F(0.5,0.5) pass")
    rows = Dict()
    for n in NGRID79
        K = sum(kl(n)); W = 15n; BK = bounds(K); BW = bounds(W)
        g = probs2(bpmf(K, G79.d), bpmf(W, G79.f), BK, BW)
        gx, gz = clusterdists(n, G79.d, G79.f, 0.3); g3 = probs2(gx, gz, BK, BW)
        b = probs2(bpmf(K, BPP.d), bpmf(W, BPP.f), BK, BW); b0 = probs2(bpmf(K, 0.9), bpmf(W, 0.1), BK, BW)
        h = probs2(bpmf(K, 0.5), bpmf(W, 0.5), BK, BW)
        rows[n] = (g = g, g3 = g3, b = b, h = h)
        println(io, "$n\t$K\t$W\t$(pfu(g))\t$(pfu(g3))\t$(pfu(b))\t$(pfu(b0))\t$(h.pass)")
    end
    nG = findfirst(n -> rows[n].g.pass >= 0.8, NGRID79); nG = nG === nothing ? nothing : NGRID79[nG]
    println(io, "S79-H1 (smallest n with P_pass(G) >= 0.8 in (28, 48]): $(nG !== nothing && 28 < nG <= 48 ? "holds" : "miss")  n=$(nG === nothing ? "none <= 80" : nG)")
    n3 = findfirst(n -> rows[n].g3.pass >= 0.8, NGRID79); println(io, "  [desc] G rho=0.3 first n >= 0.8: $(n3 === nothing ? "none <= 80" : NGRID79[n3])")
    bm = maximum(rows[n].b.pass for n in NGRID79)
    println(io, "S79-H2 (max_n P_pass(B'') <= 0.025): $(bm <= A2 ? "holds" : "miss")  max=$(f4(bm))")
    println(io, "check: d=f clock (0.5,0.5) pass prob 0 on the grid: $(all(rows[n].h.pass == 0 for n in NGRID79))")
    # ---- application (descriptive)
    lives = [(st, l) for st in (1, 2) for l in 1:NLIFE]
    saved = Dict(j => loadlife4(j[1], "FGT", j[2]) for j in lives)
    M = Dict(zip(lives, tmapv(j -> mainrun78(j[2], j[1]), lives)))
    for j in lives; reinterpret(UInt64, M[j].P) == reinterpret(UInt64, saved[j].P) && M[j].Y == saved[j].Y || error("main stream differs $j"); end
    U = Dict(j => losses(M[j].P, M[j].Y) .- losses(M[j].Pc, M[j].Y) for j in lives)
    E = Dict(j => losses(saved[j].P, saved[j].Y) .- saved[j].lref for j in lives)
    D = Dict(j => ownq(saved[j].P, saved[j].Y, nothing) for j in lives)
    S = Dict(j => selset(saved[j], EPS75, w0) for j in lives); Ns = Dict(j => M[j].N for j in lives)
    sc = Dict("O-win" => Dict(j => wscores(U[j], 500) for j in lives), "REF-win" => Dict(j => wscores(E[j], 500) for j in lives), "C0 w=500" => Dict(j => c0scores(D[j], 500) for j in lives))
    wm(nm) = (j, th) -> BitVector([!isnan(sc[nm][j][t]) && sc[nm][j][t] > th for t in 1:Ns[j]])
    clocks = [("O-win", TH78, wm("O-win")), ("REF-win", TH78, wm("REF-win")), ("C0 w=500", TH78, wm("C0 w=500")),
              ("C4 delta=0.01", HSCAN, (j, h) -> firemask("C4", (delta = 0.01,), h, D[j]))]
    st1 = [j for j in lives if j[1] == 1]; st2 = [j for j in lives if j[1] == 2]
    println(io, "== application (descriptive; both stages seen). theta on stage 1 by max min(d_LB - 10 f_UB, 0.1(1-f_UB) - (1-d_LB)), ties -> earlier")
    res = Dict()
    for L in (500, 1000), (nm, grid, mk) in clocks
        best = nothing; bc = -Inf
        for th in grid
            c = counts(j -> mk(j, th), st1, Ns, S, L); v = crit2(c); v > bc && (bc = v; best = (th = th, c = c))
        end
        c1 = best.c; v1 = verdict2(c1.X, c1.K, c1.Z, c1.W)
        c2 = counts(j -> mk(j, best.th), st2, Ns, S, L); v2 = verdict2(c2.X, c2.K, c2.Z, c2.W); res[(nm, L)] = v2.v
        println(io, "  $nm L=$L theta=$(best.th): st1 $(c1.X)/$(c1.K) $(c1.Z)/$(c1.W) -> $(v1.v) | st2 $(c2.X)/$(c2.K) $(c2.Z)/$(c2.W) d=[$(f4(v2.dl)),$(f4(v2.du))] f=[$(f4(v2.fl)),$(f4(v2.fu))] -> $(v2.v)")
    end
    println(io, "S79-H3 (O-win L=1000 stage 2 undecided): $(res[("O-win", 1000)] == "undecided" ? "holds" : "miss") ($(res[("O-win", 1000)]))")
    s = String(take!(io)); print(s); write(joinpath(OUT79, "s79b.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    ARGS[1] == "run" && run79b()
end
