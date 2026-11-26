# S82 step 1: estimate of plan A (longer L) on the 48 seen lives (discussion/notes/trace1-L-vs-info.md; predictions frozen, codex S-R 13:03Z P1-P6).
# C4 (delta = 0.01, h = 13.75) frozen, counted with the official firemask; L in 1000, 1500, 2000, 3000. No new seeds.
# Includes s81_pair/s81.jl unchanged (and through it s80_main); their main blocks do not run when included.
# usage: julia --project=. -t 8 experiments/s82_L/est.jl
include(joinpath(@__DIR__, "..", "s81_pair", "s81.jl"))
const PRED82 = joinpath(@__DIR__, "predictions.toml"); const OUT82 = joinpath(@__DIR__, "out"); mkpath(OUT82)
const FREEZE82 = joinpath(@__DIR__, "..", "freeze-s82.txt")
const LS82 = [1000, 1500, 2000, 3000]; const NB82 = 10_000

function lives82()
    w0 = TOML.parsefile(W0_R3)["w0"]; s8 = seen8(); LV = []
    for j in s8.lives; push!(LV, (g = "seen8", D = s8.X[j].D, N = s8.Ns[j], S = s8.S[j])); end
    for j in 1:NL80
        r = deserialize(joinpath(OUT80R, "life_$j.jls")); r.life == life80(j) && r.seeds == seedsR(j, 2) || error("life file gate $j"); twingate(r)
        push!(LV, (g = "s80", D = ownq(r.P, r.Y, nothing), N = r.N, S = selset(r, EPS75, w0)))
    end
    return LV
end
function run82()
    h = bytes2hex(sha256(read(PRED82))); any(==("$h  experiments/s82_L/predictions.toml"), split(read(FREEZE82, String), "\n")) || error("predictions not frozen")
    TOML.parsefile(THR80)["C4 delta=0.01 L=1000"] == H81 || error("threshold gate")
    io = IOBuffer(); LV = lives82(); n = length(LV); n == 48 || error("48 lives")
    F = [firemask("C4", (delta = 0.01,), H81, x.D) for x in LV]
    ix = collect(1:n); Ns = Dict(k => LV[k].N for k in ix); S = Dict(k => LV[k].S for k in ix)
    C = Dict(L => counts(k -> F[k], ix, Ns, S, L) for L in LS82)
    (C[1000].X, C[1000].K, C[1000].Z, C[1000].W) == (125, 183, 24, 720) || error("L=1000 gate $(C[1000])")
    for x in LV; all(i -> TS[i] + 3000 <= x.N, 1:4) || error("life too short for L=3000"); end
    for (L, nw) in zip(LS82, [15, 10, 5, 5]), k in ix   # codex I-R P4: every life, every L
        p = C[L].per[k]; p.w == nw && p.k == length(LV[k].S) && length(routinewins(LV[k].N, L)) == nw || error("per-life window gate L=$L life $k")
    end
    for L in LS82; c = C[L]; (sum(p.x for p in c.per), sum(p.k for p in c.per), sum(p.z for p in c.per), sum(p.w for p in c.per)) == (c.X, c.K, c.Z, c.W) || error("per sum gate L=$L"); end
    println(io, "gate: L=1000 reproduces 125/183 and 24/720 (48 lives); routine windows per life 15, 10, 5, 5; every life covers T_4 + 3000")
    println(io, "== seen 48 lives, C4 h=13.75, official firemask (carry-in included)")
    for L in LS82
        c = C[L]; v = verdict2(c.X, c.K, c.Z, c.W)
        println(io, "  L=$L: X/K=$(c.X)/$(c.K) d=$(f4(c.X / c.K)) [$(f4(v.dl)), $(f4(v.du))]  Z/W=$(c.Z)/$(c.W) f=$(f4(c.Z / c.W)) [$(f4(v.fl)), $(f4(v.fu))] -> $(v.v) (48 seen lives; descriptive)")
        println(io, "     needed for pass at this K, W: d_LB >= max(10 f_UB, 1 - 0.1(1 - f_UB)) = $(f4(max(10v.fu, 1 - 0.1(1 - v.fu))))")
    end
    # unseen 40 lives: life bootstrap (P6) and independent binomial, same draws for every L
    rng = MersenneTwister(82); draws = [rand(rng, 1:n, 40) for _ in 1:NB82]
    ks = [length(x.S) for x in LV]; Kmean = 153
    probs = Dict()
    for L in LS82
        per = C[L].per; tal = Dict("pass" => 0, "fail" => 0, "undecided" => 0)
        for d in draws
            X = sum(per[k].x for k in d); K = sum(per[k].k for k in d); Z = sum(per[k].z for k in d); W = sum(per[k].w for k in d)
            tal[verdict2(X, K, Z, W).v] += 1
        end
        rb = MersenneTwister(820 + L); dh = C[L].X / C[L].K; fh = C[L].Z / C[L].W; Wn = 40 * length(routinewins(LV[1].N, L))
        tb = Dict("pass" => 0, "fail" => 0, "undecided" => 0)
        for _ in 1:NB82
            X = count(_ -> rand(rb) < dh, 1:Kmean); Z = count(_ -> rand(rb) < fh, 1:Wn); tb[verdict2(X, Kmean, Z, Wn).v] += 1
        end
        probs[L] = (boot = tal["pass"] / NB82, bin = tb["pass"] / NB82)
        println(io, "  unseen 40 lives, L=$L: life bootstrap pass $(f4(tal["pass"] / NB82)) fail $(f4(tal["fail"] / NB82)) undecided $(f4(tal["undecided"] / NB82)) | binomial (K=$Kmean, W=$Wn) pass $(f4(tb["pass"] / NB82)) fail $(f4(tb["fail"] / NB82)) undecided $(f4(tb["undecided"] / NB82))")
    end
    ob = sortperm(LS82, by = L -> (-probs[L].boot, L)); obn = sortperm(LS82, by = L -> (-probs[L].bin, L))
    println(io, "  order by bootstrap pass: $(LS82[ob]); by binomial pass: $(LS82[obn])$(LS82[ob] == LS82[obn] ? "" : "  (orders differ)")")
    best = LS82[ob[1]]; e1 = all(L -> probs[L].boot < 0.5, LS82)
    println(io, "selection: $(e1 ? "no L reaches bootstrap pass 0.5 -> plan A does not go to step 2; back to the user" : "L = $best (bootstrap pass $(f4(probs[best].boot)))")")
    d = [C[L].X / C[L].K for L in LS82]; f = [C[L].Z / C[L].W for L in LS82]
    e2 = d[1] < d[2] < d[3] <= d[4] && f[1] < f[2] < f[3] <= f[4]
    println(io, "S82-E1 (no L reaches bootstrap pass 0.5): $(e1 ? "hit" : "miss")")
    println(io, "S82-E2 (d and f both increase with L): $(e2 ? "hit" : "miss")  d $(join(f4.(d), " ")) f $(join(f4.(f), " "))")
    println(io, "note: seen lives only (development estimate). The chosen L must be judged on unseen lives; thresholds h = 13.75 were chosen at L = 1000.")
    s = String(take!(io)); print(s); write(joinpath(OUT82, "est.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    run82()
end
