# S72 r3 (discussion/specs/S72-draft-open-trace-dev.md §9): held-out stratified probe (seeds 1500-1505) for OPEN-1,
# two-map held-out probe for OPEN-2, TRACE-1 judged on switches selected by the pre-update probe disruption d_i >= 3 eps.
# s72r2.jl (which includes r1 s72.jl) is included unchanged; its main block does not run when included.
# usage: julia --project=. -t N experiments/s72_open/s72r3.jl stage1 | all3 | run3 <TRM|CUM|FGT> <life> | judge3
include(joinpath(@__DIR__, "s72r2.jl"))

const OUT3 = joinpath(@__DIR__, "out_r3"); mkpath(OUT3)
const PROBE_SEEDS = collect(1500:1505); const PROBESEED = 730000; const NP0 = 200; const NP1 = 200
const CKSTEP = 50; const CKPRE = 500; const CKPOST = 6000
const STAGE1_TOML3 = joinpath(OUT3, "stage1.toml"); const W0_TOML = joinpath(OUT3, "w0.toml")
const PRED3 = joinpath(@__DIR__, "predictions-r3-stage2.toml")
al(t) = BLK * fld(t, BLK)                       # state after the last block that ends at or before t (§9.5)

# ---- the held-out probe: one fixed set per life, Y=0 examples first (1..NP0), then Y=1 (NP0+1..NP0+NP1)
function pstream(u)
    f = joinpath(OUT3, "pstream_$u.jls"); isfile(f) && return deserialize(f)
    st = obs_stream(u, "stat"); serialize(f, st); return st
end
function probe_life(life)
    sts = [pstream(u) for u in PROBE_SEEDS]
    z0 = Tuple{Int,Int}[]; z1 = Tuple{Int,Int}[]
    for (i, st) in enumerate(sts), s in 0:NS-1
        st.isex[s+1] || continue
        push!(st.Y[s+1] ? z1 : z0, (i, s))
    end
    length(z0) >= NP0 && length(z1) >= NP1 || error("probe pool too small: Y0 $(length(z0)) Y1 $(length(z1))")
    r = Mulberry(PROBESEED + life)
    function pick(v, k)   # partial Fisher-Yates without replacement
        v = copy(v)
        for j in 1:k; q = j + floor(Int, (length(v) - j + 1) * r()); v[j], v[q] = v[q], v[j]; end
        return v[1:k]
    end
    ex = vcat(pick(z0, NP0), pick(z1, NP1))
    return Life(sts, ex, length(ex))
end
probe(L, plf, m::Enc) = predict2(deepcopy(L), plf, 1:plf.N, m)

function main_points(N)
    pts = Set{Int}()
    for i in 1:4, o in -CKPRE:CKSTEP:CKPOST; push!(pts, al(TS[i] + o)); end
    for i in 1:4
        nxt = i == 4 ? N : TS[i+1]
        for k in 1:(RTAIL ÷ CKSTEP - 1); push!(pts, al(nxt - RTAIL + CKSTEP * k)); end   # R_i tail points, excluding T_{i+1} itself
    end
    return sort!(collect(pts))
end
const COFFS = collect(0:CKSTEP:CAP)   # control checkpoints (nominal offsets from T_i)

# run L over 1-based examples [a+1, b+1) with map m, pausing at aligned offsets to probe; returns Dict(offset => probe p)
function ctl_run!(L, lf, plf, a, m)
    out = Dict{Int,Vector{Float64}}(); cur = 0
    for o in unique(al.(COFFS))
        o > cur && (span!(L, lf, a + cur + 1, a + o + 1, m); cur = o)
        out[o] = probe(L, plf, m)
    end
    return out
end

function run_life3(kind, life, stage)
    seeds = stage == 1 ? SEEDS_ST1 : SEEDS_ST2
    streams = Dict(u => stream2(u) for u in seeds)
    lf = make_life2(life, seeds, streams); maps, alts = life_maps(life)
    plf = probe_life(life)
    N = lf.N; N >= TS[end] + BDD_OFF + LB && N >= TS[end] + CAP || error("life too short: $N")
    pts = main_points(N)
    REF = new_learner("CUM", life); L = new_learner(kind, life); L0 = new_learner(kind, life); PADL = new_learner(kind, life)
    P = Float64[]; Yv = Bool[]; P0 = Float64[]; ℓref = Float64[]
    pL = Dict{Int,Vector{Float64}}(); pR = Dict{Int,Vector{Float64}}(); pNew = Dict{Int,Vector{Float64}}()
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
            pNew[i] = probe(L, plf, m)                      # d_i: same pre-update state, new map (old map is pL[T_i])
            h0 = statehash(L)
            A = deepcopy(L); B = deepcopy(L); Bdd = deepcopy(L); C1 = deepcopy(L); C2 = deepcopy(L)
            bA = span!(A, lf, a + 1, a + 1 + LB, m); bB = span!(B, lf, a + 1, a + 1 + LB, alts[i])
            bD = span!(Bdd, lf, a + 1 + BDD_OFF, a + 1 + BDD_OFF + LB, m)
            span!(C1, lf, a + 1, a + 1 + LB, m); span!(C2, lf, a + 1, a + 1 + LB, m)
            two(X) = (probe(X, plf, m), probe(X, plf, alts[i]))   # the same 800 inputs: probe under π_i, then under π'_i
            preA, preB = two(A), two(B)
            pr = a + 1 + LB + DLEN
            for X in (A, B, Bdd, C1, C2); span!(X, lf, a + 1 + LB, pr, ID); end
            qA, qB, qD, qC1, qC2 = two(A), two(B), two(Bdd), two(C1), two(C2)
            statehash(L) == h0 || error("branching changed the main state")
            br[i] = (pA = qA, pB = qB, pD = qD, preA = preA, preB = preB,
                     selfcheck = max(maximum(abs.(qC1[1] .- qC2[1])), maximum(abs.(qC1[2] .- qC2[2]))),
                     y0_A = y0(lf, a + 1, a + 1 + LB), y0_Bdd = y0(lf, a + 1 + BDD_OFF, a + 1 + BDD_OFF + LB),
                     loss_A = mloss(bA), loss_B = mloss(bB), loss_Bdd = mloss(bD))
            fresh[i] = ctl_run!(new_learner(kind, life), lf, plf, a, m)
            padc[i] = ctl_run!(deepcopy(PADL), lf, plf, a, m)
        end
        cuts = vcat([t for t in pts if a < t < b], b); cur = a
        for c in cuts
            ps, ys = span!(L, lf, cur + 1, c + 1, m); append!(P, ps); append!(Yv, ys)
            append!(P0, span!(L0, lf, cur + 1, c + 1, m)[1])          # probe-free twin (§9.5 isolation)
            rp, ry = span!(REF, lf, cur + 1, c + 1, ID); append!(ℓref, losses(rp, ry))
            if c in pts
                pL[c] = probe(L, plf, m); pR[c] = probe(REF, plf, ID)
            end
            cur = c
        end
        seg <= 4 && !(b in pts) && error("switch $b is not a checkpoint")   # a_i needs the probe at T_i
        seg <= 4 && span!(PADL, lf, a + 1, b + 1, PAD)
    end
    P == P0 || error("isolation failed: probed main differs from probe-free twin ($kind life $life stage $stage)")
    res = (kind = kind, life = life, stage = stage, N = N, P = P, Y = Yv, lref = ℓref, pL = pL, pR = pR, pNew = pNew, pts = pts,
           branches = br, fresh = fresh, pad = padc, keych = keych, maps = maps, alts = alts,
           seeds = [s.seed for s in lf.streams], probe_ex = plf.ex)
    serialize(joinpath(OUT3, "life$(stage)_$(kind)_$(life).jls"), res)
    return res
end

# ---- metrics (w0 = Y=0 weight; thresholds as arguments)
wl(p, w0) = w0 * mean(loss(p[k], false) for k in 1:NP0) + (1 - w0) * mean(loss(p[k], true) for k in NP0+1:NP0+NP1)
wd(p, q, w0) = (d = abs.(logit.(p) .- logit.(q)); w0 * mean(d[1:NP0]) + (1 - w0) * mean(d[NP0+1:end]))
dtwo(x, y, w0) = (wd(x[1], y[1], w0) + wd(x[2], y[2], w0)) / 2
eP(res, t, w0) = wl(res.pL[t], w0) - wl(res.pR[t], w0)
dist(res, i, w0) = (wl(res.pNew[i], w0) - wl(res.pR[TS[i]], w0)) - eP(res, TS[i], w0)
tailpts(res, i) = (nxt = i == 4 ? res.N : TS[i+1]; [al(nxt - RTAIL + CKSTEP * k) for k in 1:(RTAIL ÷ CKSTEP - 1)])
function reach3(f, lev, eps, offs)       # first checkpoint with f(o) <= lev + eps; returns (o, previous checkpoint)
    prev = nothing
    for o in offs; f(o) <= lev + eps && return (o, prev); prev = o; end
    return (nothing, prev)
end
function ctlreach(d, res, T, eps, w0)
    ec(o) = wl(d[o], w0) - wl(res.pR[T+o], w0)
    lev = mean(ec(o) for o in unique(al.(4550:CKSTEP:CAP)))
    return reach3(ec, lev, eps, unique(al.(CKSTEP:CKSTEP:CAP)))[1]
end
function open1_3(res, eps, w0)
    o = []
    for i in 1:4
        T = TS[i]; a_i = eP(res, T, w0); d_i = dist(res, i, w0)
        early = eP(res, al(T + CKSTEP), w0); b_i = mean(eP(res, t, w0) for t in tailpts(res, i))
        meas = d_i >= 3eps; rec = b_i <= a_i + 2eps
        t, tp = reach3(t -> eP(res, t, w0), b_i, eps, unique(al.(T .+ (CKSTEP:CKSTEP:CKPOST))))
        s = t === nothing ? nothing : t - T; sp = tp === nothing ? nothing : tp - T
        push!(o, (i = i, a = a_i, d = d_i, early = early, b = b_i, meas = meas, rec = rec, s = s, s_prev = sp,
                  s_fresh = ctlreach(res.fresh[i], res, T, eps, w0), s_pad = ctlreach(res.pad[i], res, T, eps, w0), keych = res.keych[i]))
    end
    s1 = o[1].s
    viol = [x.s !== nothing && s1 !== nothing && x.s > 1.5 * s1 + 250 for x in o[2:end]]
    return (o = o, ok = all(x -> x.meas && x.rec && x.s !== nothing, o) && !any(viol), nviol = count(viol))
end
selfcheck3!(res) = all(i -> res.branches[i].selfcheck == 0, 1:4) || error("OPEN-2 self-check failed: stage $(res.stage) life $(res.life) $(res.kind)")
function open2_3(res, kappa, w0)
    selfcheck3!(res)
    return all(i -> (b = res.branches[i]; dtwo(b.pA, b.pB, w0) > kappa * dtwo(b.pA, b.pD, w0)), 1:4)
end
selset(res, eps, w0) = [i for i in 1:4 if dist(res, i, w0) >= 3eps]
function trace1_3(res, theta, S)
    t = trace1(res, theta)       # r2: false-fire rate (15 windows) and all-switch detection rate
    e = losses(res.P, res.Y) .- res.lref
    nd = count(i -> fires(clockblocks(e, TS[i] + 1, TS[i] + CWIN * CB), theta), S)
    dsel = isempty(S) ? nothing : nd / length(S)
    return (false_rate = t.false_rate, det_all = t.det_rate, nsel = length(S), ndet_sel = nd, det_sel = dsel,
            ok = dsel !== nothing && t.false_rate <= FSTAR && dsel >= DSTAR)
end
loadlife3(stage, kind, life) = (f = joinpath(OUT3, "life$(stage)_$(kind)_$(life).jls"); isfile(f) || error("missing $f"); deserialize(f))

strata(p) = (mean(loss(p[k], false) for k in 1:NP0), mean(loss(p[k], true) for k in NP0+1:NP0+NP1))
dstrata(p, q) = (d = abs.(logit.(p) .- logit.(q)); (mean(d[1:NP0]), mean(d[NP0+1:end])))
sf(x) = "$(f5(x[1]))/$(f5(x[2]))"
function report_life3!(io, res, w0, eps, kappa, theta; epsgrid = Float64[], thetagrid = Float64[])
    println(io, "== stage $(res.stage) $(res.kind) life $(res.life)")
    for i in 1:4   # probe losses by stratum (Y0/Y1): learner old map, learner new map, L-REF, at T_i; then at +48 (early)
        T = TS[i]
        println(io, "  PROBE i=$i strata Y0/Y1 at T: L_old=$(sf(strata(res.pL[T]))) L_new=$(sf(strata(res.pNew[i]))) REF=$(sf(strata(res.pR[T])))  early: L=$(sf(strata(res.pL[al(T + CKSTEP)]))) REF=$(sf(strata(res.pR[al(T + CKSTEP)])))")
    end
    for i in 1:4
        b = res.branches[i]
        println(io, "  OPEN-2 i=$i dmap=$(f5(dtwo(b.pA, b.pB, w0))) ddata=$(f5(dtwo(b.pA, b.pD, w0))) dmap_pi/alt=$(f5(wd(b.pA[1], b.pB[1], w0)))/$(f5(wd(b.pA[2], b.pB[2], w0))) ddata_pi/alt=$(f5(wd(b.pA[1], b.pD[1], w0)))/$(f5(wd(b.pA[2], b.pD[2], w0))) strata Y0/Y1 dmap_pi=$(sf(dstrata(b.pA[1], b.pB[1]))) dmap_alt=$(sf(dstrata(b.pA[2], b.pB[2]))) ddata_pi=$(sf(dstrata(b.pA[1], b.pD[1]))) ddata_alt=$(sf(dstrata(b.pA[2], b.pD[2]))) dmap_preD=$(f5(dtwo(b.preA, b.preB, w0))) selfcheck=$(b.selfcheck) y0 A/Bdd=$(b.y0_A)/$(b.y0_Bdd) loss A/B/Bdd=$(f5(b.loss_A))/$(f5(b.loss_B))/$(f5(b.loss_Bdd))")
    end
    for e in (isempty(epsgrid) ? (eps === nothing ? Float64[] : [eps]) : epsgrid)
        j = open1_3(res, e, w0)
        println(io, "  OPEN-1 eps=$e ok=$(j.ok) viol=$(j.nviol)")
        for x in j.o
            println(io, "    i=$(x.i) a=$(f5(x.a)) d=$(f5(x.d)) early=$(f5(x.early)) b=$(f5(x.b)) meas=$(x.meas) rec=$(x.rec) s=$(f5(x.s)) s_prev=$(f5(x.s_prev)) s_fresh=$(f5(x.s_fresh)) s_pad=$(f5(x.s_pad)) keych=$(f5(x.keych))")
        end
    end
    kappa === nothing || println(io, "  OPEN-2 kappa=$kappa ok=$(open2_3(res, kappa, w0))")
    if eps === nothing
        println(io, "  TRACE-1 not run (eps not selected)")
    else
        S = selset(res, eps, w0)
        for th in (isempty(thetagrid) ? (theta === nothing ? Float64[] : [theta]) : thetagrid)
            t = trace1_3(res, th, S)
            ds = t.nsel == 0 ? "not computable (0 selected switches)" : "$(t.ndet_sel)/$(t.nsel)"
            println(io, "  TRACE-1 theta=$th (sets at eps=$eps) false_rate=$(f5(t.false_rate)) det_all=$(f5(t.det_all)) det_sel=$ds ok=$(t.nsel == 0 ? "not computable" : t.ok)")
        end
    end
end

function stage1_3()
    jobs = [(k, l) for k in ("CUM", "FGT") for l in 1:NLIFE]
    foreach(pstream, PROBE_SEEDS)   # serial cache creation before threads (codex I-R P7)
    tmapv(j -> run_life3(j[1], j[2], 1), jobs)
    R = Dict(j => loadlife3(1, j...) for j in jobs)
    for j in jobs   # stage 1 only: the main stream must equal the r2 saved run bit for bit
        r2 = loadlife(1, j...); R[j].P == r2.P && R[j].lref == r2.lref || error("r3 main differs from r2 saved run: $j")
    end
    foreach(selfcheck3!, values(R))
    w0 = count(!, vcat([R[("FGT", l)].Y for l in 1:NLIFE]...)) / sum(l -> length(R[("FGT", l)].Y), 1:NLIFE)
    write(W0_TOML, "# pooled Y=0 rate of the stage-1 main streams (4 lives), written before any metric is computed (§9.5)\nw0 = $w0\n")
    w0 = TOML.parsefile(W0_TOML)["w0"]
    F(l) = R[("FGT", l)]
    epsok = [e for e in EPS_C if all(l -> open1_3(F(l), e, w0).ok, 1:NLIFE)]
    kapok = [k for k in KAPPA_C if all(l -> open2_3(F(l), k, w0), 1:NLIFE)]
    eps = isempty(epsok) ? nothing : minimum(epsok); kap = isempty(kapok) ? nothing : maximum(kapok)
    thnote = ""; th = nothing
    if eps === nothing
        thnote = "held: eps not selected"
    elseif any(l -> isempty(selset(F(l), eps, w0)), 1:NLIFE)
        thnote = "held: empty selected set"
    else
        thok = [t for t in THETA_C if all(l -> trace1_3(F(l), t, selset(F(l), eps, w0)).ok, 1:NLIFE)]
        th = isempty(thok) ? nothing : minimum(thok)
    end
    io = IOBuffer()
    println(io, "w0 = $(f5(w0))  isolation: probed main == probe-free twin == r2 saved run (all 8)")
    for k in ("FGT", "CUM"), l in 1:NLIFE
        report_life3!(io, R[(k, l)], w0, eps, kap, th; epsgrid = EPS_C, thetagrid = THETA_C)
    end
    for e in EPS_C, l in 1:NLIFE
        j = open1_3(F(l), e, w0)
        println(io, "grid FGT eps=$e life $l: ok=$(j.ok) meas $(count(x -> x.meas, j.o))/4 rec $(count(x -> x.rec, j.o))/4 reached $(count(x -> x.s !== nothing, j.o))/4 viol $(j.nviol)")
    end
    for k in KAPPA_C; println(io, "grid FGT kappa=$k: lives ok $(count(l -> open2_3(F(l), k, w0), 1:NLIFE))/4"); end
    if eps !== nothing
        for t in THETA_C
            println(io, "grid FGT theta=$t (sets at eps=$eps): lives ok $(count(l -> (S = selset(F(l), eps, w0); !isempty(S) && trace1_3(F(l), t, S).ok), 1:NLIFE))/4")
        end
    end
    sel(x) = x === nothing ? "\"not separable in stage 1\"" : string(x)
    thsel = th === nothing && thnote != "" ? "\"$thnote\"" : sel(th)
    q = eps !== nothing && kap !== nothing && th !== nothing
    println(io, "R3-Q1 (eps, kappa, theta all selectable for L-FGT): $(q ? "holds" : "miss")")
    println(io, "SELECTED eps=$(sel(eps)) kappa=$(sel(kap)) theta=$thsel")
    s = String(take!(io)); print(s); write(joinpath(OUT3, "stage1.out"), s)
    write(STAGE1_TOML3, "# selected in stage 1 by the §8.6 / §9.3 rules (L-FGT only)\nw0 = $w0\neps = $(sel(eps))\nkappa = $(sel(kap))\ntheta = $thsel\n")
end

function judge3()
    isfile(PRED3) || error("stage-2 predictions not frozen: $PRED3")
    th = TOML.parsefile(STAGE1_TOML3); g(x) = x isa String ? nothing : Float64(x)
    w0 = Float64(th["w0"]); eps, kap, theta = g(th["eps"]), g(th["kappa"]), g(th["theta"])
    R = Dict((k, l) => loadlife3(2, k, l) for k in ("CUM", "FGT", "TRM") for l in 1:NLIFE)
    foreach(selfcheck3!, values(R))
    io = IOBuffer(); V = Dict{String,Any}()
    println(io, "w0 = $(f5(w0)) (stage 1)  eps=$eps kappa=$kap theta=$theta  isolation: probed main == probe-free twin (all 12)")
    for k in ("CUM", "FGT", "TRM")
        for l in 1:NLIFE; report_life3!(io, R[(k, l)], w0, eps, kap, theta); end
        o1 = eps === nothing ? nothing : [open1_3(R[(k, l)], eps, w0) for l in 1:NLIFE]
        xs = o1 === nothing ? [] : [x for j in o1 for x in j.o]
        v1 = o1 === nothing ? nothing : all(j -> j.ok, o1)
        v2 = kap === nothing ? nothing : all(l -> open2_3(R[(k, l)], kap, w0), 1:NLIFE)
        v3 = (theta === nothing || eps === nothing) ? nothing : begin
            ts = [trace1_3(R[(k, l)], theta, selset(R[(k, l)], eps, w0)) for l in 1:NLIFE]
            println(io, "TRACE-1 summary $k: det_all per life $(join([f5(t.det_all) for t in ts], " ")) det_sel per life $(join(["$(t.ndet_sel)/$(t.nsel)" for t in ts], " ")) false per life $(join([f5(t.false_rate) for t in ts], " "))")
            any(t -> t.nsel == 0, ts) ? nothing : all(t -> t.ok, ts)
        end
        V[k] = (v1 = v1, v2 = v2, v3 = v3, xs = xs, o1 = o1)
        if o1 !== nothing
            nm = count(x -> x.meas, xs)
            println(io, "OPEN-1 summary $k: switches $(length(xs)) unmeasurable $(length(xs) - nm) measurable-not-recovered $(count(x -> x.meas && !x.rec, xs)) not-reached $(count(x -> x.meas && x.s === nothing, xs)) lives-with-violation $(count(j -> j.nviol > 0, o1))/4 total-violations $(sum(j -> j.nviol, o1))")
        end
        println(io, "VERDICT $k: OPEN-1 $(something(v1, "not run"))  OPEN-2 $(something(v2, "not run"))  TRACE-1 $(something(v3, "not run / not computable"))")
    end
    score(vs) = any(v -> v === false, vs) ? "miss" : any(v -> v === nothing, vs) ? "undecidable" : "holds"
    Fv = V["FGT"]; C = V["CUM"]; Tm = V["TRM"]
    println(io, "Q2 (FGT passes all three): $(score([Fv.v1, Fv.v2, Fv.v3]))")
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
    s = String(take!(io)); print(s); write(joinpath(OUT3, "judge3.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    mode = ARGS[1]
    if mode == "stage1"
        stage1_3()
    elseif mode == "run3"
        t = @elapsed run_life3(ARGS[2], parse(Int, ARGS[3]), parse(Int, get(ARGS, 4, "2"))); println("done $(ARGS[2]) $(ARGS[3]) sec $(round(t))")
    elseif mode == "all3"
        isfile(PRED3) || error("freeze stage-2 predictions first")
        foreach(pstream, PROBE_SEEDS); foreach(stream2, SEEDS_ST2)   # serial cache creation before threads (codex I-R P7)
        jobs = vcat([("TRM", l) for l in 1:NLIFE], [(k, l) for k in ("CUM", "FGT") for l in 1:NLIFE])
        tmapv(j -> (t = @elapsed run_life3(j[1], j[2], 2); println("done $(j[1]) $(j[2]) sec $(round(t))"); flush(stdout)), jobs)
    elseif mode == "judge3"
        judge3()
    end
end
