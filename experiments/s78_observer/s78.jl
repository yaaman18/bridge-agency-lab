# S78 (discussion/specs/S78-draft-ideal-observer.md): a map-knowing reference observer O (L-FGT twin with the map fixed at maps[1])
# as a diagnostic of whether the TRACE-1 contract is inside what the stream carries. Seen lives only (stage 1 and stage 2); 1600-1617 unopened.
# Includes s77.jl (and through it s76, s75) unchanged.
# usage: julia --project=. -t 4 experiments/s78_observer/s78.jl run
include(joinpath(@__DIR__, "..", "s77_reread", "s77.jl"))

const OUT78 = joinpath(@__DIR__, "out"); mkpath(OUT78)
const PRED78 = joinpath(@__DIR__, "predictions.toml")
const DELTA78 = [0.0, 0.005, 0.01]; const H78 = collect(0.25:0.25:60.0); const TH78 = collect(0.0:0.0005:0.1)

# main stream with the twin Lc (map fixed at maps[1]); same cuts as run_life4 / S75 mainrun
function mainrun78(life, stage)
    seeds = stage == 1 ? SEEDS_ST1 : SEEDS_ST2
    streams = Dict(u => stream2(u) for u in seeds)
    lf = make_life2(life, seeds, streams); maps, _ = life_maps(life)
    N = lf.N; pts = main_points(N); bounds = vcat(0, TS, N)
    L = new_learner("FGT", life); Lc = new_learner("FGT", life)
    P = Float64[]; Pc = Float64[]; Y = Bool[]; h1 = ""; hc1 = ""
    for seg in 1:5
        a, b = bounds[seg], bounds[seg+1]; m = maps[seg]
        seg == 2 && (h1 = statehash(L); hc1 = statehash(Lc))
        cur = a
        for c in vcat([t for t in pts if a < t < b], b)
            ps, ys = span!(L, lf, cur + 1, c + 1, m); append!(P, ps); append!(Y, ys)
            qs, zs = span!(Lc, lf, cur + 1, c + 1, maps[1]); append!(Pc, qs); zs == ys || error("twin saw different outcomes")
            cur = c
        end
    end
    return (N = N, P = P, Pc = Pc, Y = Y, sameT1 = h1 == hc1)
end

wscores(x, w) = (s = fill(NaN, length(x)); for t in PSTEP:PSTEP:length(x); t >= w && (s[t] = mean(view(x, t-w+1:t))); end; s)
function cusummask(u, δ, h)
    f = falses(length(u)); m = 0.0; M = 0.0
    for t in eachindex(u)
        m += u[t] - δ; M = min(M, m)
        if t % PSTEP == 0 && m - M > h; f[t] = true; m = 0.0; M = 0.0; end
    end
    return f
end

function run78()
    isfile(PRED78) || error("predictions not frozen: $PRED78")
    w0 = TOML.parsefile(W0_R3)["w0"]; io = IOBuffer()
    lives = [(st, l) for st in (1, 2) for l in 1:NLIFE]
    saved = Dict(j => loadlife4(j[1], "FGT", j[2]) for j in lives)
    M = Dict(zip(lives, tmapv(j -> mainrun78(j[2], j[1]), lives)))
    for j in lives   # gates
        x = M[j]; s = saved[j]
        reinterpret(UInt64, x.P) == reinterpret(UInt64, s.P) && x.Y == s.Y || error("main stream differs from saved S72 r4 FGT $j")
        reinterpret(UInt64, x.P[1:TS[1]]) == reinterpret(UInt64, x.Pc[1:TS[1]]) && x.sameT1 || error("twin differs from L before T_1 $j")
    end
    U = Dict(j => losses(M[j].P, M[j].Y) .- losses(M[j].Pc, M[j].Y) for j in lives)
    for j in lives; all(==(0.0), U[j][1:TS[1]]) || error("u != 0 before T_1 $j"); end
    E = Dict(j => losses(saved[j].P, saved[j].Y) .- saved[j].lref for j in lives)
    S = Dict(j => selset(saved[j], EPS75, w0) for j in lives); Ns = Dict(j => M[j].N for j in lives)
    println(io, "gates: main P,Y == saved S72 r4 FGT (8 lives, bitwise); twin == L and u == 0 on [1, T_1], states equal at T_1 (8)")
    println(io, "selected: " * join(["st$(j[1]) life $(j[2]) $(S[j])" for j in lives], "; "))
    for j in lives
        println(io, "  st$(j[1]) life $(j[2]) u on formation windows (mean over [T+1,T+500]): $(join(["$i:$(f4(mean(U[j][TS[i]+1:TS[i]+500])))" for i in 1:4], " "))  routine mean u: $(f4(mean(mean(U[j][w]) for w in routinewins(Ns[j], 500))))")
    end
    # ---- separability, per L
    gapO = Dict(); gapR = Dict()
    for L in LS
        println(io, "== L=$L")
        for (nm, X) in (("O-win", U), ("REF-win", E))
            scs = [wscores(X[j], 500) for j in lives]
            r = sepcheck(scs, [Ns[j] for j in lives], [S[j] for j in lives], L)
            println(io, "  $nm: R_l $(join(f4.(r.R), " ")) | F_l $(join(f4.(r.F), " ")) | common theta (8 lives): $(r.ok)$(r.ok ? " [$(f4(r.lo)), $(f4(r.hi)))" : "")")
            println(io, "    per life separable alone: $(join([r.R[k] < r.F[k] for k in eachindex(lives)], " "))")
            for st in (1, 2)
                ix = [k for (k, j) in enumerate(lives) if j[1] == st]
                ok = maximum(r.R[ix]) < minimum(r.F[ix])
                println(io, "    stage $st only: common theta: $ok$(ok ? " [$(f4(maximum(r.R[ix]))), $(f4(minimum(r.F[ix]))))" : "")")
            end
            L == 500 && (nm == "O-win" ? (gapO[:v] = r.F .- r.R) : (gapR[:v] = r.F .- r.R))
            if r.ok && nm == "O-win"   # gate with the fire rule
                th = (r.lo + r.hi) / 2
                all(k -> judgeL(BitVector([!isnan(scs[k][t]) && scs[k][t] > th for t in 1:Ns[lives[k]]]), Ns[lives[k]], S[lives[k]], L).ok, eachindex(lives)) || error("gate failed")
            end
        end
        cnt = Dict((δ, h) => (count(j -> j[1] == 1 && judgeL(cusummask(U[j], δ, h), Ns[j], S[j], L).ok, lives),
                              count(j -> j[1] == 2 && judgeL(cusummask(U[j], δ, h), Ns[j], S[j], L).ok, lives)) for δ in DELTA78 for h in H78)   # codex I-R P3
        nall = [k for δ in DELTA78 for h in H78 for k in ((δ, h),) if sum(cnt[k]) == 8]
        for δ in DELTA78
            bk = argmax(h -> sum(cnt[(δ, h)]), H78)
            println(io, "  O-cusum delta=$δ: best h=$bk passes (st1, st2) = $(cnt[(δ, bk)]); h with st1 4/4: $(count(h -> cnt[(δ, h)][1] == 4, H78)), with st2 4/4: $(count(h -> cnt[(δ, h)][2] == 4, H78))")
        end
        open(joinpath(OUT78, "cusum_L$L.tsv"), "w") do f
            println(f, "delta\th\tst1_pass\tst2_pass"); for δ in DELTA78, h in H78; println(f, "$δ\t$h\t$(cnt[(δ, h)][1])\t$(cnt[(δ, h)][2])"); end
        end
        println(io, "  O-cusum: (delta,h) passing all 8: $(isempty(nall) ? "none" : join(nall[1:min(end, 10)], " "))$(length(nall) > 10 ? " ... ($(length(nall)))" : "")")
        L == 500 && (gapO[:cusum8] = !isempty(nall))
    end
    # E1: O-win no common theta at L=500 and O-cusum none at L=500
    scs500 = [wscores(U[j], 500) for j in lives]; r500 = sepcheck(scs500, [Ns[j] for j in lives], [S[j] for j in lives], 500)
    e1 = !r500.ok && !gapO[:cusum8]
    nimp = count(k -> gapO[:v][k] > gapR[:v][k], eachindex(lives))
    println(io, "E1 (L=500: O-win no common theta over 8 lives, O-cusum none): $(e1 ? "holds" : "miss")  [O-win common: $(r500.ok), O-cusum all-8: $(gapO[:cusum8])]")
    println(io, "E2 (F-R larger for O-win than REF-win in >= 6/8): $(nimp >= 6 ? "holds" : "miss") ($nimp/8)  O: $(join(f4.(gapO[:v]), " ")) REF: $(join(f4.(gapR[:v]), " "))")
    # ---- E3: binomial model on the O-win window clock (L=500)
    println(io, "== E3 model (O-win, L=500): pooled d(theta) over selected switches of 8 lives, f(theta) over 120 routine windows")
    best = Dict(1 => (-1.0, NaN), 2 => (-1.0, NaN))   # first grid point always recorded (codex I-R P2)
    for th in TH78
        js = Dict(j => judgeL(BitVector([!isnan(scs500[k][t]) && scs500[k][t] > th for t in 1:Ns[j]]), Ns[j], S[j], 500) for (k, j) in enumerate(lives))
        ndet = sum(round(Int, js[j].det_sel * length(S[j])) for j in lives); nsel = sum(length(S[j]) for j in lives)
        nf = sum(js[j].nfalse for j in lives); d = ndet / nsel; f = nf / 120
        g = (1 - f)^15 + 15f * (1 - f)^14
        q = Dict(st => prod(d^length(S[j]) * g for j in lives if j[1] == st) for st in (1, 2))
        obs = Dict(st => count(j -> j[1] == st && js[j].ok, lives) for st in (1, 2))
        for st in (1, 2); q[st] > best[st][1] && (best[st] = (q[st], th)); end
        println(io, "  theta=$(th) d=$(f4(d)) f=$(f4(f)) q4 st1=$(f4(q[1])) st2=$(f4(q[2]))  observed lives passing st1 $(obs[1])/4 st2 $(obs[2])/4")
    end
    println(io, "  max q4: stage 1 $(f4(best[1][1])) at theta=$(best[1][2]); stage 2 $(f4(best[2][1])) at theta=$(best[2][2])  (model: independence and equal rates; theta chosen on the same sample)")
    println(io, "E3 (max model 4-life pass prob < 0.5 for both stages): $(best[1][1] < 0.5 && best[2][1] < 0.5 ? "holds" : "miss")")
    s = String(take!(io)); print(s); write(joinpath(OUT78, "s78.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    ARGS[1] == "run" && run78()
end
