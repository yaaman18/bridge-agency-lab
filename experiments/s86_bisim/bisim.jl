# S86 bisimulation invariance of the lab's definitions (discussion/specs/S86-draft-bisim-invariance.md; predictions frozen;
# codex S-R 2026-11-26 P1-P6; BP14 / H11). Seen 48 lives only; no new seeds; law numbers unchanged.
# Includes s85_tick/tick.jl unchanged (and through it s84/s83/...); their main blocks do not run when included.
# usage: julia --project=. -t 8 experiments/s86_bisim/bisim.jl
include(joinpath(@__DIR__, "..", "s85_tick", "tick.jl"))
const PRED86 = joinpath(@__DIR__, "predictions.toml"); const OUT86 = joinpath(@__DIR__, "out"); mkpath(OUT86)
const FREEZE86 = joinpath(@__DIR__, "..", "freeze-s86.txt")
const GR86 = ("F", "R", "C")

# implementations of the same coalgebra: w = count scale (power of 2), sq = count the outcome as y^2; fixed = ignore input
struct Imp; name::String; w::Float64; sq::Bool; fixed::Bool; end
const IMPS = (Imp("A", 1.0, false, false), Imp("B", 1.0, true, false), Imp("C", 4.0, false, false), Imp("D", 4.0, true, false))
const F0 = Imp("F0", 1.0, false, true)
newc() = C85(zeros(2), zeros(2), zeros(NK), zeros(NK))
function addI!(c, k, a, y, m::Imp)            # y in {0,1} (interface) or a fraction (outside the interface: S85 Theta only)
    m.fixed && return c
    yy = m.sq ? y^2 : y
    c.n[a] += m.w; c.n1[a] += m.w * yy; c.rn[k] += m.w; c.rn1[k] += m.w * yy; return c
end
stepI!(c, k, a, y, lam, m::Imp) = (m.fixed || decay!(c, lam); addI!(c, k, a, y, m))
rawI(c, k, m::Imp) = (a = akey(k); rate = (c.n1[a] + m.w) / (c.n[a] + 2m.w); (c.rn1[k] + (ALPHA_R1 * m.w) * rate) / (c.rn[k] + ALPHA_R1 * m.w))
tabI(c, m::Imp) = m.fixed ? fill(0.5, NK) : [clip(rawI(c, k, m)) for k in 1:NK]
minnz(c) = minimum(x -> x == 0 ? Inf : abs(x), vcat(c.n, c.n1, c.rn, c.rn1))

# one life under implementation m: tables after every example, states at the origins
function runI(m, K, A, Y, N, lam, orig)
    c = newc(); Tab = Matrix{Float64}(undef, NK, N + 1); Tab[:, 1] = tabI(c, m); st = Dict{Int,C85}(); mn = Inf
    0 in orig && (st[0] = deepcopy(c))
    for t in 1:N
        stepI!(c, K[t], A[t], Float64(Y[t]), lam, m); Tab[:, t+1] = tabI(c, m); mn = min(mn, minnz(c))
        t in orig && (st[t] = deepcopy(c))
    end
    return Tab, st, mn
end
# flip twin: from the state after t0, example t0+1 gets 1 - y; returns tables at steps 1..h (columns)
function flipI(c0, m, K, A, Y, t0, h, lam; flip = true)
    c = deepcopy(c0); out = Matrix{Float64}(undef, NK, h)
    for j in 1:h
        t = t0 + j; y = Float64(Y[t]); (flip && j == 1) && (y = 1 - y)
        stepI!(c, K[t], A[t], y, lam, m); out[:, j] = tabI(c, m)
        if flip && j == 1 && !m.fixed && m.name == "A"          # flip effect gate (P6): difference = 1 - 2y at (a,k) only
            r = step!(deepcopy(c0), K[t], A[t], Float64(Y[t]), lam); a = A[t]; k = K[t]; dy = 1 - 2Float64(Y[t])
            (isapprox(c.n1[a] - r.n1[a], dy; atol = 4eps(max(1.0, abs(r.n1[a])))) && isapprox(c.rn1[k] - r.rn1[k], dy; atol = 4eps(max(1.0, abs(r.rn1[k]))))) || error("flip effect gate $t")
            (sameb(c.n, r.n) && sameb(c.rn, r.rn) && all(i -> i == a || bits(c.n1[i]) == bits(r.n1[i]), 1:2) &&
             all(i -> i == k || bits(c.rn1[i]) == bits(r.rn1[i]), 1:NK)) || error("flip effect other components gate $t")
        end
    end
    return out
end
# S85 Theta under implementation m: decay -> unclipped raw -> m's own add (fraction enters through m's encoding)
function thetaI(c0, m, K, A, t0, h, lam)
    c = deepcopy(c0)
    for t in (t0 + 1):(t0 + h); decay!(c, lam); addI!(c, K[t], A[t], rawI(c, K[t], m), m); end
    return tabI(c, m)
end

function life86(x)
    O = origins84(x); orig = Set{Int}(vcat([O[(g, h)] for g in GR86, h in HS84]...))
    R = replay84(x.lf, x.life, x.P, orig)                         # S84 gates on the official law
    lf = x.lf; N = lf.N; maps, _ = life_maps(x.life); bounds = vcat(0, TS, N)
    K = zeros(Int, N); A = zeros(Int, N); Y = zeros(Bool, N)
    for t in 1:N; si, s = lf.ex[t]; stt = lf.streams[si]; seg = searchsortedfirst(bounds, t) - 1
        A[t] = stt.act[s+1]; Y[t] = stt.Y[s+1]; K[t] = keyfor(stt, s, A[t], maps[seg]); end
    lam = R.lam; runs = Dict{String,Any}(); mins = Dict{String,Float64}()
    for m in (IMPS..., F0)
        Tab, st, mn = runI(m, K, A, Y, N, lam, orig); runs[m.name] = (Tab = Tab, st = st); mins[m.name] = mn
        m.fixed && continue
        sameb(vec(Tab), vec(R.Tab)) || error("G1 table gate $(m.name)")                 # A: = official law; B,C,D: bisimilar
        mn >= floatmin(Float64) * 2.0^10 || error("normal range gate $(m.name) $mn")       # P2
    end
    rows = Dict{Tuple{String,Int},Vector{NamedTuple}}()
    for g in GR86, h in HS84, t0 in O[(g, h)]
        D = Dict{String,Float64}(); Nn = Dict{String,Float64}(); Gd = Dict{String,Float64}(); Th = Dict{String,Vector{Float64}}(); dd = Dict{String,Float64}()
        twA = nothing; hf = min(h + 1, N - t0); ok = hf == h + 1
        for m in (IMPS..., F0)
            ru = runs[m.name]; tw = flipI(ru.st[t0], m, K, A, Y, t0, hf, lam)            # flip at s = t0+1, follow to s+h (I-R P4)
            m.name == "A" && (twA = tw)
            if !m.fixed                                                                     # G1 on the flip twin's sequence
                sameb(vec(tw), vec(twA)) || error("G1 flip twin gate $(m.name) $t0")
            end
            D[m.name] = ok ? l1(view(ru.Tab, :, t0 + hf + 1), view(tw, :, hf)) : NaN      # D_s(s+h), column t0+h+2
            Nn[m.name] = l1(view(ru.Tab, :, t0 + 1), view(ru.Tab, :, t0 + h + 1))
            Gd[m.name] = l1(view(ru.Tab, :, t0 + h + 1), view(ru.Tab, :, 1))
            dd[m.name] = sum(s -> l1(view(ru.Tab, :, s), view(ru.Tab, :, s + 1)), (t0 + 1):(t0 + h))
            m.fixed || (Th[m.name] = thetaI(ru.st[t0], m, K, A, t0, h, lam))
        end
        nf = flipI(runs["A"].st[t0], IMPS[1], K, A, Y, t0, h, lam; flip = false)              # unflipped twin = A
        sameb(vec(nf), vec(view(R.Tab, :, (t0 + 2):(t0 + h + 1)))) || error("unflipped twin gate $t0")
        for nm in ("B", "C", "D")                                                           # G2
            (bits(D[nm]) == bits(D["A"]) && bits(Nn[nm]) == bits(Nn["A"]) && bits(Gd[nm]) == bits(Gd["A"]) && bits(dd[nm]) == bits(dd["A"])) || error("G2 gate $nm $t0")
        end
        (isequal(D["F0"], ok ? 0.0 : NaN) && Nn["F0"] == 0 && Gd["F0"] == 0 && dd["F0"] == 0) || error("G3 fixed program gate $t0")
        o85, _ = twin(R.st0[t0] |> (q -> C85(q...)), K, A, (t0 + 1):(t0 + h), lam, Set([h]))   # Theta_A = S85 twin, bitwise
        sameb(o85[h], Th["A"]) || error("Theta_A = S85 gate $t0")
        TA = l1(view(R.Tab, :, t0 + h + 1), Th["A"])
        push!(get!(rows, (g, h), NamedTuple[]), (D = D["A"], ThA = TA, ThB = l1(view(R.Tab, :, t0 + h + 1), Th["B"]),
            ThC = l1(view(R.Tab, :, t0 + h + 1), Th["C"]), ThD = l1(view(R.Tab, :, t0 + h + 1), Th["D"])))
    end
    return (id = x.id, rows = rows, nS = length(x.S), mins = mins)
end

function run86()
    h = bytes2hex(sha256(read(PRED86))); any(==("$h  experiments/s86_bisim/predictions.toml"), split(read(FREEZE86, String), "\n")) || error("predictions not frozen")
    io = IOBuffer(); LV = lives83(); length(LV) == 48 || error("48 lives")
    res = tmapv(life86, LV); sum(r.nS for r in res) == 183 || error("K gate")
    println(io, "gate: S84 gates on the official law; G1 tables of A,B,C,D bitwise equal on every step of every life and on every flip twin; normal range of nonzero counts (min $(minimum(minimum(values(r.mins)) for r in res))); flip effect = 1-2y at (a,k) only; unflipped twin = A; G2 D_s, N, G, sum d bitwise equal across A,B,C,D; G3 fixed program all zero; Theta_A = S85 twin bitwise; K = 183")
    pool(g, hh) = vcat([get(r.rows, (g, hh), NamedTuple[]) for r in res]...)
    fld(v, f) = [getfield(a, f) for a in v]
    println(io, "== groups (pooled; D = flip trace D_s(s+h) of the outcome at s = t0+1, read at example s+h; Theta_X = S85 Theta under implementation X)")
    for g in GR86, hh in HS84
        v = pool(g, hh); isempty(v) && continue
        z = count(a -> a.D == 0, v); v = filter(a -> !isnan(a.D), v) |> (w -> isempty(w) ? v : w)
        rb = [a.ThB / a.ThA for a in v if a.ThA > 0]; rd = [a.ThD / a.ThA for a in v if a.ThA > 0]
        println(io, "  $g h=$hh: n $(length(v))  D $(q3(fld(v, :D)))  D=0: $z  Theta A $(q3(fld(v, :ThA)))  B $(q3(fld(v, :ThB)))  C $(q3(fld(v, :ThC)))  D $(q3(fld(v, :ThD)))  B/A $(q3(rb))  D/A $(q3(rd))  B!=A bitwise $(count(a -> bits(a.ThB) != bits(a.ThA), v))")
    end
    diffB = [g for g in GR86 if !isempty(pool(g, 200)) && median(fld(pool(g, 200), :ThB)) != median(fld(pool(g, 200), :ThA))]
    diffD = [g for g in GR86 if !isempty(pool(g, 200)) && median(fld(pool(g, 200), :ThD)) != median(fld(pool(g, 200), :ThA))]
    allv = vcat([pool(g, hh) for g in GR86, hh in HS84]...)
    cEq = all(a -> bits(a.ThC) == bits(a.ThA), allv)
    e1 = !isempty(diffB) && !isempty(diffD) && cEq ? "hit" : "miss"
    v1000 = filter(a -> !isnan(a.D), vcat([pool(g, 1000) for g in GR86]...)); npos = count(a -> a.D > 0, v1000)
    nex = count(a -> isnan(a.D), vcat([pool(g, 1000) for g in GR86]...))
    e2 = isempty(v1000) ? "undecidable" : npos >= 1 ? "hit" : "miss"
    println(io, "E1: h=200 groups with median Theta_B != Theta_A: $(diffB); Theta_D != Theta_A: $(diffD); Theta_C = Theta_A bitwise at all $(length(allv)) origins: $cEq -> $e1")
    println(io, "E2: origins with D_s(s+1000) > 0: $npos / $(length(v1000)) (origins without s+1000 in the life, excluded: $nex) -> $e2")
    println(io, "S86-E1: $e1"); println(io, "S86-E2: $e2")
    println(io, "note: seen lives only. Interface-only definitions are invariant by construction (gates G1-G3); E1 tests that S85 Theta is not.")
    s = String(take!(io)); print(s); write(joinpath(OUT86, "bisim.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    run86()
end
