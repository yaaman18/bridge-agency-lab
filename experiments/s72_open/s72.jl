# S72 dev: R-AUE-OPEN-1 / OPEN-2 / TRACE-1 on candidate learners (discussion/specs/S72-draft-open-trace-dev.md).
# usage: julia --project=. -t N experiments/s72_open/s72.jl calib | run <TRM|CUM|FGT> <life 1..4> | all <nthreads-jobs> | judge
include(joinpath(@__DIR__, "..", "c0r_dev", "lib.jl"))
using Serialization

const OUT = joinpath(@__DIR__, "out"); mkpath(OUT)
const SEEDS18 = collect(1050:1067)
const NLIFE = 4
const TS = [8000, 20000, 32000, 44000]
const BLK = 8
const RING = 512
const LR = 1e-3
const LAMBDA = 1 - 1 / 2000
const EPS = 0.005
const WIN = 250
const CAP = 6000
const LB = 1504; const DLEN = 1000; const NPROBE = 400
const DELTA = 0.01
const CB = 50; const ZTH = 3.0; const LF = 2.0; const UR = 1.0
const FLEN = 1500; const RLEN = 3000; const RTAIL = 1500
const MAPSEED = 720001; const RINGSEED = 720100

# ---- mappings on the six TAB_R1 receptors: value at R1IDX[j] := r[R1IDX[perm[j]]] xor flip[j]
struct Map; perm::Vector{Int}; flip::Vector{Bool}; end
const ID = Map(collect(1:6), falses(6))
compose(rho::Map, pi::Map) = Map([pi.perm[rho.perm[j]] for j in 1:6], [pi.flip[rho.perm[j]] ⊻ rho.flip[j] for j in 1:6])
function draw_rho(r)
    while true
        perm = collect(1:6)
        for j in 6:-1:2; k = 1 + floor(Int, j * r()); perm[j], perm[k] = perm[k], perm[j]; end
        perm == collect(1:6) || return Map(perm, trues(6))
    end
end
function life_maps(life)
    r = Mulberry(MAPSEED + life)
    maps = Map[ID]; alts = Map[]
    for i in 1:4
        prev = maps[end]
        local m, a
        while true; m = compose(draw_rho(r), prev); m in maps || break; end
        push!(maps, m)
        while true; a = compose(draw_rho(r), prev); (a in maps || a in alts) || break; end
        push!(alts, a)
    end
    return maps, alts   # maps[1] = π0, maps[i+1] = π_i; alts[i] = π'_i
end
function rbit(st::Stream, m::Map, k::Int, col::Int)
    j = findfirst(==(k), R1IDX)
    j === nothing && return st.r[k, col]
    return st.r[R1IDX[m.perm[j]], col] ⊻ m.flip[j]
end

# ---- a life: the example list (stream index, step s) over 12 seeds
struct Life; streams::Vector{Stream}; ex::Vector{Tuple{Int,Int}}; N::Int; end
function stream_cached(u)
    f = joinpath(OUT, "stream_$u.jls")
    isfile(f) && return deserialize(f)
    st = obs_stream(u, "stat"); serialize(f, st); return st
end
function make_life(life, streams::Dict{Int,Stream})
    seeds = [SEEDS18[mod(life - 1 + k, 18) + 1] for k in 0:11]
    sts = [streams[u] for u in seeds]
    ex = Tuple{Int,Int}[]
    for (i, st) in enumerate(sts), s in 0:NS-1
        st.isex[s+1] && push!(ex, (i, s))
    end
    N = BLK * (length(ex) ÷ BLK)
    return Life(sts, ex[1:N], N)
end
function encode_map!(tok, col, st::Stream, s::Int, m::Map)
    tok[1, col] = 0x00
    for f in 1:W4
        j = s - W4 - 1 + f; base = 1 + (f - 1) * 11
        if j < 0
            for q in 1:11; tok[base+q, col] = 0x00; end
        else
            for k in 1:8; tok[base+k, col] = rbit(st, m, k, j + 1) ? 0x02 : 0x01; end
            tok[base+9, col] = 0x00
            a = st.act[j+1]
            tok[base+10, col] = a == 0 ? 0x03 : a == 1 ? 0x04 : 0x05
            tok[base+11, col] = st.act[j+1] == 0 ? 0x06 : st.Y[j+1] ? 0x08 : 0x07
        end
    end
    tok[46, col] = 0x09; tok[47, col] = 0x0a
    return tok
end
function r1key_map(st, s, a, m::Map)
    s == 0 && return 2 * 64 + a
    k = 0
    for (i, mm) in enumerate(R1IDX); rbit(st, m, mm, s) && (k += 1 << (i - 1)); end
    return 2 * k + a
end

# ---- learners
mutable struct TrmL; p; o; ring_tok::Matrix{UInt8}; ring_act::Vector{Int}; ring_Y::Vector{Bool}; nring::Int; head::Int; r; end
mutable struct TabL; n::Vector{Float64}; n1::Vector{Float64}; rn::Vector{Float64}; rn1::Vector{Float64}; lam::Float64; end
new_learner(kind, life) = kind == "TRM" ?
    (p = TrmC0.init_params(Mulberry(INITSEED)); TrmL(p, TrmC0.Opt(p), zeros(UInt8, S, RING), zeros(Int, RING), falses(RING), 0, 0, Mulberry(RINGSEED + life))) :
    TabL(zeros(2), zeros(2), zeros(130), zeros(130), kind == "FGT" ? LAMBDA : 1.0)

function predict_block(L::TabL, lf::Life, idx, m::Map)
    out = Float64[]
    for t in idx
        si, s = lf.ex[t]; st = lf.streams[si]; a = st.act[s+1]
        rate = (L.n1[a] + 1) / (L.n[a] + 2); k = r1key_map(st, s, a, m)
        push!(out, clip((L.rn1[k] + ALPHA_R1 * rate) / (L.rn[k] + ALPHA_R1)))
    end
    return out
end
function update_block!(L::TabL, lf::Life, idx, m::Map)
    for t in idx
        si, s = lf.ex[t]; st = lf.streams[si]; a = st.act[s+1]; y = st.Y[s+1]; k = r1key_map(st, s, a, m)
        if L.lam < 1; L.n .*= L.lam; L.n1 .*= L.lam; L.rn .*= L.lam; L.rn1 .*= L.lam; end
        L.n[a] += 1; L.n1[a] += y; L.rn[k] += 1; L.rn1[k] += y
    end
end
function block_tok(lf::Life, idx, m::Map)
    tok = Matrix{UInt8}(undef, S, length(idx)); act = Int8[]; Y = Bool[]
    for (c, t) in enumerate(idx)
        si, s = lf.ex[t]; st = lf.streams[si]
        encode_map!(tok, c, st, s, m); push!(act, st.act[s+1]); push!(Y, st.Y[s+1])
    end
    return tok, act, Y
end
function predict_block(L::TrmL, lf::Life, idx, m::Map)
    tok, act, Y = block_tok(lf, idx, m)
    return predict_set(L.p, CFG_1X1, ExSet(-1, tok, act, Y, collect(idx))).p
end
function update_block!(L::TrmL, lf::Life, idx, m::Map)
    tok, act, Y = block_tok(lf, idx, m)
    for c in eachindex(act)
        L.head = L.head % RING + 1
        L.ring_tok[:, L.head] .= tok[:, c]; L.ring_act[L.head] = act[c]; L.ring_Y[L.head] = Y[c]
        L.nring = min(L.nring + 1, RING)
    end
    L.nring < BATCH && return
    w = get!(() -> TrmC0.WorkSet{Float32}(CFG_1X1.Lc + 1, ROPE...), task_local_storage(), :s72_ws)
    g = get!(() -> TrmC0.Params{Float32}(), task_local_storage(), :s72_g)
    bt = Matrix{UInt8}(undef, S, BATCH); ba = Vector{Int}(undef, BATCH); bY = Vector{Bool}(undef, BATCH)
    for b in 1:BATCH
        i = 1 + floor(Int, L.nring * L.r())
        bt[:, b] .= L.ring_tok[:, i]; ba[b] = L.ring_act[i]; bY[b] = L.ring_Y[i]
    end
    TrmC0.train_step!(L.p, g, L.o, w, CFG_1X1, bt, ba, bY, LR, 0.0; ce = CE)
end
loss(p, y) = -log(y ? p : 1 - p)
mloss(r) = mean(loss(r[1][k], r[2][k]) for k in eachindex(r[1]))
# run blocks over [a, b) with mapping m; returns p, y (prequential)
function run_span!(L, lf::Life, a, b, m::Map; update = true)
    ps = Float64[]; ys = Bool[]
    for t0 in a:BLK:b-1
        idx = t0:min(t0 + BLK - 1, b - 1)
        append!(ps, predict_block(L, lf, idx, m))
        for t in idx; si, s = lf.ex[t]; push!(ys, lf.streams[si].Y[s+1]); end
        update && update_block!(L, lf, idx, m)
    end
    return ps, ys
end
statehash(L::TrmL) = bytes2hex(sha256(reinterpret(UInt8, vcat([vec(Float64.(x)) for x in TrmC0.plist(L.p)]..., Float64(L.head), Float64(L.nring)))))
statehash(L::TabL) = bytes2hex(sha256(reinterpret(UInt8, vcat(L.n, L.n1, L.rn, L.rn1))))

function run_life(kind, life, streams)
    lf = make_life(life, streams); maps, alts = life_maps(life)
    N = lf.N; N >= TS[end] + CAP || error("life too short: $N")
    L = new_learner(kind, life)
    P = Float64[]; Yv = Bool[]
    bounds = vcat(0, TS, N)
    br = Dict{Int,Any}(); fresh = Dict{Int,Any}(); keych = Dict{Int,Float64}()
    for seg in 1:5
        a, b = bounds[seg], bounds[seg+1]; m = maps[seg]
        if seg >= 2
            i = seg - 1
            # key change rate on R_{i-1} examples (old vs new mapping)
            ch = 0; tot = 0
            for t in a-RLEN:a-1
                si, s = lf.ex[t+1]; st = lf.streams[si]; ac = st.act[s+1]
                tot += 1; ch += r1key_map(st, s, ac, maps[seg-1]) != r1key_map(st, s, ac, m)
            end
            keych[i] = ch / tot
            h0 = statehash(L)
            A = deepcopy(L); B = deepcopy(L); C1 = deepcopy(L); C2 = deepcopy(L)
            bA = run_span!(A, lf, a + 1, a + 1 + LB, m); bB = run_span!(B, lf, a + 1, a + 1 + LB, alts[i])
            run_span!(C1, lf, a + 1, a + 1 + LB, m); run_span!(C2, lf, a + 1, a + 1 + LB, m)
            pr = a + 1 + LB + DLEN
            dpre = mean(abs.(run_span!(deepcopy(A), lf, pr, pr + NPROBE, ID; update = false)[1] .- run_span!(deepcopy(B), lf, pr, pr + NPROBE, ID; update = false)[1]))
            dA = run_span!(A, lf, a + 1 + LB, pr, ID); dB = run_span!(B, lf, a + 1 + LB, pr, ID)
            run_span!(C1, lf, a + 1 + LB, pr, ID); run_span!(C2, lf, a + 1 + LB, pr, ID)
            pA = run_span!(A, lf, pr, pr + NPROBE, ID; update = false)[1]; pB = run_span!(B, lf, pr, pr + NPROBE, ID; update = false)[1]
            pC1 = run_span!(C1, lf, pr, pr + NPROBE, ID; update = false)[1]; pC2 = run_span!(C2, lf, pr, pr + NPROBE, ID; update = false)[1]
            statehash(L) == h0 || error("branching changed the main state")
            br[i] = (delta = mean(abs.(pA .- pB)), delta_preD = dpre, selfcheck = maximum(abs.(pC1 .- pC2)), lossbranch_A = mloss(bA), lossbranch_B = mloss(bB), lossD_A = mloss(dA), lossD_B = mloss(dB))
            F = new_learner(kind, life)
            fp, fy = run_span!(F, lf, a + 1, a + 1 + CAP, m)
            fresh[i] = [loss(fp[k], fy[k]) for k in eachindex(fp)]
        end
        ps, ys = run_span!(L, lf, a + 1, b + 1, m)   # 1-based example indices a+1..b
        append!(P, ps); append!(Yv, ys)
    end
    res = (kind = kind, life = life, N = N, P = P, Y = Yv, branches = br, fresh = fresh, keych = keych,
           maps = maps, alts = alts)
    serialize(joinpath(OUT, "life_$(kind)_$(life).jls"), res)
    return res
end

# ---- the clock and judgements
function clock_blocks(P, Y, a, b)   # increments per 50-example block over [a, b) (1-based example indices)
    c = Float64[]
    for t0 in a:CB:b-CB
        sd = 0.0; sv = 0.0
        for t in t0:t0+CB-1
            p = P[t]; y = Y[t]
            H = -(p * log(p) + (1 - p) * log(1 - p)); V = p * (1 - p) * (log(p / (1 - p)))^2
            sd += loss(p, y) - H; sv += V
        end
        push!(c, sv == 0 ? 0.0 : max(0.0, sd / sqrt(sv) - ZTH))
    end
    return c
end
function calib()
    r = Mulberry(729001); pass = 0; n = 10000
    for trial in 1:n
        P = Float64[]; Y = Bool[]
        for t in 1:30*CB; p = 0.05 + 0.9 * r(); push!(P, p); push!(Y, r() < p); end
        sum(clock_blocks(P, Y, 1, 30 * CB + 1)) <= UR && (pass += 1)
    end
    rate = pass / n
    s = @sprintf("calib: calibrated predictor, 30 blocks x %d trials, R pass rate %.4f (gate >= 0.95: %s)\n", n, rate, rate >= 0.95)
    print(s); write(joinpath(OUT, "calib.out"), s)
    return rate
end
function judge_life(res)
    ℓ = [loss(res.P[t], res.Y[t]) for t in eachindex(res.P)]; N = res.N
    bounds = vcat(0, TS, N)
    o1 = []; t1 = []
    for i in 1:4
        T = TS[i]; nxt = bounds[i+2]
        a_i = mean(ℓ[T-RLEN+1:T]); b_i = mean(ℓ[nxt-RLEN+1:nxt])
        early = mean(ℓ[T+1:T+WIN])
        measurable = early >= a_i + 3EPS; recovered = b_i <= a_i + 2EPS
        s = nothing
        for t in T+WIN:min(T + CAP, nxt)
            if mean(ℓ[t-WIN+1:t]) <= b_i + EPS; s = t - T; break; end
        end
        fl = res.fresh[i]; bf = mean(fl[end-1499:end]); sf = nothing   # fresh: its own level = mean of the last 1,500 of its 6,000 examples
        for t in WIN:length(fl); if mean(fl[t-WIN+1:t]) <= bf + EPS; sf = t; break; end; end
        push!(o1, (i = i, a = a_i, b = b_i, early = early, measurable = measurable, recovered = recovered, s = s, s_fresh = sf,
                   ratio = (s !== nothing && sf !== nothing) ? s / sf : nothing, keych = res.keych[i]))
        cF = sum(clock_blocks(res.P, res.Y, T + 1, T + FLEN + 1))
        cR = sum(clock_blocks(res.P, res.Y, nxt - RTAIL + 1, nxt + 1))
        push!(t1, (i = i, F = cF, R = cR, ok = cF >= LF && cR <= UR))
    end
    s1 = o1[1].s
    open1 = all(x -> x.measurable && x.recovered && x.s !== nothing, o1) &&
            all(x -> x.s <= 1.5 * s1 + 250, o1[2:end])
    all(i -> res.branches[i].selfcheck == 0, 1:4) || error("OPEN-2 self-check failed (same-map branches differ): life $(res.life) $(res.kind)")
    open2 = all(i -> res.branches[i].delta > DELTA, 1:4)
    return (o1 = o1, open1 = open1, br = res.branches, open2 = open2, t1 = t1, trace1 = all(x -> x.ok, t1))
end
fmt(x) = x === nothing ? "none" : x isa Bool ? string(x) : x isa Integer ? string(x) : @sprintf("%.5f", x)
function judge()
    io = IOBuffer()
    J = Dict{Tuple{String,Int},Any}()
    for kind in ("CUM", "FGT", "TRM"), life in 1:NLIFE
        f = joinpath(OUT, "life_$(kind)_$(life).jls"); isfile(f) || error("missing life file $f (judgement needs all $(NLIFE) lives)")
        j = judge_life(deserialize(f)); J[(kind, life)] = j
        println(io, "== $kind life $life: OPEN-1 $(j.open1)  OPEN-2 $(j.open2)  TRACE-1 $(j.trace1)")
        for x in j.o1
            println(io, "  OPEN-1 i=$(x.i) a=$(fmt(x.a)) b=$(fmt(x.b)) early=$(fmt(x.early)) measurable=$(x.measurable) recovered=$(x.recovered) s=$(fmt(x.s)) s_fresh=$(fmt(x.s_fresh)) s/s_fresh=$(fmt(x.ratio)) keych=$(fmt(x.keych))")
        end
        for i in 1:4
            b = j.br[i]
            println(io, "  OPEN-2 i=$i delta=$(fmt(b.delta)) delta_preD=$(fmt(b.delta_preD)) selfcheck=$(b.selfcheck) loss_branch A/B=$(fmt(b.lossbranch_A))/$(fmt(b.lossbranch_B)) loss_D A/B=$(fmt(b.lossD_A))/$(fmt(b.lossD_B))")
        end
        for x in j.t1; println(io, "  TRACE-1 i=$(x.i) F=$(fmt(x.F)) R=$(fmt(x.R)) ok=$(x.ok)"); end
    end
    for kind in ("CUM", "FGT", "TRM")
        xs = [x for l in 1:NLIFE for x in J[(kind, l)].o1]; s1 = Dict(l => J[(kind, l)].o1[1].s for l in 1:NLIFE)
        nm = count(x -> x.measurable, xs); nrec = count(x -> x.measurable && x.recovered, xs); nre = count(x -> x.measurable && x.s !== nothing, xs)
        nviol = count(l -> any(x -> x.s !== nothing && s1[l] !== nothing && x.s > 1.5 * s1[l] + 250, J[(kind, l)].o1[2:end]), 1:NLIFE)
        println(io, "OPEN-1 summary $kind: switches $(length(xs)), unmeasurable $(length(xs) - nm), measurable $nm, recovered $nrec/$nm, reached $nre/$nm (cap $CAP, right-censored), not-recovered $(nm - nrec), not-reached $(nm - nre), lives with non-inferiority violation $nviol/$NLIFE")
        println(io, "VERDICT $kind: OPEN-1 $(all(l -> J[(kind, l)].open1, 1:NLIFE))  OPEN-2 $(all(l -> J[(kind, l)].open2, 1:NLIFE))  TRACE-1 $(all(l -> J[(kind, l)].trace1, 1:NLIFE))")
    end
    # negative-control clocks: constant 1 per block -> F = R = 30; zero clock -> F = 0
    println(io, "negative clocks: constant F=30 R=30 ok=$(30 >= LF && 30 <= UR); zero F=0 R=0 ok=$(0 >= LF && 0 <= UR)")
    s = String(take!(io)); print(s); write(joinpath(OUT, "judge.out"), s)
    return J
end

if abspath(PROGRAM_FILE) == @__FILE__
    mode = ARGS[1]
    if mode == "calib"
        calib()
    elseif mode == "streams"
        sts = tmapv(stream_cached, SEEDS18); println("streams ok: ", length(sts))
    elseif mode == "run"
        streams = Dict(u => stream_cached(u) for u in SEEDS18)
        t = @elapsed run_life(ARGS[2], parse(Int, ARGS[3]), streams); println("done $(ARGS[2]) $(ARGS[3]) sec $(round(t))")
    elseif mode == "all"
        streams = Dict(u => stream_cached(u) for u in SEEDS18)
        jobs = vcat([("TRM", l) for l in 1:NLIFE], [(k, l) for k in ("CUM", "FGT") for l in 1:NLIFE])
        tmapv(j -> (t = @elapsed run_life(j[1], j[2], streams); println("done $(j[1]) $(j[2]) sec $(round(t))"); flush(stdout)), jobs)
    elseif mode == "judge"
        judge()
    end
end
