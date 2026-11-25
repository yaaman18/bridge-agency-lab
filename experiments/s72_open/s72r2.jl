# S72 r2 (discussion/specs/S72-draft-open-trace-dev.md §8): excess loss vs L-REF, logit Δ against a data-pair control,
# threshold clock with false-fire / detection rates, base-rate (PAD) control. s72.jl (r1, frozen) is included unchanged.
# usage: julia --project=. -t N experiments/s72_open/s72r2.jl stage1 | streams2 | all2 | run2 <TRM|CUM|FGT> <life> | judge2
include(joinpath(@__DIR__, "s72.jl"))   # r1 definitions; its main block does not run when included

const OUT2 = joinpath(@__DIR__, "out_r2"); mkpath(OUT2)
const SEEDS_ST1 = collect(1050:1067)    # stage 1: the 18 seeds of the dev lives (seen)
const SEEDS_ST2 = collect(1300:1317)    # stage 2: new seeds
const EPS_C = [0.0025, 0.005, 0.01]; const KAPPA_C = [1.5, 2.0, 3.0]; const THETA_C = [0.005, 0.01, 0.02, 0.04]
const FSTAR = 0.10; const DSTAR = 0.90; const CWIN = 10      # clock windows of 10 blocks x 50 examples
const BDD_OFF = LB + DLEN + NPROBE                           # B'' window starts right after the probe: [T+2905, T+4408]
const STAGE1_TOML = joinpath(OUT2, "stage1.toml")
const PRED2 = joinpath(@__DIR__, "predictions-r2-stage2.toml")

# ---- inputs: a Map, or PAD (receptor slots PAD in all frames = obs-ay; a table then has one key per action)
const PAD = nothing
const Enc = Union{Map,Nothing}
keyfor(st, s, a, m::Map) = r1key_map(st, s, a, m)
keyfor(st, s, a, ::Nothing) = 2 * 64 + a
function predict2(L::TabL, lf::Life, idx, m::Enc)
    out = Float64[]
    for t in idx
        si, s = lf.ex[t]; st = lf.streams[si]; a = st.act[s+1]
        rate = (L.n1[a] + 1) / (L.n[a] + 2); k = keyfor(st, s, a, m)
        push!(out, clip((L.rn1[k] + ALPHA_R1 * rate) / (L.rn[k] + ALPHA_R1)))
    end
    return out
end
function update2!(L::TabL, lf::Life, idx, m::Enc)
    for t in idx
        si, s = lf.ex[t]; st = lf.streams[si]; a = st.act[s+1]; y = st.Y[s+1]; k = keyfor(st, s, a, m)
        if L.lam < 1; L.n .*= L.lam; L.n1 .*= L.lam; L.rn .*= L.lam; L.rn1 .*= L.lam; end
        L.n[a] += 1; L.n1[a] += y; L.rn[k] += 1; L.rn1[k] += y
    end
end
function block_tok2(lf::Life, idx, m::Enc)
    tok = Matrix{UInt8}(undef, S, length(idx)); act = Int8[]; Y = Bool[]
    for (c, t) in enumerate(idx)
        si, s = lf.ex[t]; st = lf.streams[si]
        m === nothing ? encode!(tok, c, st, s, false) : encode_map!(tok, c, st, s, m)
        push!(act, st.act[s+1]); push!(Y, st.Y[s+1])
    end
    return tok, act, Y
end
predict2(L::TrmL, lf::Life, idx, m::Enc) = (b = block_tok2(lf, idx, m); clip.(predict_set(L.p, CFG_1X1, ExSet(-1, b[1], b[2], b[3], collect(idx))).p))
function update2!(L::TrmL, lf::Life, idx, m::Enc)
    tok, act, Y = block_tok2(lf, idx, m)
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
# prequential over 1-based example indices [a, b): predict the block, then update on it
function span!(L, lf::Life, a, b, m::Enc; update = true)
    ps = Float64[]; ys = Bool[]
    for t0 in a:BLK:b-1
        idx = t0:min(t0 + BLK - 1, b - 1)
        append!(ps, predict2(L, lf, idx, m))
        for t in idx; si, s = lf.ex[t]; push!(ys, lf.streams[si].Y[s+1]); end
        update && update2!(L, lf, idx, m)
    end
    return ps, ys
end
losses(ps, ys) = [loss(ps[k], ys[k]) for k in eachindex(ps)]
logit(p) = log(p / (1 - p))
dlogit(pa, pb) = mean(abs.(logit.(pa) .- logit.(pb)))

# ---- lives
function stream2(u)
    f = joinpath(u in SEEDS_ST1 ? OUT : OUT2, "stream_$u.jls")    # stage-1 streams are the r1 files (read only)
    isfile(f) && return deserialize(f)
    u in SEEDS_ST1 && error("stage-1 stream missing: $f")
    st = obs_stream(u, "stat"); serialize(f, st); return st
end
function make_life2(life, seeds, streams)
    sts = [streams[seeds[mod(life - 1 + k, 18) + 1]] for k in 0:11]
    ex = Tuple{Int,Int}[]
    for (i, st) in enumerate(sts), s in 0:NS-1
        st.isex[s+1] && push!(ex, (i, s))
    end
    N = BLK * (length(ex) ÷ BLK)
    return Life(sts, ex[1:N], N)
end
y0(lf, a, b) = count(t -> (x = lf.ex[t]; !lf.streams[x[1]].Y[x[2]+1]), a:b-1)

function run_life2(kind, life, stage)
    seeds = stage == 1 ? SEEDS_ST1 : SEEDS_ST2
    streams = Dict(u => stream2(u) for u in seeds)
    lf = make_life2(life, seeds, streams); maps, alts = life_maps(life)   # same maps as r1 (§8.0: field unchanged)
    N = lf.N; N >= TS[end] + BDD_OFF + LB || error("life too short: $N")
    REF = new_learner("CUM", life)
    rp, ry = span!(REF, lf, 1, N + 1, ID)          # L-REF reads the pre-map receptors: cumulative table on π0 throughout
    ℓref = losses(rp, ry)
    L = new_learner(kind, life); PADL = new_learner(kind, life)
    P = Float64[]; Yv = Bool[]
    bounds = vcat(0, TS, N)
    br = Dict{Int,Any}(); fresh = Dict{Int,Any}(); padc = Dict{Int,Any}(); keych = Dict{Int,Float64}()
    for seg in 1:5
        a, b = bounds[seg], bounds[seg+1]; m = maps[seg]
        if seg >= 2
            i = seg - 1
            ch = 0; tot = 0
            for t in a-RLEN+1:a
                si, s = lf.ex[t]; st = lf.streams[si]; ac = st.act[s+1]
                tot += 1; ch += r1key_map(st, s, ac, maps[seg-1]) != r1key_map(st, s, ac, m)
            end
            keych[i] = ch / tot
            h0 = statehash(L)
            A = deepcopy(L); B = deepcopy(L); Bdd = deepcopy(L); C1 = deepcopy(L); C2 = deepcopy(L)
            bA = span!(A, lf, a + 1, a + 1 + LB, m); bB = span!(B, lf, a + 1, a + 1 + LB, alts[i])
            bD = span!(Bdd, lf, a + 1 + BDD_OFF, a + 1 + BDD_OFF + LB, m)
            span!(C1, lf, a + 1, a + 1 + LB, m); span!(C2, lf, a + 1, a + 1 + LB, m)
            pr = a + 1 + LB + DLEN
            dpre = dlogit(span!(deepcopy(A), lf, pr, pr + NPROBE, ID; update = false)[1], span!(deepcopy(B), lf, pr, pr + NPROBE, ID; update = false)[1])
            for X in (A, B, Bdd, C1, C2); span!(X, lf, a + 1 + LB, pr, ID); end
            pA, pB, pD, pC1, pC2 = (span!(X, lf, pr, pr + NPROBE, ID; update = false)[1] for X in (A, B, Bdd, C1, C2))
            statehash(L) == h0 || error("branching changed the main state")
            br[i] = (dmap = dlogit(pA, pB), ddata = dlogit(pA, pD), dmap_preD = dpre, selfcheck = maximum(abs.(pC1 .- pC2)),
                     y0_A = y0(lf, a + 1, a + 1 + LB), y0_Bdd = y0(lf, a + 1 + BDD_OFF, a + 1 + BDD_OFF + LB),
                     loss_A = mloss(bA), loss_B = mloss(bB), loss_Bdd = mloss(bD))
            F = new_learner(kind, life)
            fresh[i] = losses(span!(F, lf, a + 1, a + 1 + CAP, m)...)
            Q = deepcopy(PADL)
            padc[i] = losses(span!(Q, lf, a + 1, a + 1 + CAP, m)...)
        end
        ps, ys = span!(L, lf, a + 1, b + 1, m)
        append!(P, ps); append!(Yv, ys)
        seg <= 4 && span!(PADL, lf, a + 1, b + 1, PAD)   # the PAD learner follows the main stream up to T_4
    end
    res = (kind = kind, life = life, stage = stage, N = N, P = P, Y = Yv, lref = ℓref, branches = br, fresh = fresh, pad = padc,
           keych = keych, maps = maps, alts = alts, seeds = [s.seed for s in lf.streams])
    serialize(joinpath(OUT2, "life$(stage)_$(kind)_$(life).jls"), res)
    return res
end

# ---- metrics (thresholds as arguments)
rint(N, i) = (nxt = i == 4 ? N : TS[i+1]; (nxt - RLEN + 1):nxt)    # R_i, i = 0..4 (R_0 ends at T_1)
function reach(x, lev, eps, from, to)    # first t in [from, to] whose trailing 250-mean <= lev + eps; offset from from - WIN
    for t in from:to; mean(x[t-WIN+1:t]) <= lev + eps && return t; end
    return nothing
end
function open1(res, eps)
    ℓ = losses(res.P, res.Y); e = ℓ .- res.lref; N = res.N
    o = []
    for i in 1:4
        T = TS[i]; nxt = i == 4 ? N : TS[i+1]
        a_i = mean(e[rint(N, i - 1)]); b_i = mean(e[rint(N, i)]); early = mean(e[T+1:T+WIN])
        meas = early >= a_i + 3eps; rec = b_i <= a_i + 2eps
        t = reach(e, b_i, eps, T + WIN, min(T + CAP, nxt)); s = t === nothing ? nothing : t - T
        ctl = Dict()
        for (nm, d) in (("fresh", res.fresh[i]), ("pad", res.pad[i]))
            ec = d .- res.lref[T+1:T+CAP]; lev = mean(ec[end-1499:end])
            ctl[nm] = reach(ec, lev, eps, WIN, CAP)
        end
        push!(o, (i = i, a = a_i, b = b_i, early = early, meas = meas, rec = rec, s = s, s_fresh = ctl["fresh"], s_pad = ctl["pad"],
                  raw_a = mean(ℓ[rint(N, i - 1)]), raw_early = mean(ℓ[T+1:T+WIN]), ref_a = mean(res.lref[rint(N, i - 1)]), ref_early = mean(res.lref[T+1:T+WIN]),
                  keych = res.keych[i]))
    end
    s1 = o[1].s
    viol = [x.s !== nothing && s1 !== nothing && x.s > 1.5 * s1 + 250 for x in o[2:end]]
    ok = all(x -> x.meas && x.rec && x.s !== nothing, o) && !any(viol)
    return (o = o, ok = ok, nviol = count(viol))
end
selfcheck!(res) = all(i -> res.branches[i].selfcheck == 0, 1:4) || error("OPEN-2 self-check failed: stage $(res.stage) life $(res.life) $(res.kind)")
function open2(res, kappa)
    selfcheck!(res)
    return all(i -> res.branches[i].dmap > kappa * res.branches[i].ddata, 1:4)
end
function clockblocks(e, a, b)     # mean excess loss per 50-example block over [a, b]
    [mean(e[t0:t0+CB-1]) for t0 in a:CB:b-CB+1]
end
fires(eb, theta) = any(x -> max(0.0, x - theta) > 0, eb)
function trace1(res, theta)
    e = losses(res.P, res.Y) .- res.lref; N = res.N
    nf = 0
    for i in 0:4
        r = rint(N, i); tail = (last(r) - RTAIL + 1):last(r)
        for w in 0:2
            a = first(tail) + w * CWIN * CB
            nf += fires(clockblocks(e, a, a + CWIN * CB - 1), theta)
        end
    end
    nd = count(i -> fires(clockblocks(e, TS[i] + 1, TS[i] + CWIN * CB), theta), 1:4)
    fr = nf / 15; dr = nd / 4
    return (false_rate = fr, det_rate = dr, ok = fr <= FSTAR && dr >= DSTAR)
end
function q1sd(res)
    ℓ = losses(res.P, res.Y); e = ℓ .- res.lref
    return (sd_l = std([mean(ℓ[rint(res.N, i)]) for i in 0:4]), sd_e = std([mean(e[rint(res.N, i)]) for i in 0:4]))
end
loadlife(stage, kind, life) = (f = joinpath(OUT2, "life$(stage)_$(kind)_$(life).jls"); isfile(f) || error("missing $f"); deserialize(f))
f5(x) = fmt(x)

function report_life!(io, res, eps, kappa, theta)
    j = eps === nothing ? nothing : open1(res, eps)
    println(io, "== stage $(res.stage) $(res.kind) life $(res.life): OPEN-1 $(j === nothing ? "not run" : j.ok) (eps $eps)  OPEN-2 $(kappa === nothing ? "not run" : open2(res, kappa)) (kappa $kappa)  TRACE-1 $(theta === nothing ? "not run" : trace1(res, theta).ok) (theta $theta)")
    for x in (j === nothing ? [] : j.o)
        println(io, "  OPEN-1 i=$(x.i) a_e=$(f5(x.a)) b_e=$(f5(x.b)) early_e=$(f5(x.early)) meas=$(x.meas) rec=$(x.rec) s=$(f5(x.s)) s_fresh=$(f5(x.s_fresh)) s_pad=$(f5(x.s_pad)) raw_a=$(f5(x.raw_a)) raw_early=$(f5(x.raw_early)) ref_a=$(f5(x.ref_a)) ref_early=$(f5(x.ref_early)) keych=$(f5(x.keych))")
    end
    for i in 1:4
        b = res.branches[i]
        println(io, "  OPEN-2 i=$i dmap=$(f5(b.dmap)) ddata=$(f5(b.ddata)) ratio=$(f5(b.ddata == 0 ? Inf : b.dmap / b.ddata)) dmap_preD=$(f5(b.dmap_preD)) selfcheck=$(b.selfcheck) y0 A/Bdd=$(b.y0_A)/$(b.y0_Bdd) loss A/B/Bdd=$(f5(b.loss_A))/$(f5(b.loss_B))/$(f5(b.loss_Bdd))")
    end
    for th in (res.stage == 1 ? THETA_C : theta === nothing ? Float64[] : [theta])   # stage 2 reports only the registered theta
        t = trace1(res, th); println(io, "  TRACE-1 theta=$th false_rate=$(f5(t.false_rate)) det_rate=$(f5(t.det_rate)) ok=$(t.ok)")
    end
    q = q1sd(res); println(io, "  Q1 sd_raw=$(f5(q.sd_l)) sd_e=$(f5(q.sd_e)) smaller_e=$(q.sd_e < q.sd_l)")
    return j
end

function stage1()
    tmapv(j -> run_life2(j[1], j[2], 1), [(k, l) for k in ("CUM", "FGT") for l in 1:NLIFE])
    R = Dict((k, l) => loadlife(1, k, l) for k in ("CUM", "FGT") for l in 1:NLIFE)
    foreach(selfcheck!, values(R))
    io = IOBuffer()
    # selection on L-FGT only (§8.6)
    epsok = [e for e in EPS_C if all(l -> open1(R[("FGT", l)], e).ok, 1:NLIFE)]
    kapok = [k for k in KAPPA_C if all(l -> open2(R[("FGT", l)], k), 1:NLIFE)]
    thok = [t for t in THETA_C if all(l -> trace1(R[("FGT", l)], t).ok, 1:NLIFE)]
    eps = isempty(epsok) ? nothing : minimum(epsok); kap = isempty(kapok) ? nothing : maximum(kapok); th = isempty(thok) ? nothing : minimum(thok)
    for k in ("FGT", "CUM"), l in 1:NLIFE
        report_life!(io, R[(k, l)], eps, kap, th)
    end
    for e in EPS_C, l in 1:NLIFE
        j = open1(R[("FGT", l)], e)
        println(io, "grid FGT eps=$e life $l: ok=$(j.ok) meas $(count(x -> x.meas, j.o))/4 rec $(count(x -> x.rec, j.o))/4 reached $(count(x -> x.s !== nothing, j.o))/4 viol $(j.nviol)")
    end
    for k in KAPPA_C; println(io, "grid FGT kappa=$k: lives ok $(count(l -> open2(R[("FGT", l)], k), 1:NLIFE))/4"); end
    for t in THETA_C; println(io, "grid FGT theta=$t: lives ok $(count(l -> trace1(R[("FGT", l)], t).ok, 1:NLIFE))/4"); end
    println(io, "negative clocks: constant false_rate=1.0 ok=$(1.0 <= FSTAR); zero det_rate=0.0 ok=$(0.0 >= DSTAR)")
    for k in ("FGT", "CUM")
        n = count(l -> (q = q1sd(R[(k, l)]); q.sd_e < q.sd_l), 1:NLIFE)
        println(io, "Q1 $k: lives with sd_e < sd_raw $n/4 -> $(n >= 3 ? "holds" : "miss")")
    end
    q1 = all(k -> count(l -> (q = q1sd(R[(k, l)]); q.sd_e < q.sd_l), 1:NLIFE) >= 3, ("FGT", "CUM"))
    println(io, "Q1 VERDICT: $(q1 ? "holds" : "miss")")
    sel(x) = x === nothing ? "\"not separable in stage 1\"" : string(x)
    println(io, "SELECTED eps=$(sel(eps)) kappa=$(sel(kap)) theta=$(sel(th))")
    s = String(take!(io)); print(s); write(joinpath(OUT2, "stage1.out"), s)
    write(STAGE1_TOML, "# selected in stage 1 by the §8.6 rules (L-FGT only)\neps = $(sel(eps))\nkappa = $(sel(kap))\ntheta = $(sel(th))\n")
end

function judge2()
    isfile(PRED2) || error("stage-2 predictions not frozen: $PRED2")
    th = TOML.parsefile(STAGE1_TOML); g(x) = x isa String ? nothing : Float64(x)
    eps, kap, theta = g(th["eps"]), g(th["kappa"]), g(th["theta"])
    R = Dict((k, l) => loadlife(2, k, l) for k in ("CUM", "FGT", "TRM") for l in 1:NLIFE)
    foreach(selfcheck!, values(R))   # every branch pair of every life, independent of kappa and of pass/fail (codex I-R P5)
    io = IOBuffer(); V = Dict{String,Any}()
    for k in ("CUM", "FGT", "TRM")
        for l in 1:NLIFE; report_life!(io, R[(k, l)], eps, kap, theta); end
        o1 = eps === nothing ? nothing : [open1(R[(k, l)], eps) for l in 1:NLIFE]
        xs = o1 === nothing ? [] : [x for j in o1 for x in j.o]
        v1 = o1 === nothing ? nothing : all(j -> j.ok, o1)
        v2 = kap === nothing ? nothing : all(l -> open2(R[(k, l)], kap), 1:NLIFE)
        v3 = theta === nothing ? nothing : all(l -> trace1(R[(k, l)], theta).ok, 1:NLIFE)
        V[k] = (v1 = v1, v2 = v2, v3 = v3, xs = xs, o1 = o1)
        if o1 !== nothing
            nm = count(x -> x.meas, xs)
            println(io, "OPEN-1 summary $k: switches $(length(xs)) unmeasurable $(length(xs) - nm) measurable-not-recovered $(count(x -> x.meas && !x.rec, xs)) not-reached $(count(x -> x.meas && x.s === nothing, xs)) lives-with-violation $(count(j -> j.nviol > 0, o1))/4 total-violations $(sum(j -> j.nviol, o1))")
        end
        println(io, "VERDICT $k: OPEN-1 $(something(v1, "not run"))  OPEN-2 $(something(v2, "not run"))  TRACE-1 $(something(v3, "not run"))")
    end
    # scoring (§8.5, §8.6 P23): any measured failure -> miss; all measured pass but something not run -> undecidable
    score(vs) = any(v -> v === false, vs) ? "miss" : any(v -> v === nothing, vs) ? "undecidable" : "holds"
    F = V["FGT"]; C = V["CUM"]; Tm = V["TRM"]
    println(io, "Q2 (FGT passes all three): $(score([F.v1, F.v2, F.v3]))")
    q3 = C.v1 === nothing ? "undecidable" : (C.v1 == false && (any(x -> x.meas && !x.rec, C.xs) || any(j -> j.nviol > 0, C.o1))) ? "holds" : "miss"
    println(io, "Q3 (CUM fails OPEN-1 via violation or measurable-not-recovered): $q3")
    println(io, "Q4 (TRM passes OPEN-1): $(score([Tm.v1]))   exploratory: OPEN-2 $(score([Tm.v2]))  TRACE-1 $(score([Tm.v3]))")
    if Tm.o1 === nothing
        println(io, "Q5: undecidable (OPEN-1 not run)")
    else
        rs = [x.s / x.s_pad for x in Tm.xs if x.s !== nothing && x.s_pad !== nothing]
        nn = count(x -> x.s === nothing || x.s_pad === nothing, Tm.xs)
        q5 = isempty(rs) ? "undecidable (0 switches where both reached)" : (0.7 <= median(rs) <= 1.3 ? "holds" : "miss")
        println(io, "Q5 (median s_main/s_pad in [0.7,1.3]): n=$(length(rs)) median=$(isempty(rs) ? "none" : f5(median(rs))) not-both-reached $nn -> $q5")
        fr = [x.s / x.s_fresh for x in Tm.xs if x.s !== nothing && x.s_fresh !== nothing]
        println(io, "report: TRM median s_main/s_fresh n=$(length(fr)) $(isempty(fr) ? "none" : f5(median(fr)))")
    end
    s = String(take!(io)); print(s); write(joinpath(OUT2, "judge2.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    mode = ARGS[1]
    if mode == "stage1"
        stage1()
    elseif mode == "streams2"
        tmapv(stream2, SEEDS_ST2); println("streams2 ok")
    elseif mode == "run2"
        t = @elapsed run_life2(ARGS[2], parse(Int, ARGS[3]), 2); println("done $(ARGS[2]) $(ARGS[3]) sec $(round(t))")
    elseif mode == "all2"
        isfile(PRED2) || error("freeze stage-2 predictions first")
        jobs = vcat([("TRM", l) for l in 1:NLIFE], [(k, l) for k in ("CUM", "FGT") for l in 1:NLIFE])
        tmapv(j -> (t = @elapsed run_life2(j[1], j[2], 2); println("done $(j[1]) $(j[2]) sec $(round(t))"); flush(stdout)), jobs)
    elseif mode == "judge2"
        judge2()
    end
end
