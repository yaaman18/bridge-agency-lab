# S76 (discussion/specs/S76-draft-stratified-selfclock-dev.md): self-baseline clock with the window's Y=0 frequency equalized to the base (C6).
# Part 1: direct check of H-S75a at life 1, i = 4 (seen S72 stage-1 lives). Part 2: dev selection on stage-1, confirmation on seeds 1600-1617.
# Includes s75.jl unchanged (its main block does not run when included).
# usage: julia --project=. -t 4 experiments/s76_strat/s76.jl run
include(joinpath(@__DIR__, "..", "s75_clock", "s75.jl"))

const OUT76 = joinpath(@__DIR__, "out"); mkpath(OUT76)
const PRED76 = joinpath(@__DIR__, "predictions.toml")
const W76 = [500, 1000]; const TH76 = [0.005, 0.01, 0.02, 0.04]

# C6 at point t with window w: nothing when a base stratum is empty (no fire there)
function c6(ℓ, Y, t, w)
    wi = t-w+1:t; bi = t-w-BASE75+1:t-w
    b0 = [ℓ[k] for k in bi if !Y[k]]; b1 = [ℓ[k] for k in bi if Y[k]]
    x0 = [ℓ[k] for k in wi if !Y[k]]; x1 = [ℓ[k] for k in wi if Y[k]]
    (isempty(b0) || isempty(b1)) && return (s = nothing, n0b = length(b0), n1b = length(b1), n0w = length(x0), n1w = length(x1), imp = false)
    q = length(b0) / length(bi)
    d0 = isempty(x0) ? 0.0 : mean(x0) - mean(b0); d1 = isempty(x1) ? 0.0 : mean(x1) - mean(b1)    # symmetric imputation (codex P2)
    return (s = q * d0 + (1 - q) * d1, q = q, p = length(x0) / w, n0b = length(b0), n1b = length(b1), n0w = length(x0), n1w = length(x1), imp = isempty(x0) || isempty(x1),
            m0 = isempty(x0) ? nothing : mean(x0), m1 = isempty(x1) ? nothing : mean(x1))
end
function firemask6(d, Y, w, th)
    f = falses(d.N)
    for t in PSTEP:PSTEP:d.N
        t >= w + BASE75 || continue
        c = c6(d.ℓ, Y, t, w); c.s === nothing && continue
        f[t] = c.s > th
    end
    return f
end
# per-point strata log (codex I-R P2): window and base counts, window imputation vs base-empty skip; returns (n imputed, n skipped)
function stratalog(tag, d, Y, w)
    nimp = 0; nskip = 0
    open(joinpath(OUT76, "strata_$(tag)_w$w.tsv"), "w") do f
        println(f, "t\tn0_base\tn1_base\tn0_win\tn1_win\twindow_imputed\tbase_empty_skip")
        for t in PSTEP:PSTEP:d.N
            t >= w + BASE75 || continue
            c = c6(d.ℓ, Y, t, w); sk = c.s === nothing; nimp += c.imp; nskip += sk
            println(f, "$t\t$(c.n0b)\t$(c.n1b)\t$(c.n0w)\t$(c.n1w)\t$(c.imp)\t$sk")
        end
    end
    return (nimp, nskip)
end
c0val(ℓ, t, w) = wmean(ℓ, t, w) - bmean(ℓ, t, w)

function run76()
    isfile(PRED76) || error("predictions not frozen: $PRED76")
    w0 = TOML.parsefile(W0_R3)["w0"]; io = IOBuffer()
    R = Dict((k, l) => loadlife4(1, k, l) for k in ("FGT", "CUM", "WIN") for l in 1:NLIFE)
    D = Dict(j => ownq(R[j].P, R[j].Y, nothing) for j in keys(R))
    S = Dict(j => selset(R[j], EPS75, w0) for j in keys(R))
    # gate: with both strata present, C0 - C6 == (p - q)(m0 - m1) up to rounding (codex P4)
    println(io, "== part 1: t = T_i + 500, w = 500, L-FGT (selected = d_i >= 3 eps)")
    for l in 1:NLIFE, i in 1:4
        ℓ = D[("FGT", l)].ℓ; Y = R[("FGT", l)].Y; t = TS[i] + 500
        c = c6(ℓ, Y, t, 500); a = c0val(ℓ, t, 500)
        if c.s === nothing
            println(io, "  life $l i=$i sel=$(i in S[("FGT", l)]) C0=$(f4(a)) C6=not computable (base stratum empty: n0b=$(c.n0b) n1b=$(c.n1b))"); continue
        end
        dec = c.imp ? "imputed" : f4((c.p - c.q) * (c.m0 - c.m1))
        c.imp || abs((a - c.s) - (c.p - c.q) * (c.m0 - c.m1)) < 1e-9 || error("decomposition gate failed life $l i $i")
        println(io, "  life $l i=$i sel=$(i in S[("FGT", l)]) C0=$(f4(a)) C6=$(f4(c.s)) C0-C6=$(f4(a - c.s)) (p-q)(m0-m1)=$dec p=$(f4(c.p)) q=$(f4(c.q)) n0w=$(c.n0w) n1w=$(c.n1w) imputed=$(c.imp)")
    end
    c = c6(D[("FGT", 1)].ℓ, R[("FGT", 1)].Y, TS[4] + 500, 500); a = c0val(D[("FGT", 1)].ℓ, TS[4] + 500, 500)
    a1 = c.s === nothing ? "not computable (base stratum empty)" : a <= 0 < c.s ? "holds" : (c.s <= 0 ? "miss" : "miss (C0 > 0)")
    println(io, "S76-A1 (life 1 i=4: C0 <= 0 < C6): $a1  C0=$(f4(a)) C6=$(f4(c.s)) imputed=$(c.imp)$(c.imp ? " (reading suspended)" : "")")
    println(io, "== part 2: dev (S72 stage-1 lives)")
    for k in ("FGT", "CUM", "WIN"), l in 1:NLIFE, w in W76
        ni, ns = stratalog("dev_$(k)_$l", D[(k, l)], R[(k, l)].Y, w)
        println(io, "  strata $k life $l w=$w: points with window imputation $ni, base-empty skips $ns")
    end
    rows = []
    for (ci, w) in enumerate(W76)
        sel = nothing
        for (gi, th) in enumerate(TH76)
            js = [judgeclock(firemask6(D[("FGT", l)], R[("FGT", l)].Y, w, th), D[("FGT", l)].N, S[("FGT", l)]) for l in 1:NLIFE]
            for l in 1:NLIFE; println(io, "  FGT w=$w th=$th life $l $(jline(js[l]))"); end
            for k in ("CUM", "WIN"), l in 1:NLIFE
                println(io, "  [desc] $k w=$w th=$th life $l $(jline(judgeclock(firemask6(D[(k, l)], R[(k, l)].Y, w, th), D[(k, l)].N, S[(k, l)])))")
            end
            println(io, "  grid C6 w=$w th=$th: FGT lives ok $(count(j -> j.ok, js))/4")
            if all(j -> j.ok, js) && sel === nothing
                sel = (w = w, th = th, ci = ci, gi = gi, maxf = maximum(j.false_rate for j in js), dl = mean(j.delay for j in js))
            end
        end
        println(io, "  SELECTED C6 w=$w: $(sel === nothing ? "none" : "th=$(sel.th) maxfalse=$(f4(sel.maxf)) delay=$(f4(sel.dl))")")
        sel === nothing || push!(rows, sel)
    end
    sort!(rows, by = r -> (r.maxf, r.dl, r.ci, r.gi))
    if isempty(rows)
        println(io, "WINNER: none"); println(io, "S76-A2: miss"); println(io, "S76-A3: not evaluated (confirmation not run)")
    else
        wv = rows[1]
        println(io, "WINNER: C6 w=$(wv.w) th=$(wv.th)"); println(io, "S76-A2: holds")
        foreach(pstream, PROBE_SEEDS); foreach(stream75, SEEDS_CF)
        M = tmapv(l -> (x = mainrun(l, SEEDS_CF); serialize(joinpath(OUT76, "confirm_FGT_$l.jls"), x); x), collect(1:NLIFE))
        for l in 1:NLIFE; all(s -> s in SEEDS_CF, M[l].seeds) || error("confirmation life $l used a seed outside 1600-1617"); end
        println(io, "== confirmation (seeds 1600-1617, L-FGT, winner only)")
        js = []
        for l in 1:NLIFE
            x = M[l]; Sx = selset(x, EPS75, w0); d = ownq(x.P, x.Y, nothing)
            ni, ns = stratalog("confirm_FGT_$l", d, x.Y, wv.w)
            println(io, "  strata confirm life $l w=$(wv.w): points with window imputation $ni, base-empty skips $ns")
            j = judgeclock(firemask6(d, x.Y, wv.w, wv.th), d.N, Sx); push!(js, j)
            println(io, "  life $l N=$(x.N) selected=$Sx  $(jline(j))")
            r = trace1_3(x, 0.04, Sx); c0j = judgeclock(firemask("C0", (w = 500,), 0.02, d), d.N, Sx)
            println(io, "  life $l [desc: L-REF clock theta=0.04] false=$(f4(r.false_rate)) det_sel=$(r.ndet_sel)/$(r.nsel)  [desc: C0 w=500 th=0.02] $(jline(c0j))")
        end
        a3 = any(j -> j.nsel > 0 && !j.ok, js) ? "miss" : any(j -> j.nsel == 0, js) ? "undecided (a life with 0 selected switches)" : "holds"
        println(io, "S76-A3 (winner passes all 4 confirmation lives): $a3 ($(count(j -> j.nsel > 0 && j.ok, js))/4 pass)")
    end
    s = String(take!(io)); print(s); write(joinpath(OUT76, "s76.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    ARGS[1] == "run" && run76()
end
