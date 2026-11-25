# S73 dev (discussion/specs/S73-draft-self-clock-dev.md): self-baseline clock (A) and experience-made individual difference (B).
# Tables only, S72 stage-1 lives. Includes the S72 r4 code unchanged (its main block does not run when included).
# usage: julia --project=. experiments/s73_selfclock/s73.jl run
include(joinpath(@__DIR__, "..", "s72_open", "s72r4.jl"))

const OUT73 = joinpath(@__DIR__, "out"); mkpath(OUT73)
const SWIN = 500; const SBASE = 3000; const EVLEN = 1500
const THETA73 = [0.005, 0.01, 0.02, 0.04]

# ---- A: the self-baseline clock (own losses only)
selffire(ℓ, a, theta) = mean(ℓ[a:a+SWIN-1]) - mean(ℓ[a-SBASE:a-1]) > theta
function selfclock(res, theta, S)
    ℓ = losses(res.P, res.Y); N = res.N; nf = 0
    for i in 0:4
        r = rint(N, i); tail = (last(r) - RTAIL + 1):last(r)
        for w in 0:2; nf += selffire(ℓ, first(tail) + w * SWIN, theta); end
    end
    det = Dict(i => selffire(ℓ, TS[i] + 1, theta) for i in 1:4)
    fr = nf / 15; dall = count(values(det)) / 4
    dsel = isempty(S) ? nothing : count(i -> det[i], S) / length(S)
    return (false_rate = fr, det_all = dall, nsel = length(S), det_sel = dsel, ok = dsel !== nothing && fr <= FSTAR && dsel >= DSTAR)
end

# ---- B: paired histories H (π_1 on [T_1, T_2)) and H' (π'_1 there); identical afterwards; π_1 returns at T_4
function paired(kind, life)
    streams = Dict(u => stream2(u) for u in SEEDS_ST1)
    lf = make_life2(life, SEEDS_ST1, streams); maps, alts = life_maps(life)
    L = new_learner4(kind, life)
    p0, y0v = span!(L, lf, 1, TS[1] + 1, maps[1])
    out = Dict{String,Any}()
    for (nm, m2) in (("H", maps[2]), ("Hp", alts[1]))
        X = deepcopy(L); ps = copy(p0); ys = copy(y0v); hT4 = ""
        for (a, b, m) in ((TS[1], TS[2], m2), (TS[2], TS[3], maps[3]), (TS[3], TS[4], maps[4]), (TS[4], TS[4] + EVLEN, maps[2]))
            a == TS[4] && (hT4 = statehash(X))     # state right after example T_4, before the return (codex I-R P1)
            q, z = span!(X, lf, a + 1, b + 1, m); append!(ps, q); append!(ys, z)
        end
        ℓ = losses(ps, ys); T = TS[4]
        out[nm] = (P = ps, Y = ys, pre = mean(ℓ[T-SBASE+1:T]), post = mean(ℓ[T+1:T+SWIN]), state = hT4)
    end
    T = TS[4]
    H = out["H"]; Hp = out["Hp"]
    return (kind = kind, life = life, SH = H.post - H.pre, SHp = Hp.post - Hp.pre, D = (Hp.post - Hp.pre) - (H.post - H.pre),
            dpost = Hp.post - H.post, dpre = Hp.pre - H.pre, preH = H.pre, preHp = Hp.pre, postH = H.post, postHp = Hp.post,
            y0ev = count(!, H.Y[T+1:T+SWIN]), Pmain = H.P[1:T], Ymain = H.Y[1:T], same_state_T4 = H.state == Hp.state)
end

function run73()
    io = IOBuffer()
    w0 = TOML.parsefile(W0_R3)["w0"]
    R = Dict((k, l) => loadlife4(1, k, l) for k in ("FGT", "CUM", "WIN") for l in 1:NLIFE)
    println(io, "== A: self-baseline clock (window $SWIN vs own preceding $SBASE; selected switches = S72 r4 stage 1 at eps 0.0025)")
    for k in ("FGT", "CUM", "WIN"), l in 1:NLIFE
        S = selset(R[(k, l)], 0.0025, w0)
        for th in THETA73
            c = selfclock(R[(k, l)], th, S)
            println(io, "  $k life $l theta=$th false_rate=$(f5(c.false_rate)) det_all=$(f5(c.det_all)) det_sel=$(c.det_sel === nothing ? "not computable" : f5(c.det_sel)) (n=$(c.nsel)) ok=$(c.ok)")
        end
        r = trace1_3(R[(k, l)], 0.04, S)
        println(io, "  $k life $l [compare: S72 r4 L-REF clock theta=0.04] false_rate=$(f5(r.false_rate)) det_all=$(f5(r.det_all)) det_sel=$(r.ndet_sel)/$(r.nsel)")
    end
    passA = [th for th in THETA73 if all(l -> selfclock(R[("FGT", l)], th, selset(R[("FGT", l)], 0.0025, w0)).ok, 1:NLIFE)]
    for th in THETA73
        println(io, "grid A FGT theta=$th: lives ok $(count(l -> selfclock(R[("FGT", l)], th, selset(R[("FGT", l)], 0.0025, w0)).ok, 1:NLIFE))/4")
    end
    println(io, "Q1 (no theta separates for L-FGT): $(isempty(passA) ? "holds" : "miss (theta $(minimum(passA)) passes)")")
    println(io, "== B: paired histories, pi_1 returns at T_4 (first $SWIN examples vs own preceding $SBASE)")
    B = Dict{Tuple{String,Int},Any}()
    for k in ("FGT", "CUM", "WIN"), l in 1:NLIFE
        b = paired(k, l); B[(k, l)] = b
        (reinterpret(UInt64, b.Pmain) == reinterpret(UInt64, R[(k, l)].P[1:TS[4]]) && b.Ymain == R[(k, l)].Y[1:TS[4]]) || error("H main history differs from the S72 r4 saved main stream: $k $l")
        println(io, "  $k life $l S_H=$(f5(b.SH)) S_H'=$(f5(b.SHp)) D=$(f5(b.D)) (dpost=$(f5(b.dpost)) dpre=$(f5(b.dpre))) pre H/H'=$(f5(b.preH))/$(f5(b.preHp)) post H/H'=$(f5(b.postH))/$(f5(b.postHp)) Y0 in event=$(b.y0ev) same_state_T4=$(b.same_state_T4)")
    end
    for l in 1:NLIFE   # gate: window table forgets the history difference exactly
        b = B[("WIN", l)]
        b.same_state_T4 && b.preH === b.preHp && b.postH === b.postHp && b.D == 0 || error("WIN gate failed: life $l")
    end
    println(io, "gate: WIN D == 0, pre and post means bit-identical, states identical at T_4 (4 lives); H histories == S72 r4 saved main streams (12)")
    q2 = all(l -> B[("CUM", l)].D > 0, 1:NLIFE)
    q3 = all(l -> abs(B[("FGT", l)].D) < B[("CUM", l)].D, 1:NLIFE)
    println(io, "Q2 (CUM D > 0 in 4/4): $(q2 ? "holds" : "miss") ($(count(l -> B[("CUM", l)].D > 0, 1:NLIFE))/4)")
    println(io, "Q3 (|D_FGT| < D_CUM in 4/4): $(q3 ? "holds" : "miss") ($(count(l -> abs(B[("FGT", l)].D) < B[("CUM", l)].D, 1:NLIFE))/4)")
    s = String(take!(io)); print(s); write(joinpath(OUT73, "s73.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    ARGS[1] == "run" && run73()
end
