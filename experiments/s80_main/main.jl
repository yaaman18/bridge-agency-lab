# S80 confirmation (discussion/specs/S80-draft-trace1-confirm.md §1-§6; predictions frozen in predictions.toml, codex S-R 12:06Z).
# 40 lives, life j uses seeds 2300 + 12(j-1) .. +11 in order (no ring, disjoint), life number ℓ = 4 + j. L-FGT. Main clock C4 (delta = 0.01), L = 1000.
# Includes s80_desc/desc.jl unchanged (and through it s80_diag, s79b, s79, s78, s77, s76, s75, s72r4); their main blocks do not run when included.
# usage: julia --project=. -t 8 experiments/s80_main/main.jl thresh   (seen lives only: code-path gates, thresholds -> out/thresholds.toml)
#        julia --project=. -t 8 experiments/s80_main/main.jl run      (opens seeds 2300-2779 and, by revision 1 (spec §11.1), 2780-2899 as needed;
#                                                                        needs predictions, thresholds and revision1.toml whose sha is in freeze-s80.txt; writes out/rev1/)
include(joinpath(@__DIR__, "..", "s80_desc", "desc.jl"))
using SHA
const PRED80M = joinpath(@__DIR__, "predictions.toml"); const OUT80M = joinpath(@__DIR__, "out"); mkpath(OUT80M)
const STR80 = joinpath(OUT80M, "streams"); mkpath(STR80)
const THR80 = joinpath(OUT80M, "thresholds.toml"); const FREEZE80 = joinpath(@__DIR__, "..", "freeze-s80.txt")
const NL80 = 40; const SEED0 = 2300
seeds80(j) = collect(SEED0 + 12(j - 1) : SEED0 + 12(j - 1) + 11)
life80(j) = 4 + j
# revision 1 (spec §11.1, revision1.toml): round r adds seed 2780 + 40(r - 1) + (j - 1) to life j, after its 12 seeds
const REV1 = joinpath(@__DIR__, "revision1.toml"); const OUT80R = joinpath(OUT80M, "rev1"); mkpath(OUT80R)
const SEEDX0 = 2780; const KMAX80 = 3
seedsR(j, k) = vcat(seeds80(j), [SEEDX0 + NL80 * (r - 1) + (j - 1) for r in 1:k])
needN() = max(TS[end] + BDD_OFF + LB, TS[end] + CAP)

function stream80(u)
    (u in SEEDS_ST1 || u in SEEDS_ST2 || 1600 <= u <= 1617) && error("seen or reserved seed $u")
    2300 <= u <= SEEDX0 + NL80 * KMAX80 - 1 || error("seed $u outside the approved range 2300-$(SEEDX0 + NL80 * KMAX80 - 1)")
    f = joinpath(STR80, "stream_$u.jls"); isfile(f) && return deserialize(f)
    st = obs_stream(u, "stat"); serialize(f, st); return st
end
function make_life3(seeds, streams)   # the 12 seeds in the given order (make_life2 without the ring)
    sts = [streams[u] for u in seeds]
    ex = Tuple{Int,Int}[]
    for (i, st) in enumerate(sts), s in 0:NS-1
        st.isex[s+1] && push!(ex, (i, s))
    end
    N = BLK * (length(ex) ÷ BLK)
    return Life(sts, ex[1:N], N)
end
# s75 mainrun's main loop on a given life, plus the S78 twin Lc (map fixed at maps[1]) in the same pass
function mainrun80(life, lf)
    maps, _ = life_maps(life); plf = probe_life(life)
    N = lf.N; N >= TS[end] + BDD_OFF + LB && N >= TS[end] + CAP || error("life too short: life $life N $N")
    pts = main_points(N); bounds = vcat(0, TS, N)
    L = new_learner("FGT", life); Ls = TabL(zeros(2), zeros(2), zeros(130), zeros(130), LAM_SLOW); REF = new_learner("CUM", life)
    Lc = new_learner("FGT", life)
    P = Float64[]; Y = Bool[]; Ps = Float64[]; ℓref = Float64[]; Pc = Float64[]; h1 = ""; hc1 = ""
    pL = Dict{Int,Vector{Float64}}(); pR = Dict{Int,Vector{Float64}}(); pNew = Dict{Int,Vector{Float64}}()
    for seg in 1:5
        a, b = bounds[seg], bounds[seg+1]; m = maps[seg]
        seg >= 2 && (pNew[seg-1] = probe(L, plf, m))
        seg == 2 && (h1 = statehash(L); hc1 = statehash(Lc))
        cur = a
        for c in vcat([t for t in pts if a < t < b], b)
            ps, ys = span!(L, lf, cur + 1, c + 1, m); append!(P, ps); append!(Y, ys)
            qs, zs = span!(Ls, lf, cur + 1, c + 1, m); append!(Ps, qs); zs == ys || error("slow twin saw different outcomes")
            rp, ry = span!(REF, lf, cur + 1, c + 1, ID); append!(ℓref, losses(rp, ry))
            cq, cz = span!(Lc, lf, cur + 1, c + 1, maps[1]); append!(Pc, cq); cz == ys || error("twin saw different outcomes")
            if c in TS; pL[c] = probe(L, plf, m); pR[c] = probe(REF, plf, ID); end
            cur = c
        end
    end
    return (kind = "FGT", life = life, N = N, P = P, Y = Y, Pslow = Ps, lref = ℓref, pL = pL, pR = pR, pNew = pNew,
            Pc = Pc, sameT1 = h1 == hc1, seeds = [s.seed for s in lf.streams])
end
bits(x) = reinterpret(UInt64, x)
twingate(r) = r.sameT1 && bits(r.P[1:TS[1]]) == bits(r.Pc[1:TS[1]]) || error("twin gate life $(r.life)")

# clocks: name => (grid, mask(life data, threshold))
function clockdata(r)
    D = ownq(r.P, r.Y, nothing); U = losses(r.P, r.Y) .- losses(r.Pc, r.Y)
    all(==(0.0), U[1:TS[1]]) || error("twin gate u = 0 on [1, T_1], life $(r.life)")
    return (D = D, so = wscores(U, 500), sc = c0scores(D, 500))
end
const CLK = ["C4 delta=0.01", "C0 w=500", "O-win"]
function mask80(nm, x, th)
    nm == "C4 delta=0.01" && return firemask("C4", (delta = 0.01,), th, x.D)
    s = nm == "O-win" ? x.so : x.sc
    return BitVector([!isnan(s[t]) && s[t] > th for t in 1:x.D.N])
end
grid80(nm) = nm == "C4 delta=0.01" ? HSCAN : TH78

# ρ̂ by moments (§5): p = Σx/Σm, q = Σx(x-1)/Σm(m-1), ρ = (q - p²)/(p(1-p)); nothing if not estimable
function rhohat(xs, ms)
    p = sum(xs) / sum(ms); dm = sum(m * (m - 1) for m in ms); den = p * (1 - p)
    (dm == 0 || den == 0) && return nothing
    return (sum(x * (x - 1) for x in xs) / dm - p^2) / den
end
# V6 matching rule (same as s80_desc B): per life, D = a_f - median(a_r) over same-life routine windows with |n0_r - n0_f| <= 1 and n0 > 0
function brule(Y, c, ℓ, N, S)
    n0(w) = count(!, view(Y, w))
    ab(w) = (z = [t for t in w if !Y[t]]; isempty(z) ? nothing : (a = mean(c[z]), b = mean(ℓ[z])))
    rs = [(w, n0(w), ab(w)) for w in routinewins(N, L80)]
    out = []
    for i in S
        w = formwin(i, L80); nf = n0(w); af = ab(w)
        cand = [r for r in rs if r[3] !== nothing && abs(r[2] - nf) <= 1]
        if af === nothing || isempty(cand)
            push!(out, (i = i, n0 = nf, held = af === nothing ? "a_f undefined (n0 = 0)" : "no candidate")); continue
        end
        exact = [r for r in cand if r[2] == nf]
        push!(out, (i = i, n0 = nf, held = nothing, af = af.a, D = af.a - median([r[3].a for r in cand]),
                    Db = af.b - median([r[3].b for r in cand]), ncand = length(cand),
                    De = isempty(exact) ? nothing : af.a - median([r[3].a for r in exact]), used = [first(r[1]) for r in cand]))
    end
    v = [o.D for o in out if o.held === nothing]
    return (rows = out, med = isempty(v) ? nothing : median(v), nvalid = length(v), nheld = length(out) - length(v))
end
v5verdict(r) = any(x -> x !== nothing && x > 0.3, r) ? "miss" : all(x -> x !== nothing, r) ? "hit" : "held"   # codex I-R P4
v6counts(meds) = (count(m -> m !== nothing && m > 0, meds), count(m -> m !== nothing && m <= 0, meds), count(isnothing, meds))   # codex I-R P1
v6verdict(meds) = any(m -> m !== nothing && m <= 0, meds) ? "miss" : all(m -> m !== nothing && m > 0, meds) ? "hit" : "held"
browline(j, o) = o.held === nothing ?
    "$(j): i=$(o.i) n0=$(o.n0): a_f=$(f4(o.af)) D=$(f4(o.D)) Db=$(f4(o.Db)) candidates=$(o.ncand) exact-D=$(o.De === nothing ? "-" : f4(o.De))" :
    "$(j): i=$(o.i) n0=$(o.n0): held ($(o.held))"

function seen8()
    w0 = TOML.parsefile(W0_R3)["w0"]
    lives = [(st, l) for st in (1, 2) for l in 1:NLIFE]
    saved = Dict(j => loadlife4(j[1], "FGT", j[2]) for j in lives)
    M = Dict(zip(lives, tmapv(j -> mainrun78(j[2], j[1]), lives)))
    for j in lives; bits(M[j].P) == bits(saved[j].P) && M[j].Y == saved[j].Y || error("main stream differs $j"); end
    X = Dict(j => (D = ownq(saved[j].P, saved[j].Y, nothing), so = wscores(losses(M[j].P, M[j].Y) .- losses(M[j].Pc, M[j].Y), 500),
                   sc = c0scores(ownq(saved[j].P, saved[j].Y, nothing), 500)) for j in lives)
    S = Dict(j => selset(saved[j], EPS75, w0) for j in lives); Ns = Dict(j => saved[j].N for j in lives)
    return (w0 = w0, lives = lives, saved = saved, M = M, X = X, S = S, Ns = Ns)
end

# codex I-R P7: the freeze file must hold the exact line "<sha256>  <path>" for the file
frozen(path, rel) = (h = bytes2hex(sha256(read(path))); any(==("$h  $rel"), split(read(FREEZE80, String), "\n")))
function thresh80()
    frozen(PRED80M, "experiments/s80_main/predictions.toml") || error("predictions not frozen: $PRED80M")
    io = IOBuffer(); s8 = seen8(); w0 = s8.w0
    # gate: allocation (codex S-R P5, P7)
    al80 = [seeds80(j) for j in 1:NL80]
    vcat(al80...) == collect(2300:2779) && all(j -> al80[j] == [2300 + 12(j - 1) + t - 1 for t in 1:12], 1:NL80) || error("allocation gate")
    isempty(intersect(Set(vcat(al80...)), Set(vcat(SEEDS_ST1, SEEDS_ST2, collect(1600:1617))))) || error("allocation overlaps seen/reserved")
    [life80(j) for j in 1:NL80] == collect(5:44) && MAPSEED + 44 < RINGSEED || error("life number gate")
    println(io, "gate: seeds 2300-2779 in order, 12 per life, disjoint from 1050-1067, 1300-1317, 1600-1617; life numbers 5-44")
    # gate: code path. mainrun80 on the stage-1 ring lives 1-4 == saved FGT (P, Y, lref bitwise), Pc == mainrun78, selset == saved
    st = Dict(u => stream2(u) for u in SEEDS_ST1)
    for l in 1:NLIFE   # codex I-R P3: make_life3 on the ring order == make_life2 (N and the (i, s) list)
        a = make_life2(l, SEEDS_ST1, st); b = make_life3([SEEDS_ST1[mod(l - 1 + k, 18) + 1] for k in 0:11], st)
        a.N == b.N && a.ex == b.ex && [x.seed for x in a.streams] == [x.seed for x in b.streams] || error("make_life3 gate life $l")
    end
    R = tmapv(l -> mainrun80(l, make_life2(l, SEEDS_ST1, st)), collect(1:NLIFE))
    for l in 1:NLIFE
        r = R[l]; s = s8.saved[(1, l)]
        bits(r.P) == bits(s.P) && r.Y == s.Y && bits(r.lref) == bits(s.lref) || error("code-path gate P/Y/lref life $l")
        bits(r.Pc) == bits(s8.M[(1, l)].Pc) || error("code-path gate Pc life $l")
        selset(r, EPS75, w0) == s8.S[(1, l)] || error("code-path gate selset life $l")
        twingate(r); clockdata(r)
    end
    println(io, "gate: mainrun80 on stage-1 lives 1-4 == saved FGT P, Y, lref (bitwise), Pc == mainrun78, selset == saved; twin gates pass")
    # gate: B rule reproduces s80_desc rows on the seen lives (codex S-R P7)
    # codex I-R P6: whole lines of the B section of desc.out, with multiplicity, against ours
    dl = split(read(joinpath(OUT80E, "desc.out"), String), "\n"); ia = findfirst(startswith("== B:"), dl); ib = findfirst(startswith("== C:"), dl)
    ref = [l for l in dl[ia+1:ib-1] if startswith(l, "  st") || startswith(l, "  [life]")]
    ours = String[]; nv = 0; meds = []
    for j in s8.lives
        b = brule(s8.saved[j].Y, c4inc(s8.X[j].D.ℓ), s8.X[j].D.ℓ, s8.Ns[j], s8.S[j]); nv += b.nvalid; push!(meds, b.med)
        for o in b.rows
            o.held === nothing ? push!(ours, "  st$(j[1]) life $(j[2]) i=$(o.i) n0=$(o.n0): a_f=$(f4(o.af)) D=$(f4(o.D)) Db=$(f4(o.Db)) candidates=$(o.ncand) exact-D=$(o.De === nothing ? "-" : f4(o.De))") :
                                 push!(ours, "  st$(j[1]) life $(j[2]) i=$(o.i) n0=$(o.n0): held ($(o.held))")
        end
        es = [o.De for o in b.rows if o.held === nothing && o.De !== nothing]; em = isempty(es) ? nothing : median(es)
        push!(ours, "  [life] st$(j[1]) life $(j[2]): valid formation $(b.nvalid), routine windows used $(length(unique(vcat([o.used for o in b.rows if o.held === nothing]...)))), median D $(b.med === nothing ? "-" : f4(b.med)), exact-n0 sign $(em === nothing ? "held" : em > 0 ? "+" : em < 0 ? "-" : "0")")
    end
    sort(ours) == sort(ref) || error("B rule gate: lines differ\n" * join(setdiff(ours, ref), "\n") * "\n--\n" * join(setdiff(ref, ours), "\n"))
    nv == 25 && v6verdict(meds) == "hit" && length(meds) == 8 || error("B pooled gate")
    v6counts([1.0, 0.0, nothing]) == (1, 1, 1) || error("V6 count gate")
    v5verdict((0.3, 0.3)) == "hit" && v5verdict((0.3, nothing)) == "held" && v5verdict((nothing, 0.31)) == "miss" || error("V5 gate")
    v6verdict([1.0, -0.1, nothing]) == "miss" && v6verdict([1.0, 2.0, 0.0]) == "miss" && v6verdict([1.0, nothing]) == "held" && v6verdict([1.0, 2.0]) == "hit" || error("V6 boundary gate")
    println(io, "gate: B rule reproduces every s80_desc B row and per-life line (8 lives, 25 valid); V6 boundary cases (negative + empty -> miss, one zero -> miss, empty -> held)")
    # thresholds: crit2 max over the pooled 8 seen lives, ties -> earlier grid point; independent recomputation by findmax
    thr = Dict{String,Any}()
    for L in (1000, 500), nm in CLK
        g = grid80(nm); cs = [counts(j -> mask80(nm, s8.X[j], th), s8.lives, s8.Ns, s8.S, L) for th in g]
        best = nothing; bc = -Inf
        for (k, th) in enumerate(g); v = crit2(cs[k]); v > bc && (bc = v; best = k); end
        k2 = findmax(crit2.(cs))[2]; k2 == best || error("threshold recomputation differs $nm L=$L")
        c = cs[best]; v = verdict2(c.X, c.K, c.Z, c.W)
        let X = 0, K = 0, Z = 0, W = 0   # codex I-R P8: recount without counts/judgeL
            for j in s8.lives
                f = mask80(nm, s8.X[j], g[best])
                for w in routinewins(s8.Ns[j], L); W += 1; Z += any(f[t] for t in w); end
                for i in s8.S[j]; K += 1; X += any(f[t] for t in TS[i]+1:TS[i]+L); end
            end
            (X, K, Z, W) == (c.X, c.K, c.Z, c.W) || error("recount gate $nm L=$L")
        end
        thr["$(nm) L=$L"] = g[best]
        println(io, "  threshold $nm L=$L: $(g[best])  (seen 8: $(c.X)/$(c.K) $(c.Z)/$(c.W) -> $(v.v))")
    end
    open(THR80, "w") do f; TOML.print(f, thr); end
    TOML.parsefile(THR80) == thr || error("threshold TOML reload gate")
    println(io, "thresholds written: $THR80 (sha256 $(bytes2hex(sha256(read(THR80)))))")
    s = String(take!(io)); print(s); write(joinpath(OUT80M, "thresh.out"), s)
end

function run80m()
    frozen(PRED80M, "experiments/s80_main/predictions.toml") || error("predictions not frozen")
    frozen(THR80, "experiments/s80_main/out/thresholds.toml") || error("thresholds.toml sha not in freeze-s80.txt")
    sh = bytes2hex(sha256(read(THR80)))
    thr = TOML.parsefile(THR80); io = IOBuffer(); w0 = TOML.parsefile(W0_R3)["w0"]
    println(io, "thresholds $sh: $(join(["$k=$(thr[k])" for k in sort(collect(keys(thr)))], ", "))")
    frozen(REV1, "experiments/s80_main/revision1.toml") || error("revision1.toml not frozen")
    rv = TOML.parsefile(REV1)
    (rv["first_seed"], rv["per_round"], rv["kmax"], rv["last_seed_max"], rv["need_N"]) == (SEEDX0, NL80, KMAX80, SEEDX0 + NL80 * KMAX80 - 1, needN()) || error("revision1 constants gate")
    al = [seedsR(j, KMAX80) for j in 1:NL80]   # allocation gate for revision 1
    sort(vcat(al...)) == collect(2300:SEEDX0 + NL80 * KMAX80 - 1) && all(j -> al[j][1:12] == seeds80(j), 1:NL80) &&
        all(j -> al[j][13:end] == [2780 + 40(r - 1) + j - 1 for r in 1:KMAX80], 1:NL80) || error("revision1 allocation gate")
    foreach(pstream, PROBE_SEEDS)                      # serial cache before threads
    tmapv(stream80, collect(2300:2779))
    # revision 1: smallest k >= 1 with every life N >= need; open round r's seeds only when round r is reached
    k = 0; Nk = Int[]
    for kk in 1:KMAX80
        tmapv(stream80, collect(SEEDX0 + NL80 * (kk - 1) : SEEDX0 + NL80 * kk - 1))
        Nk = [make_life3(seedsR(j, kk), Dict(u => stream80(u) for u in seedsR(j, kk))).N for j in 1:NL80]
        println(io, "revision 1, k = $kk: N per life $(join(Nk, " ")); short $(count(<(needN()), Nk)), min $(minimum(Nk))")
        all(>=(needN()), Nk) && (k = kk; break)
    end
    if k == 0
        s = String(take!(io)); print(s); write(joinpath(OUT80R, "run.out"), s)
        error("revision 1: some life still N < $(needN()) at k = $KMAX80; stop again")
    end
    pre = count(j -> isfile(joinpath(OUT80R, "life_$j.jls")), 1:NL80)   # codex I-R 12:21Z P5
    println(io, "revision 1: life files already in out/rev1 at start: $pre (0 = all 40 lives computed in this run)")
    println(io, "revision 1: k = $k (each life $(12 + k) seeds, added $(SEEDX0)-$(SEEDX0 + NL80 * k - 1)); need N >= $(needN())")
    R = tmapv(j -> (f = joinpath(OUT80R, "life_$j.jls"); isfile(f) ? deserialize(f) :
                    (r = mainrun80(life80(j), make_life3(seedsR(j, k), Dict(u => stream80(u) for u in seedsR(j, k)))); serialize(f, r); r)), collect(1:NL80))
    for j in 1:NL80
        r = R[j]; r.life == life80(j) && r.seeds == seedsR(j, k) && r.N == Nk[j] || error("allocation gate on run: life $j seeds $(r.seeds)")
        twingate(r)
    end
    println(io, "gate: every life used its 12 seeds 2300+12(j-1).. then 2780+40(r-1)+(j-1) for r = 1..$k, life number 4+j; twin gates pass (40 lives)")
    lives = collect(1:NL80); X = Dict(j => clockdata(R[j]) for j in lives)
    S = Dict(j => selset(R[j], EPS75, w0) for j in lives); Ns = Dict(j => R[j].N for j in lives)
    ktot = sum(length(S[j]) for j in lives)
    println(io, "selected switches: total $ktot, per life $(join([length(S[j]) for j in lives], " "))")
    res = Dict(); rho = Dict()
    for L in (1000, 500), nm in CLK
        th = thr["$(nm) L=$L"]; c = counts(j -> mask80(nm, X[j], th), lives, Ns, S, L); v = verdict2(c.X, c.K, c.Z, c.W)
        res[(nm, L)] = v.v; b = boot(c.per; rng = MersenneTwister(80))
        rd = rhohat([p.x for p in c.per], [p.k for p in c.per]); rf = rhohat([p.z for p in c.per], [p.w for p in c.per])
        rho[(nm, L)] = (rd, rf)
        println(io, "== $nm L=$L$(L == 1000 ? "" : " (descriptive)") θ=$th: X/K=$(c.X)/$(c.K) Z/W=$(c.Z)/$(c.W) d=[$(f4(v.dl)),$(f4(v.du))] f=[$(f4(v.fl)),$(f4(v.fu))] -> $(v.v)$(nm == "C4 delta=0.01" && L == 1000 ? " (TRACE-1, main)" : " (descriptive)")")
        println(io, "   bootstrap over lives (2000, seed 80) d 5-95% [$(f4(b.d5)), $(f4(b.d95))] f 5-95% [$(f4(b.f5)), $(f4(b.f95))]; ρ̂ detection $(rd === nothing ? "not estimable" : f4(rd)), false $(rf === nothing ? "not estimable" : f4(rf))")
        L == 1000 && println(io, "   per life x/k z/w: $(join(["$(p.x)/$(p.k) $(p.z)/$(p.w)" for p in c.per], " | "))")
    end
    meds = []
    println(io, "== V6 (B rule, C4 c_t)")
    for j in lives
        b = brule(R[j].Y, c4inc(X[j].D.ℓ), X[j].D.ℓ, Ns[j], S[j]); push!(meds, b.med)
        for o in b.rows; println(io, "  " * browline("life $j", o)); end
        println(io, "  [life $j] valid $(b.nvalid) held $(b.nheld) median D $(b.med === nothing ? "-" : f4(b.med))")
    end
    length(meds) == NL80 || error("V6: $(length(meds)) lives scored")   # codex I-R P5
    pos, nonpos, emp = v6counts(meds)
    println(io, "  lives: positive $pos, <= 0 $nonpos, no valid window $emp")
    r4 = rho[("C4 delta=0.01", 1000)]
    v5 = v5verdict(r4)
    println(io, "S80-V1 (C4 L=1000 fail): $(res[("C4 delta=0.01", 1000)] == "fail" ? "hit" : "miss")  $(res[("C4 delta=0.01", 1000)])")
    println(io, "S80-V2 (O-win L=1000 pass): $(res[("O-win", 1000)] == "pass" ? "hit" : "miss")  $(res[("O-win", 1000)])")
    println(io, "S80-V3 (C0 L=1000 fail): $(res[("C0 w=500", 1000)] == "fail" ? "hit" : "miss")  $(res[("C0 w=500", 1000)])")
    println(io, "S80-V4 (mean selected per life in [3.0, 4.0]): $(3.0 <= ktot / NL80 <= 4.0 ? "hit" : "miss")  $(ktot / NL80)")
    println(io, "S80-V5 (C4 ρ̂ <= 0.3 both): $v5")
    println(io, "S80-V6 (median D > 0 in all 40 lives): $(v6verdict(meds))")
    println(io, "note: the verdicts assume independence of switches and routine windows; the probe ring 1500-1505 is shared by all lives")
    s = String(take!(io)); print(s); write(joinpath(OUT80R, "run.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    ARGS[1] == "thresh" ? thresh80() : ARGS[1] == "run" ? run80m() : error("thresh | run")
end
