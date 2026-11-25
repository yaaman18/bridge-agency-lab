# S75 (discussion/specs/S75-draft-clock-candidates-dev.md): clock candidates C0-C5 built from the individual's own quantities only,
# one winner selected on the S72 stage-1 lives (dev), then confirmed on new seeds 1600-1617 (winner only, no fall-back).
# Includes the S72 r4 code unchanged (its main block does not run when included).
# usage: julia --project=. -t 4 experiments/s75_clock/s75.jl dev | confirm
include(joinpath(@__DIR__, "..", "s72_open", "s72r4.jl"))

const OUT75 = joinpath(@__DIR__, "out"); mkpath(OUT75)
const PRED75 = joinpath(@__DIR__, "predictions.toml"); const WIN75 = joinpath(OUT75, "dev_winner.toml")
const SEEDS_CF = collect(1600:1617)
const BASE75 = 3000; const DEADLINE = 500; const PSTEP = 50; const EPS75 = 0.0025
const LAM_SLOW = 1 - 1 / 20000; const MU_K = 1 / 3000
# (candidate, config label, config, threshold grid). Rank keys 3-4 (spec §5): candidate number C0..C5, then the position in that
# candidate's grid read lexicographically with the non-threshold config outer (C1: w=1000 before w=2000) and the threshold inner (codex I-R P4)
const CANDS = [
    ("C0", "w=500", (w = 500,), [0.005, 0.01, 0.02, 0.04]),
    ("C1", "w=1000", (w = 1000,), [0.005, 0.01, 0.02, 0.04]),
    ("C1", "w=2000", (w = 2000,), [0.005, 0.01, 0.02, 0.04]),
    ("C2", "w=500", (w = 500,), [2.0, 3.0, 4.0, 6.0]),
    ("C3", "w=500", (w = 500,), [0.005, 0.01, 0.02, 0.04]),
    ("C4", "delta=0.005", (delta = 0.005,), [5.0, 10.0, 20.0, 40.0]),
    ("C4", "delta=0.01", (delta = 0.01,), [5.0, 10.0, 20.0, 40.0]),
    ("C5", "w=500", (w = 500,), [0.05, 0.1, 0.2, 0.4]),
]

# ---- per-example own quantities
bent(p) = -(p * log(p) + (1 - p) * log(1 - p))          # expected own loss under own prediction (nats)
wmean(x, t, w) = mean(view(x, t-w+1:t))                  # window: the w examples ending at t
bmean(x, t, w) = mean(view(x, t-w-BASE75+1:t-w))         # base: the BASE75 examples right before the window
bsd(x, t, w) = std(view(x, t-w-BASE75+1:t-w))            # sample sd (n - 1)

# fire points (global example index, multiples of PSTEP) for one candidate config and threshold
function firemask(cand, cfg, th, d)
    N = d.N; f = falses(N)
    if cand == "C4"
        μ = 0.0; m = 0.0; M = 0.0
        for t in 1:N
            m += d.ℓ[t] - μ - cfg.delta; M = min(M, m); μ += (d.ℓ[t] - μ) * MU_K    # μ_t is the value before ℓ_t
            if t % PSTEP == 0 && m - M > th; f[t] = true; m = 0.0; M = 0.0; end
        end
        return f
    end
    w = cfg.w
    for t in PSTEP:PSTEP:N
        if cand == "C3"
            t >= w || continue
            f[t] = wmean(d.r, t, w) > th
        else
            t >= w + BASE75 || continue
            x = cand == "C5" ? d.g : d.ℓ
            if cand == "C2"
                sd = bsd(x, t, w); sd > 0 || continue
                f[t] = (wmean(x, t, w) - bmean(x, t, w)) / (sd / sqrt(w)) > th
            else
                f[t] = wmean(x, t, w) - bmean(x, t, w) > th
            end
        end
    end
    return f
end

function judgeclock(f, N, S)
    nf = 0
    for i in 0:4
        r = rint(N, i); tail = (last(r) - RTAIL + 1):last(r)
        for k in 0:2; a = first(tail) + k * 500; nf += any(view(f, a:a+499)); end
    end
    delay = Dict{Int,Union{Int,Nothing}}()
    for i in 1:4
        T = TS[i]; j = findfirst(view(f, T+1:T+DEADLINE)); delay[i] = j === nothing ? nothing : j
    end
    fr = nf / 15; dall = count(i -> delay[i] !== nothing, 1:4) / 4
    nds = count(i -> delay[i] !== nothing, S); dsel = isempty(S) ? nothing : nds / length(S)
    dl = isempty(S) ? nothing : mean(delay[i] === nothing ? DEADLINE : delay[i] for i in S)
    return (false_rate = fr, det_all = dall, nsel = length(S), ndet_sel = nds, det_sel = dsel, delay = dl,
            undet = count(i -> delay[i] === nothing, S), ok = dsel !== nothing && fr <= FSTAR && dsel >= DSTAR)
end

# ---- the main stream re-run (run_life4's main loop without branches): L-FGT, the slow twin, and L-REF, with the probes TRACE-1 needs
function stream75(u)
    u in SEEDS_ST1 && return stream2(u)
    f = joinpath(OUT75, "stream_$u.jls"); isfile(f) && return deserialize(f)
    st = obs_stream(u, "stat"); serialize(f, st); return st
end
function mainrun(life, seeds)
    streams = Dict(u => stream75(u) for u in seeds)
    lf = make_life2(life, seeds, streams); maps, _ = life_maps(life); plf = probe_life(life)
    N = lf.N; N >= TS[end] + BDD_OFF + LB && N >= TS[end] + CAP || error("life too short: $N")
    pts = main_points(N); bounds = vcat(0, TS, N)
    L = new_learner("FGT", life); Ls = TabL(zeros(2), zeros(2), zeros(130), zeros(130), LAM_SLOW); REF = new_learner("CUM", life)
    P = Float64[]; Y = Bool[]; Ps = Float64[]; ℓref = Float64[]
    pL = Dict{Int,Vector{Float64}}(); pR = Dict{Int,Vector{Float64}}(); pNew = Dict{Int,Vector{Float64}}()
    for seg in 1:5
        a, b = bounds[seg], bounds[seg+1]; m = maps[seg]
        seg >= 2 && (pNew[seg-1] = probe(L, plf, m))
        cur = a
        for c in vcat([t for t in pts if a < t < b], b)
            ps, ys = span!(L, lf, cur + 1, c + 1, m); append!(P, ps); append!(Y, ys)
            qs, zs = span!(Ls, lf, cur + 1, c + 1, m); append!(Ps, qs); zs == ys || error("slow twin saw different outcomes")
            rp, ry = span!(REF, lf, cur + 1, c + 1, ID); append!(ℓref, losses(rp, ry))
            if c in TS; pL[c] = probe(L, plf, m); pR[c] = probe(REF, plf, ID); end
            cur = c
        end
    end
    return (kind = "FGT", life = life, N = N, P = P, Y = Y, Pslow = Ps, lref = ℓref, pL = pL, pR = pR, pNew = pNew,
            seeds = [s.seed for s in lf.streams])
end
ownq(P, Y, Ps) = (ℓ = losses(P, Y); (N = length(P), ℓ = ℓ, r = ℓ .- bent.(P), g = Ps === nothing ? nothing : abs.(logit.(P) .- logit.(Ps))))

f4(x) = x === nothing ? "none" : @sprintf("%.4f", x)
jline(j) = "false=$(f4(j.false_rate)) det_all=$(f4(j.det_all)) det_sel=$(j.nsel == 0 ? "not computable" : "$(j.ndet_sel)/$(j.nsel)") delay=$(f4(j.delay)) undet=$(j.undet) ok=$(j.nsel == 0 ? "not computable" : j.ok)"

function dev75()
    isfile(PRED75) || error("predictions not frozen: $PRED75")
    w0 = TOML.parsefile(W0_R3)["w0"]; io = IOBuffer()
    R = Dict((k, l) => loadlife4(1, k, l) for k in ("FGT", "CUM", "WIN") for l in 1:NLIFE)
    M = tmapv(l -> mainrun(l, SEEDS_ST1), collect(1:NLIFE))
    for l in 1:NLIFE   # gate: the slim main run reproduces the saved run_life4 main stream and the probes used for the selected set
        s = R[("FGT", l)]; x = M[l]
        reinterpret(UInt64, x.P) == reinterpret(UInt64, s.P) && x.Y == s.Y && reinterpret(UInt64, x.lref) == reinterpret(UInt64, s.lref) &&
            all(i -> (bw(u, v) = reinterpret(UInt64, u) == reinterpret(UInt64, v); bw(x.pNew[i], s.pNew[i]) && bw(x.pL[TS[i]], s.pL[TS[i]]) && bw(x.pR[TS[i]], s.pR[TS[i]])), 1:4) ||
            error("slim main run differs from S72 r4 saved FGT life $l")
        selset(x, EPS75, w0) == selset(s, EPS75, w0) || error("selected set differs: life $l")
    end
    D = Dict((k, l) => (k == "FGT" ? ownq(M[l].P, M[l].Y, M[l].Pslow) : ownq(R[(k, l)].P, R[(k, l)].Y, nothing)) for k in ("FGT", "CUM", "WIN") for l in 1:NLIFE)
    S = Dict((k, l) => selset(R[(k, l)], EPS75, w0) for k in ("FGT", "CUM", "WIN") for l in 1:NLIFE)
    for l in 1:NLIFE, i in 1:4   # gate: C0 at T_i + 500 equals the S73 self-baseline quantity
        ℓ = D[("FGT", l)].ℓ; T = TS[i]
        wmean(ℓ, T + 500, 500) - bmean(ℓ, T + 500, 500) == mean(ℓ[T+1:T+500]) - mean(ℓ[T+1-3000:T]) || error("C0/S73 mismatch life $l i $i")
    end
    println(io, "gates: slim main run == S72 r4 saved FGT (P, Y, lref, probes at T_i, selected sets; 4 lives, bitwise); C0 at T_i+500 == S73 quantity (16)")
    println(io, "selected switches (eps=$EPS75): " * join(["FGT life $l $(S[("FGT", l)])" for l in 1:NLIFE], "; "))
    rows = []
    for (ci, (cand, lab, cfg, grid)) in enumerate(CANDS)
        println(io, "== $cand $lab")
        sel = nothing
        for (gi, th) in enumerate(grid)
            js = [judgeclock(firemask(cand, cfg, th, D[("FGT", l)]), D[("FGT", l)].N, S[("FGT", l)]) for l in 1:NLIFE]
            for l in 1:NLIFE; println(io, "  FGT th=$th life $l $(jline(js[l]))"); end
            for k in ("CUM", "WIN"), l in 1:NLIFE
                cand == "C5" && continue
                println(io, "  [desc] $k th=$th life $l $(jline(judgeclock(firemask(cand, cfg, th, D[(k, l)]), D[(k, l)].N, S[(k, l)])))")
            end
            pass = all(j -> j.ok, js)
            println(io, "  grid $cand $lab th=$th: FGT lives ok $(count(j -> j.ok, js))/4")
            if pass && sel === nothing
                sel = (cand = cand, lab = lab, th = th, ci = ci, gi = gi, maxf = maximum(j.false_rate for j in js), dl = mean(j.delay for j in js))
            end
        end
        println(io, "  SELECTED $cand $lab: $(sel === nothing ? "none (no threshold passes all 4 lives)" : "th=$(sel.th) maxfalse=$(f4(sel.maxf)) delay=$(f4(sel.dl))")")
        sel === nothing || push!(rows, sel)
    end
    sort!(rows, by = r -> (r.maxf, r.dl, parse(Int, r.cand[2:end]), r.ci, r.gi))
    println(io, "RANKING: " * (isempty(rows) ? "none" : join(["$(r.cand) $(r.lab) th=$(r.th) (maxfalse $(f4(r.maxf)), delay $(f4(r.dl)))" for r in rows], " > ")))
    if isempty(rows)
        println(io, "WINNER: none"); println(io, "S75-Q1: miss"); println(io, "S75-Q2: miss"); println(io, "S75-Q3: undecided (confirmation not run)")
        write(WIN75, "winner = \"none\"\n")
    else
        wv = rows[1]
        println(io, "WINNER: $(wv.cand) $(wv.lab) th=$(wv.th)"); println(io, "S75-Q1: holds"); println(io, "S75-Q2: $(wv.cand in ("C4", "C5") ? "holds" : "miss")")
        write(WIN75, "winner = \"$(wv.cand)\"\nconfig = \"$(wv.lab)\"\nci = $(wv.ci)\nthreshold = $(wv.th)\n")
    end
    s = String(take!(io)); print(s); write(joinpath(OUT75, "dev.out"), s)
end

function confirm75()
    isfile(PRED75) || error("predictions not frozen: $PRED75")
    W = TOML.parsefile(WIN75)
    W["winner"] == "none" && (println("S75-Q3: undecided (no winner, confirmation not run)"); return)
    cand, lab, cfg, _ = CANDS[W["ci"]]; th = Float64(W["threshold"]); (cand == W["winner"] && lab == W["config"]) || error("winner file mismatch")
    w0 = TOML.parsefile(W0_R3)["w0"]; io = IOBuffer()
    foreach(pstream, PROBE_SEEDS); foreach(stream75, SEEDS_CF)
    M = tmapv(l -> (x = mainrun(l, SEEDS_CF); serialize(joinpath(OUT75, "confirm_FGT_$l.jls"), x); x), collect(1:NLIFE))
    for l in 1:NLIFE; all(s -> s in SEEDS_CF, M[l].seeds) || error("confirmation life $l used a seed outside 1600-1617"); end
    println(io, "confirmation: winner $cand $lab th=$th, seeds 1600-1617, L-FGT")
    js = []
    for l in 1:NLIFE
        x = M[l]; S = selset(x, EPS75, w0); d = ownq(x.P, x.Y, x.Pslow)
        j = judgeclock(firemask(cand, cfg, th, d), d.N, S); push!(js, j)
        r = trace1_3(x, 0.04, S)
        println(io, "  life $l N=$(x.N) selected=$S  $(jline(j))")
        println(io, "  life $l [desc: S72 r4 L-REF clock theta=0.04] false=$(f4(r.false_rate)) det_all=$(f4(r.det_all)) det_sel=$(r.ndet_sel)/$(r.nsel)")
    end
    q3 = any(j -> j.nsel > 0 && !j.ok, js) ? "miss" : any(j -> j.nsel == 0, js) ? "undecided (a life with 0 selected switches)" : "holds"
    println(io, "S75-Q3 (winner passes all 4 confirmation lives): $q3 ($(count(j -> j.nsel > 0 && j.ok, js))/4 pass)")
    s = String(take!(io)); print(s); write(joinpath(OUT75, "confirm.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    ARGS[1] == "dev" && dev75()
    ARGS[1] == "confirm" && confirm75()
end
