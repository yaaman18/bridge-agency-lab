# S80 Y=0 clock comparison (discussion/specs/S80-draft-trace1-confirm.md §10.3): does a learner-free clock that only counts Y=0
# in the last w examples trace the same detection / false-alarm curve as C4 (delta=0.01)? Seen lives only; no new seeds.
# Includes s80_diag/diag.jl unchanged (its main block does not run when included).
# usage: julia --project=. -t 4 experiments/s80_y0/y0clock.jl
include(joinpath(@__DIR__, "..", "s80_diag", "diag.jl"))
const PRED80Y = joinpath(@__DIR__, "predictions.toml"); const OUT80Y = joinpath(@__DIR__, "out"); mkpath(OUT80Y)
const TH80Y = collect(0:1:200)

# fire at decision points t (multiples of PSTEP, t >= w) when #(Y = 0 in Y[t-w+1:t]) > th
function y0mask(Y, w, th)
    N = length(Y); z = cumsum(.!Y); f = falses(N)
    for t in PSTEP:PSTEP:N
        t >= w || continue
        f[t] = (z[t] - (t > w ? z[t-w] : 0)) > th
    end
    return f
end
fwins(f, N) = BitVector([any(view(f, w)) for w in routinewins(N, L80)])   # which routine windows fire

function run80y()
    isfile(PRED80Y) || error("predictions not frozen: $PRED80Y")
    io = IOBuffer(); w0 = TOML.parsefile(W0_R3)["w0"]
    lives = [(st, l) for st in (1, 2) for l in 1:NLIFE]
    saved = Dict(j => loadlife4(j[1], "FGT", j[2]) for j in lives)
    D = Dict(j => ownq(saved[j].P, saved[j].Y, nothing) for j in lives)
    S = Dict(j => selset(saved[j], EPS75, w0) for j in lives); Ns = Dict(j => D[j].N for j in lives)
    Yv = Dict(j => saved[j].Y for j in lives)
    all(j -> length(Yv[j]) == Ns[j], lives) || error("length gate")
    # gate 1: y0mask agrees with a direct count (y0before-style) on every decision point of one life, w = 500 and 1000
    let j = lives[1], Y = Yv[j]
        for w in (500, 1000), th in (3, 8)
            f = y0mask(Y, w, th)
            all(t -> f[t] == (t % PSTEP == 0 && t >= w && count(!, view(Y, t-w+1:t)) > th), 1:Ns[j]) || error("y0mask gate w=$w th=$th")
        end
    end
    # gate 2: negative control th = -1 fires at every decision point t >= w, so every window ending at >= w fires
    let c = counts(j -> y0mask(Yv[j], 1000, -1), lives, Ns, S, L80)
        nw = sum(count(w -> any(t -> t >= 1000 && t % PSTEP == 0, w), routinewins(Ns[j], L80)) for j in lives)   # codex I-R P2
        c.X == c.K && c.Z == nw || error("negative-control gate: X=$(c.X)/$(c.K) Z=$(c.Z) vs $nw")
    end
    # gate 3: C4 reproduces the s80_diag numbers (h* = 7.5, X/K = 27/30, Z/W = 31/120)
    mk4(j, h) = firemask("C4", (delta = 0.01,), h, D[j])
    c4 = Dict(h => counts(j -> mk4(j, h), lives, Ns, S, L80) for h in HSCAN)
    h4 = maximum([h for h in HSCAN if c4[h].X >= 0.9 * c4[h].K])
    (h4, c4[h4].X, c4[h4].K, c4[h4].Z, c4[h4].W) == (7.5, 27, 30, 31, 120) || error("C4 gate: $h4 $(c4[h4])")
    println(io, "gate: y0mask == direct count; th=-1 fires every window; C4 h*=7.5 X/K=27/30 Z/W=31/120 reproduced")
    res = Dict()
    for w in (1000, 500)
        cy = Dict(th => counts(j -> y0mask(Yv[j], w, th), lives, Ns, S, L80) for th in TH80Y)
        ok = [th for th in TH80Y if cy[th].X >= 0.9 * cy[th].K]
        ts = isempty(ok) ? nothing : maximum(ok)
        println(io, "== Y0c w=$w$(w == 1000 ? " (main)" : " (descriptive)"): θ* = $(ts === nothing ? "none" : ts)$(ts === nothing ? "" : "  X/K=$(cy[ts].X)/$(cy[ts].K) Z/W=$(cy[ts].Z)/$(cy[ts].W)")")
        println(io, "  [curve] θ: X/K Z/W  " * join(["$th: $(cy[th].X)/$(cy[th].K) $(cy[th].Z)/$(cy[th].W)" for th in TH80Y if th <= 30 || th % 10 == 0], " | "))
        # descriptive: false-alarm count at matched detection levels
        for x in 30:-1:15
            a = [cy[th].Z for th in TH80Y if cy[th].X >= x]; b = [c4[h].Z for h in HSCAN if c4[h].X >= x]
            println(io, "  [matched] detection >= $x/30: min Z  Y0c $(isempty(a) ? "-" : minimum(a))  C4 $(isempty(b) ? "-" : minimum(b))")
        end
        bt = nothing; bc = -Inf
        for th in TH80Y; v = crit2(cy[th]); v > bc && (bc = v; bt = th); end
        vy = verdict2(cy[bt].X, cy[bt].K, cy[bt].Z, cy[bt].W)
        println(io, "  [crit2 pooled] θ=$bt X/K=$(cy[bt].X)/$(cy[bt].K) Z/W=$(cy[bt].Z)/$(cy[bt].W) -> $(vy.v)")
        res[w] = (ts = ts, cy = cy, crit = vy.v)
    end
    bh = nothing; bc = -Inf
    for h in HSCAN; v = crit2(c4[h]); v > bc && (bc = v; bh = h); end
    v4 = verdict2(c4[bh].X, c4[bh].K, c4[bh].Z, c4[bh].W)
    println(io, "== C4 [crit2 pooled] h=$bh X/K=$(c4[bh].X)/$(c4[bh].K) Z/W=$(c4[bh].Z)/$(c4[bh].W) -> $(v4.v)")
    r = res[1000]
    if r.ts === nothing
        println(io, "no θ* for w=1000; Y1-Y3 not computable")
    else
        c = r.cy[r.ts]
        fw4 = vcat([fwins(mk4(j, h4), Ns[j]) for j in lives]...); fwy = vcat([fwins(y0mask(Yv[j], 1000, r.ts), Ns[j]) for j in lives]...)
        length(fw4) == 120 && count(fw4) == 31 && count(fwy) == c.Z || error("overlap gate")
        # codex I-R P4: rebuild both false-window sets keyed by (life, start, stop) and check the intersection count
        key(mk) = Set((j, first(w), last(w)) for j in lives for w in routinewins(Ns[j], L80) if any(view(mk(j), w)))
        k4 = key(j -> mk4(j, h4)); ky = key(j -> y0mask(Yv[j], 1000, r.ts))
        length(k4) == 31 && length(ky) == c.Z && length(intersect(k4, ky)) == count(fw4 .& fwy) || error("keyed overlap gate")
        ov = count(fw4 .& fwy) / count(fw4)
        println(io, "overlap: C4 false windows $(count(fw4)), Y0c false windows $(count(fwy)), both $(count(fw4 .& fwy)) -> $(f4(ov))")
        # descriptive: overlap at the Y0c θ whose Z is closest to 31 (matched false-alarm count)
        tm = TH80Y[argmin([abs(r.cy[th].Z - 31) for th in TH80Y])]
        fwm = vcat([fwins(y0mask(Yv[j], 1000, tm), Ns[j]) for j in lives]...)
        println(io, "  [desc] Y0c θ=$tm (Z=$(r.cy[tm].Z), X/K=$(r.cy[tm].X)/$(r.cy[tm].K)): both $(count(fw4 .& fwm)) of C4's 31")
        # descriptive: which selected switches each clock misses at its operating point
        for j in lives, i in S[j]
            m4 = !any(view(mk4(j, h4), formwin(i, L80))); my = !any(view(y0mask(Yv[j], 1000, r.ts), formwin(i, L80)))
            (m4 || my) && println(io, "  [missed] st$(j[1]) life $(j[2]) i=$i C4 $(m4 ? "miss" : "hit") Y0c $(my ? "miss" : "hit")")
        end
        println(io, "S80-Y1 (Y0c Z/W at θ* > 0.10): $(c.Z / c.W > 0.10 ? "holds" : "miss")  $(c.Z)/$(c.W)")
        println(io, "S80-Y2 (16 <= Z <= 46 at θ*): $(16 <= c.Z <= 46 ? "holds" : "miss")  Z=$(c.Z)")
        println(io, "S80-Y3 (overlap >= 0.6): $(ov >= 0.6 ? "holds" : "miss")  $(f4(ov))")
    end
    println(io, "S80-Y4 (crit2 pooled verdict not pass for Y0c w=1000 and C4): $(r.crit != "pass" && v4.v != "pass" ? "holds" : "miss")  Y0c $(r.crit), C4 $(v4.v)")
    s = String(take!(io)); print(s); write(joinpath(OUT80Y, "y0clock.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    run80y()
end
