# S79 (discussion/specs/S79-draft-trace1-rates.md): contract r2 (rates with one-sided 95% Clopper-Pearson bounds, three-valued),
# its power under a good-clock alternative, and a descriptive application to seen lives (theta chosen on stage 1, applied to stage 2).
# Includes s78.jl (and through it s77, s76, s75) unchanged. Seeds 1600-1617 are not opened.
# usage: julia --project=. -t 4 experiments/s79_rates/s79.jl run
include(joinpath(@__DIR__, "..", "s78_observer", "s78.jl"))
using Random

const OUT79 = joinpath(@__DIR__, "out"); mkpath(OUT79)
const PRED79 = joinpath(@__DIR__, "predictions.toml")
const ALPHA79 = 0.05; const DST79 = 0.90; const FST79 = 0.10
const NGRID79 = collect(4:4:80); const RHO79 = [0.1, 0.3]
const G79 = (d = 0.97, f = 0.03); const B79 = (d = 0.90, f = 0.10)

# ---- exact binomial tails and Clopper-Pearson one-sided bounds (no external packages)
lchoose(n, k) = sum(log, (n-k+1):n; init = 0.0) - sum(log, 1:k; init = 0.0)
function binpmf(n, p)
    p == 0 && return [k == 0 ? 1.0 : 0.0 for k in 0:n]; p == 1 && return [k == n ? 1.0 : 0.0 for k in 0:n]
    lc = [lchoose(n, k) for k in 0:n]
    return [exp(lc[k+1] + k * log(p) + (n - k) * log1p(-p)) for k in 0:n]
end
upper_tail(n, p, x) = sum(binpmf(n, p)[x+1:end])        # P(X >= x)
lower_tail(n, p, x) = sum(binpmf(n, p)[1:x+1])          # P(X <= x)
function bisect(g, lo, hi)                              # g increasing in p, find g(p) = 0
    for _ in 1:80; m = (lo + hi) / 2; g(m) < 0 ? (lo = m) : (hi = m); end
    return (lo + hi) / 2
end
cp_lb(x, n) = x == 0 ? 0.0 : bisect(p -> upper_tail(n, p, x) - ALPHA79, 0.0, 1.0)
cp_ub(x, n) = x == n ? 1.0 : bisect(p -> ALPHA79 - lower_tail(n, p, x), 0.0, 1.0)
function verdict(X, K, Z, W)
    dl, du, fl, fu = cp_lb(X, K), cp_ub(X, K), cp_lb(Z, W), cp_ub(Z, W)
    v = dl >= DST79 && fu <= FST79 ? "pass" : (du < DST79 || fl > FST79) ? "fail" : "undecided"
    return (v = v, dl = dl, du = du, fl = fl, fu = fu)
end

# ---- power of contract r2 for count distributions pX (0..K) and pZ (0..W), independent
function r2probs(pX, K, pZ, W)   # codex I-R P1: compare binomial tails at d*, f* directly (equivalent to the CP bounds)
    bK = binpmf(K, DST79); bW = binpmf(W, FST79)
    utK = reverse(cumsum(reverse(bK))); ltK = cumsum(bK); utW = reverse(cumsum(reverse(bW))); ltW = cumsum(bW)
    dlok = utK .<= ALPHA79; duok = ltK .>= ALPHA79       # d_LB >= d*  ;  d_UB >= d*
    fuok = ltW .<= ALPHA79; flok = utW .>= ALPHA79       # f_UB <= f*  ;  f_LB <= f*
    aX = sum(pX[dlok]); aZ = sum(pZ[fuok]); okX = sum(pX[duok]); okZ = sum(pZ[flok])
    pp = aX * aZ; pf = 1 - okX * okZ
    return (pass = pp, fail = pf, undec = 1 - pp - pf, masks = (dlok, duok, fuok, flok))
end
pfu(r) = "$(f4(r.pass))/$(f4(r.fail))/$(f4(r.undec))"
kl(n) = [isodd(l) ? 4 : 3 for l in 1:n]
oldpass(n, d, f) = prod(d^k for k in kl(n)) * (lower_tail(15, f, 1))^n
# beta-binomial pmf with mean p and intra-cluster correlation rho, cluster size m (product form, no gamma)
function bbpmf(m, p, rho)
    a = p * (1 - rho) / rho; b = (1 - p) * (1 - rho) / rho
    den = prod(a + b + i for i in 0:m-1)
    return [exp(lchoose(m, x)) * prod(a + i for i in 0:x-1; init = 1.0) * prod(b + j for j in 0:m-x-1; init = 1.0) / den for x in 0:m]
end
conv(a, b) = [sum(a[i+1] * b[k-i+1] for i in max(0, k - length(b) + 1):min(k, length(a) - 1)) for k in 0:(length(a) + length(b) - 2)]
function clusterdists(n, d, f, rho)
    pX = [1.0]; for k in kl(n); pX = conv(pX, bbpmf(k, d, rho)); end
    z1 = bbpmf(15, f, rho); pZ = [1.0]; for _ in 1:n; pZ = conv(pZ, z1); end
    return pX, pZ
end
function powerrow(n, d, f; rho = 0.0)
    K = sum(kl(n)); W = 15n
    pX, pZ = rho == 0 ? (binpmf(K, d), binpmf(W, f)) : clusterdists(n, d, f, rho)
    return r2probs(pX, K, pZ, W)
end

# ---- descriptive application
function counts(mask_of, lives, Ns, S, L)
    X = 0; K = 0; Z = 0; W = 0; per = []
    for j in lives
        r = judgeL(mask_of(j), Ns[j], S[j], L); x = round(Int, r.det_sel * length(S[j]))
        X += x; K += length(S[j]); Z += r.nfalse; W += r.nwin; push!(per, (x = x, k = length(S[j]), z = r.nfalse, w = r.nwin))
    end
    return (X = X, K = K, Z = Z, W = W, per = per)
end
crit(c) = (v = verdict(c.X, c.K, c.Z, c.W); min(v.dl - DST79, FST79 - v.fu))
function boot(per; B = 2000, rng = MersenneTwister(79))
    ds = Float64[]; fs = Float64[]
    for _ in 1:B
        s = per[rand(rng, 1:length(per), length(per))]
        push!(ds, sum(p.x for p in s) / sum(p.k for p in s)); push!(fs, sum(p.z for p in s) / sum(p.w for p in s))
    end
    q(v, a) = sort(v)[clamp(round(Int, a * length(v)), 1, length(v))]
    return (d5 = q(ds, 0.05), d95 = q(ds, 0.95), f5 = q(fs, 0.05), f95 = q(fs, 0.95))
end

function run79()
    isfile(PRED79) || error("predictions not frozen: $PRED79")
    io = IOBuffer(); w0 = TOML.parsefile(W0_R3)["w0"]
    # ---- part A: formula checks and power
    v4 = verdict(14, 14, 0, 60)
    println(io, "== A. contract r2 (one-sided 95% CP, d*=$DST79, f*=$FST79)")
    println(io, "check: n=4, K=14 all detected, Z=0/60 -> d_LB=$(v4.dl) (0.05^(1/14)=$(0.05^(1/14))) f_UB=$(f4(v4.fu)) verdict=$(v4.v)  (expected undecided: $(v4.v == "undecided" && abs(v4.dl - 0.05^(1/14)) < 1e-9))")
    # gate (codex I-R P1): tail masks == verdict() for every (X, Z) at n = 4, 8, 12
    for n in (4, 8, 12)
        K = sum(kl(n)); W = 15n; m = r2probs(ones(K + 1), K, ones(W + 1), W).masks
        for x in 0:K, z in 0:W
            v = verdict(x, K, z, W).v; w = m[1][x+1] && m[3][z+1] ? "pass" : (!m[2][x+1] || !m[4][z+1]) ? "fail" : "undecided"
            v == w || error("mask gate failed n=$n x=$x z=$z: $v vs $w")
        end
    end
    println(io, "gate: tail masks agree with CP verdict() for all (X, Z) at n = 4, 8, 12")
    rows = Dict()
    for n in NGRID79
        rows[(n, :G)] = powerrow(n, G79.d, G79.f); rows[(n, :B)] = powerrow(n, B79.d, B79.f)
        for ρ in RHO79; rows[(n, :G, ρ)] = powerrow(n, G79.d, G79.f; rho = ρ); rows[(n, :B, ρ)] = powerrow(n, B79.d, B79.f; rho = ρ); end
    end
    println(io, "n\tK\tW\tG pass/fail/undec\tG old\tB pass/fail/undec\tB old\t" * join(["G p/f/u rho=$ρ\tB p/f/u rho=$ρ" for ρ in RHO79], "\t"))
    for n in NGRID79
        g = rows[(n, :G)]; b = rows[(n, :B)]
        println(io, "$n\t$(sum(kl(n)))\t$(15n)\t$(f4(g.pass))/$(f4(g.fail))/$(f4(g.undec))\t$(f4(oldpass(n, G79.d, G79.f)))\t$(f4(b.pass))/$(f4(b.fail))/$(f4(b.undec))\t$(f4(oldpass(n, B79.d, B79.f)))\t" *
                    join(["$(pfu(rows[(n, :G, ρ)]))\t$(pfu(rows[(n, :B, ρ)]))" for ρ in RHO79], "\t"))
    end
    bmax = maximum(rows[(n, :B)].pass for n in NGRID79)
    println(io, "check: independent model max_n P_pass(B) = $(f4(bmax)) (<= 0.05: $(bmax <= ALPHA79 + 1e-12))")
    nG = findfirst(n -> rows[(n, :G)].pass >= 0.8, NGRID79); nG = nG === nothing ? nothing : NGRID79[nG]
    println(io, "S79-F1 (smallest n with P_pass(G) >= 0.8 in [20,40]): $(nG !== nothing && 20 <= nG <= 40 ? "holds" : "miss")  n=$(nG === nothing ? "none <= 80" : nG)")
    b3 = [n for n in NGRID79 if rows[(n, :B, 0.3)].pass > ALPHA79]
    println(io, "S79-F2 (rho=0.3: P_pass(B) > 0.05 for some n): $(isempty(b3) ? "miss" : "holds")  max=$(f4(maximum(rows[(n, :B, 0.3)].pass for n in NGRID79)))$(isempty(b3) ? "" : " at n in $(b3)")")
    o4 = oldpass(4, G79.d, G79.f)
    println(io, "S79-F3 (old contract 4-life pass prob for G < 0.5): $(o4 < 0.5 ? "holds" : "miss")  $(f4(o4))")
    # ---- part B: descriptive application
    lives = [(st, l) for st in (1, 2) for l in 1:NLIFE]
    saved = Dict(j => loadlife4(j[1], "FGT", j[2]) for j in lives)
    M = Dict(zip(lives, tmapv(j -> mainrun78(j[2], j[1]), lives)))
    for j in lives
        reinterpret(UInt64, M[j].P) == reinterpret(UInt64, saved[j].P) && M[j].Y == saved[j].Y || error("main stream differs from saved $j")
    end
    U = Dict(j => losses(M[j].P, M[j].Y) .- losses(M[j].Pc, M[j].Y) for j in lives)
    E = Dict(j => losses(saved[j].P, saved[j].Y) .- saved[j].lref for j in lives)
    D = Dict(j => ownq(saved[j].P, saved[j].Y, nothing) for j in lives)
    S = Dict(j => selset(saved[j], EPS75, w0) for j in lives); Ns = Dict(j => M[j].N for j in lives)
    WS = Dict("O-win" => Dict(j => wscores(U[j], 500) for j in lives), "REF-win" => Dict(j => wscores(E[j], 500) for j in lives),
              "C0" => Dict(j => c0scores(D[j], 500) for j in lives))
    clocks = [("O-win", TH78, (j, th) -> BitVector([!isnan(WS["O-win"][j][t]) && WS["O-win"][j][t] > th for t in 1:Ns[j]])),
              ("REF-win", TH78, (j, th) -> BitVector([!isnan(WS["REF-win"][j][t]) && WS["REF-win"][j][t] > th for t in 1:Ns[j]])),
              ("C0 w=500", TH78, (j, th) -> BitVector([!isnan(WS["C0"][j][t]) && WS["C0"][j][t] > th for t in 1:Ns[j]])),
              ("C4 delta=0.01", HSCAN, (j, h) -> firemask("C4", (delta = 0.01,), h, D[j]))]
    st1 = [j for j in lives if j[1] == 1]; st2 = [j for j in lives if j[1] == 2]
    println(io, "== B. application (descriptive; both stages seen). theta chosen on stage 1 by max min(d_LB-0.90, 0.10-f_UB), ties -> earlier grid point")
    res = Dict()
    for L in (500, 1000), (nm, grid, mk) in clocks
        best = nothing; bc = -Inf
        for th in grid
            c = counts(j -> mk(j, th), st1, Ns, S, L); v = crit(c)
            v > bc + 1e-15 && (bc = v; best = (th = th, c = c))
        end
        c1 = best.c; v1 = verdict(c1.X, c1.K, c1.Z, c1.W)
        c2 = counts(j -> mk(j, best.th), st2, Ns, S, L); v2 = verdict(c2.X, c2.K, c2.Z, c2.W); bt = boot(c2.per)
        res[(nm, L)] = (v2 = v2, c2 = c2, th = best.th)
        println(io, "  $nm L=$L theta=$(best.th): st1 X/K=$(c1.X)/$(c1.K) Z/W=$(c1.Z)/$(c1.W) d_LB=$(f4(v1.dl)) f_UB=$(f4(v1.fu)) $(v1.v) | st2 X/K=$(c2.X)/$(c2.K) Z/W=$(c2.Z)/$(c2.W) d=[$(f4(v2.dl)),$(f4(v2.du))] f=[$(f4(v2.fl)),$(f4(v2.fu))] -> $(v2.v)")
        println(io, "      st2 per life (x/k, z/w): $(join(["$(p.x)/$(p.k),$(p.z)/$(p.w)" for p in c2.per], " "))  life-bootstrap 5-95%: d [$(f4(bt.d5)), $(f4(bt.d95))] f [$(f4(bt.f5)), $(f4(bt.f95))]")
    end
    r4 = res[("O-win", 1000)].v2.v
    println(io, "S79-F4 (O-win L=1000 stage 2 undecided): $(r4 == "undecided" ? "holds" : "miss") ($r4)")
    f5 = [res[("C0 w=500", 500)].v2.v, res[("C4 delta=0.01", 500)].v2.v]
    println(io, "S79-F5 (C0 or C4 at L=500 stage 2 fail): $(any(==("fail"), f5) ? "holds" : "miss") (C0 $(f5[1]), C4 $(f5[2]))")
    # ---- sensitivity alternative: O-win L=1000 stage-2 measured rates
    o = res[("O-win", 1000)].c2; dO = o.X / o.K; fO = o.Z / o.W
    println(io, "== A'. sensitivity alternative O (O-win L=1000 stage-2 measured): d=$(f4(dO)) f=$(f4(fO))")
    for n in NGRID79
        r = powerrow(n, dO, fO); println(io, "  n=$n pass=$(f4(r.pass)) fail=$(f4(r.fail)) undec=$(f4(r.undec)) old=$(f4(oldpass(n, dO, fO)))")
    end
    s = String(take!(io)); print(s); write(joinpath(OUT79, "s79.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    ARGS[1] == "run" && run79()
end
