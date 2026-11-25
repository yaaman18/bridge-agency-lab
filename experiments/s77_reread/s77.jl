# S77 (discussion/specs/S77-draft-trace1-reread.md). Part 1: missed-switch description and threshold-free separability (S72 stage-1, L-FGT).
# Includes s76.jl (and through it s75.jl) unchanged.
# usage: julia --project=. -t 4 experiments/s77_reread/s77.jl part1
include(joinpath(@__DIR__, "..", "s76_strat", "s76.jl"))

const OUT77 = joinpath(@__DIR__, "out"); mkpath(OUT77)
const LS = [500, 1000, 1500]; const HSCAN = collect(1.0:0.25:60.0)

# routine windows and formation windows for interval length L (spec §1)
function routinewins(N, L)
    ws = UnitRange{Int}[]
    for i in 0:4
        r = rint(N, i)
        span = L == 500 ? ((last(r) - RTAIL + 1):last(r)) : r     # L=500: the S72 tail (3 x 500); else R_i (3000)
        n = length(span) ÷ L
        for k in 0:n-1; a = first(span) + k * L; push!(ws, a:a+L-1); end
    end
    return ws
end
formwin(i, L) = (TS[i] + 1):(TS[i] + L)
function judgeL(f, N, S, L)
    ws = routinewins(N, L); nf = count(w -> any(view(f, w)), ws)
    det = Dict(i => any(view(f, formwin(i, L))) for i in 1:4)
    fr = nf / length(ws); dsel = isempty(S) ? nothing : count(i -> det[i], S) / length(S)
    return (false_rate = fr, nwin = length(ws), nfalse = nf, det_sel = dsel, ok = dsel !== nothing && fr <= FSTAR && dsel >= DSTAR)
end

# score at decision points (NaN where not computable)
function c0scores(d, w)
    s = fill(NaN, d.N)
    for t in PSTEP:PSTEP:d.N; t >= w + BASE75 && (s[t] = c0val(d.ℓ, t, w)); end
    return s
end
function c6scores(d, Y, w)
    s = fill(NaN, d.N)
    for t in PSTEP:PSTEP:d.N
        t >= w + BASE75 || continue
        c = c6(d.ℓ, Y, t, w); c.s === nothing || (s[t] = c.s)
    end
    return s
end
# C6 terms at t: (1-q)Δ1, Δ1, 1-q, qΔ0
function c6terms(ℓ, Y, t, w)
    wi = t-w+1:t; bi = t-w-BASE75+1:t-w
    b0 = [ℓ[k] for k in bi if !Y[k]]; b1 = [ℓ[k] for k in bi if Y[k]]; x0 = [ℓ[k] for k in wi if !Y[k]]; x1 = [ℓ[k] for k in wi if Y[k]]
    q = length(b0) / length(bi); d0 = isempty(x0) ? 0.0 : mean(x0) - mean(b0); d1 = isempty(x1) ? 0.0 : mean(x1) - mean(b1)
    return (w1 = (1 - q) * d1, d1 = d1, omq = 1 - q, w0 = q * d0)
end
smax(s, r) = (v = filter(!isnan, [s[t] for t in r if t % PSTEP == 0]); isempty(v) ? -Inf : maximum(v))

# exact common-threshold check for a windowed score (fire is s > θ)
function sepcheck(scs, Ns, Ss, L)
    Rl = Float64[]; Fl = Float64[]
    for l in eachindex(scs)
        rm = sort([smax(scs[l], w) for w in routinewins(Ns[l], L)], rev = true)
        k = floor(Int, FSTAR * length(rm) + 1e-9)
        push!(Rl, rm[k+1]); push!(Fl, minimum(smax(scs[l], formwin(i, L)) for i in Ss[l]))
    end
    return (R = Rl, F = Fl, ok = maximum(Rl) < minimum(Fl), lo = maximum(Rl), hi = minimum(Fl))
end

function part1()
    w0 = TOML.parsefile(W0_R3)["w0"]; io = IOBuffer()
    R = [loadlife4(1, "FGT", l) for l in 1:NLIFE]; D = [ownq(r.P, r.Y, nothing) for r in R]
    S = [selset(r, EPS75, w0) for r in R]; Ns = [d.N for d in D]
    # gate: judgeL at L=500 equals S75 judgeclock (false rate and selected detection) on a few masks
    for l in 1:NLIFE, th in (0.01, 0.02)
        f = firemask("C0", (w = 500,), th, D[l]); a = judgeL(f, D[l].N, S[l], 500); b = judgeclock(f, D[l].N, S[l])
        a.false_rate == b.false_rate && a.det_sel == b.det_sel || error("judgeL != judgeclock life $l")
    end
    println(io, "gate: judgeL(L=500) == S75 judgeclock (8 masks)")
    # ---- B1: C6 w=500 theta=0.02, terms in the formation window (L=500)
    println(io, "== B1: C6 w=500 theta=0.02 (L=500), per selected switch")
    det = Float64[]; mis = Float64[]
    for l in 1:NLIFE
        f = firemask6(D[l], R[l].Y, 500, 0.02); ℓ = D[l].ℓ; e = ℓ .- R[l].lref
        for i in S[l]
            T = TS[i]; pts0 = [t for t in formwin(i, 500) if t % PSTEP == 0]
            pts = [t for t in pts0 if (c = c6(ℓ, R[l].Y, t, 500); c.s !== nothing && isfinite(c.s) && all(isfinite, values(c6terms(ℓ, R[l].Y, t, 500))))]   # codex I-R P2
            length(pts) == length(pts0) || println(io, "  note life $l i=$i: $(length(pts0) - length(pts)) of $(length(pts0)) points dropped (base stratum empty or non-finite)")
            tm = pts[argmax([c6terms(ℓ, R[l].Y, t, 500).w1 for t in pts])]; c = c6terms(ℓ, R[l].Y, tm, 500)
            hit = any(view(f, formwin(i, 500))); push!(hit ? det : mis, c.w1)
            println(io, "  life $l i=$i detected=$hit max(1-q)Δ1=$(f4(c.w1)) at t=T+$(tm - T): Δ1=$(f4(c.d1)) 1-q=$(f4(c.omq)) qΔ0=$(f4(c.w0))  e_i=$(f4(mean(e[T+1:T+500]))) Y0=$(count(!, R[l].Y[T+1:T+500]))")
        end
    end
    md = median(det)
    b1 = length(mis) == 3 && all(x -> x < md, mis) ? "holds" : "miss"
    println(io, "B1: missed n=$(length(mis)) values $(join(f4.(mis), ", ")); detected n=$(length(det)) median $(f4(md)) -> $b1")
    # ---- separability per L
    sep = Dict{Tuple{String,Int},Bool}()
    for L in LS
        println(io, "== L=$L (routine windows per life $(length(routinewins(Ns[1], L))))")
        for (nm, scs, mk) in (("C0 w=500", [c0scores(D[l], 500) for l in 1:NLIFE], (l, th) -> firemask("C0", (w = 500,), th, D[l])),
                                ("C6 w=500", [c6scores(D[l], R[l].Y, 500) for l in 1:NLIFE], (l, th) -> firemask6(D[l], R[l].Y, 500, th)))
            r = sepcheck(scs, Ns, S, L); sep[(nm, L)] = r.ok
            println(io, "  $nm: R_l (allowed-false+1 th routine max) $(join(f4.(r.R), " ")) | F_l (min selected formation max) $(join(f4.(r.F), " ")) | common theta exists: $(r.ok)$(r.ok ? " range [$(f4(r.lo)), $(f4(r.hi)))" : "")")
            for l in 1:NLIFE; println(io, "    life $l separable alone: $(r.R[l] < r.F[l])"); end
            if r.ok   # gate: a theta inside the range passes all 4 lives with the fire rule
                th = (r.lo + r.hi) / 2
                ok = all(l -> judgeL(mk(l, th), Ns[l], S[l], L).ok, 1:NLIFE)      # the real fire functions (codex I-R P3)
                ok || error("separability gate failed $nm L=$L")
            end
        end
        for δ in (0.005, 0.01)
            hs = [h for h in HSCAN if all(l -> judgeL(firemask("C4", (delta = δ,), h, D[l]), Ns[l], S[l], L).ok, 1:NLIFE)]
            per = [count(h -> judgeL(firemask("C4", (delta = δ,), h, D[l]), Ns[l], S[l], L).ok, HSCAN) for l in 1:NLIFE]
            sep[("C4 delta=$δ", L)] = !isempty(hs)
            println(io, "  C4 delta=$δ: h passing all 4 lives: $(isempty(hs) ? "none" : join(hs, ","))  | per-life count of passing h (of $(length(HSCAN))): $(join(per, " "))")
        end
    end
    b2 = !any(v for ((k, L), v) in sep if L == 500)
    b3 = any(v for ((k, L), v) in sep if L != 500)
    println(io, "B2 (L=500: no candidate has a common value): $(b2 ? "holds" : "miss")")
    println(io, "B3 (L=1000 or 1500: some candidate has a common value): $(b3 ? "holds" : "miss")")
    s = String(take!(io)); print(s); write(joinpath(OUT77, "part1.out"), s)
end

# ---- part 3 (spec §3): sub-criterion on switches where the stream showed L-REF evidence e_i > e*, e* fixed on dev routine windows
const CONF77 = [("C0", "w=500", (l, th, d, Y) -> firemask("C0", (w = 500,), th, d), [0.005, 0.01, 0.02, 0.04]),
                ("C4", "delta=0.005", (l, th, d, Y) -> firemask("C4", (delta = 0.005,), th, d), [5.0, 10.0, 20.0, 40.0]),
                ("C4", "delta=0.01", (l, th, d, Y) -> firemask("C4", (delta = 0.01,), th, d), [5.0, 10.0, 20.0, 40.0]),
                ("C6", "w=500", (l, th, d, Y) -> firemask6(d, Y, 500, th), [0.005, 0.01, 0.02, 0.04])]
emean(r, a) = mean(view(r, a))
function targets(x, Ssel, estar)
    e = losses(x.P, x.Y) .- x.lref
    ev = Dict(i => emean(e, TS[i]+1:TS[i]+500) for i in 1:4)
    return [i for i in Ssel if ev[i] > estar], ev
end
function part3()
    isfile(joinpath(@__DIR__, "predictions-part3.toml")) || error("part-3 predictions not frozen")
    w0 = TOML.parsefile(W0_R3)["w0"]; io = IOBuffer()
    R = [loadlife4(1, "FGT", l) for l in 1:NLIFE]; D = [ownq(r.P, r.Y, nothing) for r in R]
    Ssel = [selset(r, EPS75, w0) for r in R]
    estar = maximum(emean(losses(R[l].P, R[l].Y) .- R[l].lref, w) for l in 1:NLIFE for w in routinewins(R[l].N, 500))
    println(io, "e* (max over 4 dev lives x 15 routine windows of the mean L-REF excess) = $(estar)")
    Tg = []
    for l in 1:NLIFE
        tg, ev = targets(R[l], Ssel[l], estar); push!(Tg, tg)
        println(io, "  dev life $l selected=$(Ssel[l]) targets=$tg  e_i=$(join(["$i:$(f4(ev[i]))" for i in 1:4], " "))")
    end
    rows = []
    for (ci, (cand, lab, mk, grid)) in enumerate(CONF77)
        sel = nothing
        for (gi, th) in enumerate(grid)
            js = [judgeclock(mk(l, th, D[l], R[l].Y), D[l].N, Tg[l]) for l in 1:NLIFE]
            jm = [judgeclock(mk(l, th, D[l], R[l].Y), D[l].N, Ssel[l]) for l in 1:NLIFE]
            for l in 1:NLIFE; println(io, "  $cand $lab th=$th life $l SUB $(jline(js[l]))  | MAIN det_sel=$(jm[l].ndet_sel)/$(jm[l].nsel) ok=$(jm[l].ok)"); end
            println(io, "  grid $cand $lab th=$th: sub lives ok $(count(j -> j.ok, js))/4, main lives ok $(count(j -> j.ok, jm))/4")
            if all(j -> j.ok, js) && sel === nothing
                sel = (cand = cand, lab = lab, th = th, ci = ci, gi = gi, maxf = maximum(j.false_rate for j in js), dl = mean(j.delay for j in js))
            end
        end
        println(io, "  SELECTED $cand $lab: $(sel === nothing ? "none" : "th=$(sel.th) maxfalse=$(f4(sel.maxf)) delay=$(f4(sel.dl))")")
        sel === nothing || push!(rows, sel)
    end
    sort!(rows, by = r -> (r.maxf, r.dl, parse(Int, r.cand[2:end]), r.ci, r.gi))
    if isempty(rows)
        println(io, "WINNER: none"); println(io, "S77-D1: miss$(any(isempty, Tg) ? " (a dev life has 0 targets)" : "")"); println(io, "S77-D2: not evaluated"); println(io, "S77-D3: not evaluated")
    else
        wv = rows[1]; _, _, mk, _ = CONF77[wv.ci]
        println(io, "WINNER: $(wv.cand) $(wv.lab) th=$(wv.th)"); println(io, "S77-D1: holds")
        foreach(pstream, PROBE_SEEDS); foreach(stream75, SEEDS_CF)
        M = tmapv(l -> (x = mainrun(l, SEEDS_CF); serialize(joinpath(OUT77, "confirm_FGT_$l.jls"), x); x), collect(1:NLIFE))
        for l in 1:NLIFE; all(s -> s in SEEDS_CF, M[l].seeds) || error("confirmation life $l used a seed outside 1600-1617"); end
        println(io, "== confirmation (seeds 1600-1617, L-FGT, winner only, e* from dev = $estar)")
        js = []; jm = []
        for l in 1:NLIFE
            x = M[l]; Sx = selset(x, EPS75, w0); tg, ev = targets(x, Sx, estar); d = ownq(x.P, x.Y, nothing); f = mk(l, wv.th, d, x.Y)
            a = judgeclock(f, d.N, tg); b = judgeclock(f, d.N, Sx); push!(js, a); push!(jm, b)
            r = trace1_3(x, 0.04, Sx)
            println(io, "  life $l N=$(x.N) selected=$Sx targets=$tg e_i=$(join(["$i:$(f4(ev[i]))" for i in 1:4], " "))")
            println(io, "    SUB $(jline(a))"); println(io, "    MAIN $(jline(b))")
            println(io, "    [desc: L-REF clock theta=0.04] false=$(f4(r.false_rate)) det_sel=$(r.ndet_sel)/$(r.nsel)")
        end
        d2 = any(j -> j.nsel > 0 && !j.ok, js) ? "miss" : any(j -> j.nsel == 0, js) ? "undecided (a life with 0 targets)" : "holds"
        mainpass = all(j -> j.ok, jm)
        println(io, "S77-D2 (sub-criterion 4/4): $d2 ($(count(j -> j.nsel > 0 && j.ok, js))/4 pass)")
        println(io, "S77-D3 (main criterion NOT 4/4): $(mainpass ? "miss (main passes 4/4)" : "holds") ($(count(j -> j.ok, jm))/4 pass main)")
    end
    s = String(take!(io)); print(s); write(joinpath(OUT77, "part3.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    ARGS[1] == "part1" && part1()
    ARGS[1] == "part3" && part3()
end
