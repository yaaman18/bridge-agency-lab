# S80 diagnostic (discussion/specs/S80-draft-trace1-confirm.md §10): where do C4 (delta=0.01, L=1000) routine false fires sit,
# relative to seed boundaries and Y=0 bursts? Seen lives only (stage 1 seeds 1050-1067, stage 2 1300-1317). No new seeds.
# Includes s79b.jl unchanged (its main block does not run when included).
# usage: julia --project=. -t 4 experiments/s80_diag/diag.jl
include(joinpath(@__DIR__, "..", "s79_rates", "s79b.jl"))
const PRED80D = joinpath(@__DIR__, "predictions.toml"); const OUT80D = joinpath(@__DIR__, "out"); mkpath(OUT80D)
const L80 = 1000; const NEAR = 1000; const Y0WIN = 500

function boundaries(stage, life)
    seeds = stage == 1 ? SEEDS_ST1 : SEEDS_ST2
    lf = make_life2(life, seeds, Dict(u => stream2(u) for u in seeds))
    return lf, [t for t in 2:lf.N if lf.ex[t][1] != lf.ex[t-1][1]]
end
dist(t, bs) = (k = searchsortedlast(bs, t); k == 0 ? t : t - bs[k])
y0before(Y, t) = count(!, view(Y, max(1, t - Y0WIN + 1):t))   # the 500 examples ending at t, t included (C4 at t has seen ℓ_t; codex I-R P4)

function run80d()
    isfile(PRED80D) || error("predictions not frozen: $PRED80D")
    io = IOBuffer(); w0 = TOML.parsefile(W0_R3)["w0"]
    lives = [(st, l) for st in (1, 2) for l in 1:NLIFE]
    saved = Dict(j => loadlife4(j[1], "FGT", j[2]) for j in lives)
    D = Dict(j => ownq(saved[j].P, saved[j].Y, nothing) for j in lives)
    S = Dict(j => selset(saved[j], EPS75, w0) for j in lives); Ns = Dict(j => D[j].N for j in lives)
    B = Dict(j => boundaries(j...) for j in lives)
    for j in lives   # gate: the rebuilt life has the saved length and outcomes
        lf = B[j][1]; lf.N == Ns[j] || error("N mismatch $j")
        all(t -> (x = lf.ex[t]; lf.streams[x[1]].Y[x[2]+1] == saved[j].Y[t]), 1:lf.N) || error("Y mismatch $j")
    end
    println(io, "gate: rebuilt lives (make_life2) have the saved N and Y (8 lives)")
    mk(j, h) = firemask("C4", (delta = 0.01,), h, D[j])
    cs = Dict(h => counts(j -> mk(j, h), lives, Ns, S, L80) for h in HSCAN)
    ok = [h for h in HSCAN if cs[h].X >= 0.9 * cs[h].K]
    if isempty(ok); println(io, "no h* (no h with X/K >= 0.9); K1-K3 not computable"); s = String(take!(io)); print(s); write(joinpath(OUT80D, "diag.out"), s); return; end
    hs = maximum(ok); c = cs[hs]
    println(io, "h* = $hs: X/K = $(c.X)/$(c.K), Z/W = $(c.Z)/$(c.W)")
    for h in (1.0, 2.0, 3.0, 5.0, 10.0, 19.0); println(io, "  [curve] h=$h X/K=$(cs[h].X)/$(cs[h].K) Z/W=$(cs[h].Z)/$(cs[h].W)"); end
    ff = Tuple{Int,Int,Int}[]; base = Tuple{Int,Int}[]   # (dist, y0, life#) / (dist, y0)
    for (q, j) in enumerate(lives)
        f = mk(j, hs); bs = B[j][2]; Y = saved[j].Y
        for w in routinewins(Ns[j], L80)
            for t in w; t % PSTEP == 0 && push!(base, (dist(t, bs), y0before(Y, t))); end
            k = findfirst(view(f, w)); k === nothing && continue
            t = first(w) + k - 1; push!(ff, (dist(t, bs), y0before(Y, t), q))
        end
    end
    length(ff) == c.Z && c.W == 120 && all(x -> x[1] >= 0, ff) || error("false-fire gate: $(length(ff)) vs Z=$(c.Z), W=$(c.W)")
    println(io, "gate: false fires == Z at h*, W == 120")
    if isempty(ff); println(io, "no false fires at h*; K1, K2 not computable; S80-K3: miss (Z/W = 0)"); s = String(take!(io)); print(s); write(joinpath(OUT80D, "diag.out"), s); return; end
    near(v) = count(x -> x[1] <= NEAR, v) / length(v)
    bmed = median([x[2] for x in base])
    pn, bn = near(ff), near(base); py = count(x -> x[2] > bmed, ff) / length(ff)
    println(io, "false fires $(length(ff)) | base decision points $(length(base))")
    println(io, "  near boundary (<= $NEAR): false $(f4(pn)) vs base $(f4(bn)) (ratio $(f4(pn / bn)))")
    println(io, "  Y=0 in previous $Y0WIN: base median $bmed; false fires above it $(f4(py)); false-fire Y0 counts $(sort([x[2] for x in ff]))")
    println(io, "  base Y0 quantiles 0.5/0.75/0.9/0.99: $(join([quantile([x[2] for x in base], p) for p in (0.5, 0.75, 0.9, 0.99)], "/"))")
    println(io, "  false-fire distances: $(sort([x[1] for x in ff]))")
    println(io, "  false fires per life: $(join([count(x -> x[3] == q, ff) for q in 1:length(lives)], " "))")
    # descriptive: missed switches at h* and at the crit2 h=19 (S79b), Y0 after the switch
    for h in (hs, 19.0), j in lives
        f = mk(j, h)
        for i in S[j]
            any(view(f, formwin(i, L80))) && continue
            println(io, "  [missed h=$h] st$(j[1]) life $(j[2]) i=$i Y0 in [T+1,T+$L80] = $(count(!, view(saved[j].Y, formwin(i, L80)))) dist(T)=$(dist(TS[i], B[j][2]))")
        end
    end
    println(io, "  [formation] Y0 in [T+1,T+$L80] over selected: $(sort([count(!, view(saved[j].Y, formwin(i, L80))) for j in lives for i in S[j]]))")
    println(io, "S80-K1 (near-boundary share >= 2x base): $(pn >= 2bn ? "holds" : "miss")")
    println(io, "S80-K2 (>= 75% of false fires above base Y0 median): $(py >= 0.75 ? "holds" : "miss")")
    println(io, "S80-K3 (Z/W at h* > 0.10): $(c.Z / c.W > 0.10 ? "holds" : "miss")")
    s = String(take!(io)); print(s); write(joinpath(OUT80D, "diag.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    run80d()
end
