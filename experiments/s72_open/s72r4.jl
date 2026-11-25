# S72 r4 (discussion/specs/S72-draft-open-trace-dev.md §10): OPEN-1 on same-task age branches (world-side ρ*, fixed held-out
# training list from seeds 1506-1507), difficulty control, OPEN-2 as Δ_map > δ with a window-table gate, TRACE-1 as r3.
# s72r3.jl (which includes r2 and r1) is included unchanged; its main block does not run when included.
# usage: julia --project=. -t N experiments/s72_open/s72r4.jl stage1 | all4 | run4 <TRM|CUM|FGT|WIN> <life> [stage] | judge4
include(joinpath(@__DIR__, "s72r3.jl"))

const OUT4 = joinpath(@__DIR__, "out_r4"); mkpath(OUT4)
const HOLD_SEEDS = [1506, 1507]; const HOLDLEN = 6000; const RHOSEED = 720200; const WINLEN = DLEN
const DELTA_C = [0.01, 0.03, 0.1]
const STAGE1_TOML4 = joinpath(OUT4, "stage1.toml"); const PRED4 = joinpath(@__DIR__, "predictions-r4-stage2.toml")
const W0_R3 = joinpath(OUT3, "w0.toml")
const TABKINDS = ("CUM", "FGT", "WIN")

# ---- window table (negative control for OPEN-2): counts over exactly the last WINLEN examples, base rates included
mutable struct WinL; n::Vector{Float64}; n1::Vector{Float64}; rn::Vector{Float64}; rn1::Vector{Float64}; buf::Vector{Tuple{Int,Int,Bool}}; end
new_learner4(kind, life) = kind == "WIN" ? WinL(zeros(2), zeros(2), zeros(130), zeros(130), Tuple{Int,Int,Bool}[]) : new_learner(kind, life)
function predict2(L::WinL, lf::Life, idx, m::Enc)
    out = Float64[]
    for t in idx
        si, s = lf.ex[t]; st = lf.streams[si]; a = st.act[s+1]
        rate = (L.n1[a] + 1) / (L.n[a] + 2); k = keyfor(st, s, a, m)
        push!(out, clip((L.rn1[k] + ALPHA_R1 * rate) / (L.rn[k] + ALPHA_R1)))
    end
    return out
end
function update2!(L::WinL, lf::Life, idx, m::Enc)
    for t in idx
        si, s = lf.ex[t]; st = lf.streams[si]; a = st.act[s+1]; y = st.Y[s+1]; k = keyfor(st, s, a, m)
        push!(L.buf, (k, a, y)); L.n[a] += 1; L.n1[a] += y; L.rn[k] += 1; L.rn1[k] += y
        if length(L.buf) > WINLEN
            k0, a0, y0 = popfirst!(L.buf); L.n[a0] -= 1; L.n1[a0] -= y0; L.rn[k0] -= 1; L.rn1[k0] -= y0
        end
    end
end
statehash(L::WinL) = bytes2hex(sha256(reinterpret(UInt8, vcat(L.n, L.n1, L.rn, L.rn1))))

# ---- the fixed held-out training list and the world-side transform ρ*
function hold_life()
    sts = [pstream(u) for u in HOLD_SEEDS]   # same cache as the probe streams (out_r3/pstream_*.jls)
    ex = Tuple{Int,Int}[]
    for (i, st) in enumerate(sts), s in 0:NS-1; st.isex[s+1] && push!(ex, (i, s)); end
    length(ex) >= HOLDLEN || error("held-out list too short: $(length(ex))")
    return Life(sts, ex[1:HOLDLEN], HOLDLEN)
end
worldside(pi::Map, rho::Map) = compose(pi, rho)   # x -> π(ρ*(x)): ρ* acts on the world receptors first (§10.6)
function draw_rhostar(life, maps, alts)
    r = Mulberry(RHOSEED + life)
    while true
        rho = draw_rho(r)
        all(i -> !(worldside(maps[i], rho) in maps) && !(worldside(maps[i], rho) in alts), 1:4) && return rho
    end
end

function run_life4(kind, life, stage)
    seeds = stage == 1 ? SEEDS_ST1 : SEEDS_ST2
    streams = Dict(u => stream2(u) for u in seeds)
    lf = make_life2(life, seeds, streams); maps, alts = life_maps(life)
    plf = probe_life(life); hl = hold_life(); rho = draw_rhostar(life, maps, alts)
    task = [worldside(maps[i], rho) for i in 1:4]     # age i: π_{i-1} ∘ ρ*
    N = lf.N; N >= TS[end] + BDD_OFF + LB && N >= TS[end] + CAP || error("life too short: $N")
    pts = main_points(N)
    REF = new_learner("CUM", life); L = new_learner4(kind, life); L0 = new_learner4(kind, life); PADL = new_learner4(kind, life)
    P = Float64[]; Yv = Bool[]; P0 = Float64[]; ℓref = Float64[]
    pL = Dict{Int,Vector{Float64}}(); pR = Dict{Int,Vector{Float64}}(); pNew = Dict{Int,Vector{Float64}}()
    bounds = vcat(0, TS, N)
    br = Dict{Int,Any}(); fresh = Dict{Int,Any}(); padc = Dict{Int,Any}(); keych = Dict{Int,Float64}()
    age = Dict{Int,Any}(); ageref = Dict{Int,Any}(); agenew0 = Dict{Int,Vector{Float64}}()
    # difficulty control (§10.2): fresh learner on main [1, T_1] under π_{i-1}, then the same task; REF side shared by all ages
    cref = new_learner("CUM", life); span!(cref, lf, 1, TS[1] + 1, ID); ctlref = ctl_run!(cref, hl, plf, 0, ID)
    ctl = Dict{Int,Any}(); ctlold0 = Dict{Int,Vector{Float64}}()
    for i in 1:4
        C = new_learner4(kind, life); span!(C, lf, 1, TS[1] + 1, maps[i])
        ctlold0[i] = probe(C, plf, maps[i]); ctl[i] = ctl_run!(C, hl, plf, 0, task[i])
    end
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
            pNew[i] = probe(L, plf, m)
            h0 = statehash(L); hr = statehash(REF)
            # same-task age branch (§10.1): the old-map probe at this state is pL[T_i]
            G = deepcopy(L); agenew0[i] = probe(G, plf, task[i]); age[i] = ctl_run!(G, hl, plf, 0, task[i])
            ageref[i] = ctl_run!(deepcopy(REF), hl, plf, 0, ID)
            A = deepcopy(L); B = deepcopy(L); Bdd = deepcopy(L); C1 = deepcopy(L); C2 = deepcopy(L)
            bA = span!(A, lf, a + 1, a + 1 + LB, m); bB = span!(B, lf, a + 1, a + 1 + LB, alts[i])
            bD = span!(Bdd, lf, a + 1 + BDD_OFF, a + 1 + BDD_OFF + LB, m)
            span!(C1, lf, a + 1, a + 1 + LB, m); span!(C2, lf, a + 1, a + 1 + LB, m)
            two(X) = (probe(X, plf, m), probe(X, plf, alts[i]))
            preA, preB = two(A), two(B)
            pr = a + 1 + LB + DLEN
            for X in (A, B, Bdd, C1, C2); span!(X, lf, a + 1 + LB, pr, ID); end
            qA, qB, qD, qC1, qC2 = two(A), two(B), two(Bdd), two(C1), two(C2)
            statehash(L) == h0 && statehash(REF) == hr || error("branching changed the main state")
            br[i] = (pA = qA, pB = qB, pD = qD, preA = preA, preB = preB,
                     selfcheck = max(maximum(abs.(qC1[1] .- qC2[1])), maximum(abs.(qC1[2] .- qC2[2]))),
                     y0_A = y0(lf, a + 1, a + 1 + LB), y0_Bdd = y0(lf, a + 1 + BDD_OFF, a + 1 + BDD_OFF + LB),
                     loss_A = mloss(bA), loss_B = mloss(bB), loss_Bdd = mloss(bD))
            fresh[i] = ctl_run!(new_learner4(kind, life), lf, plf, a, m)
            padc[i] = ctl_run!(deepcopy(PADL), lf, plf, a, m)
        end
        cuts = vcat([t for t in pts if a < t < b], b); cur = a
        for c in cuts
            ps, ys = span!(L, lf, cur + 1, c + 1, m); append!(P, ps); append!(Yv, ys)
            append!(P0, span!(L0, lf, cur + 1, c + 1, m)[1])
            rp, ry = span!(REF, lf, cur + 1, c + 1, ID); append!(ℓref, losses(rp, ry))
            if c in pts
                pL[c] = probe(L, plf, m); pR[c] = probe(REF, plf, ID)
            end
            cur = c
        end
        seg <= 4 && !(b in pts) && error("switch $b is not a checkpoint")
        seg <= 4 && span!(PADL, lf, a + 1, b + 1, PAD)
    end
    P == P0 || error("isolation failed: probed main differs from probe-free twin ($kind life $life stage $stage)")
    res = (kind = kind, life = life, stage = stage, N = N, P = P, Y = Yv, lref = ℓref, pL = pL, pR = pR, pNew = pNew, pts = pts,
           branches = br, fresh = fresh, pad = padc, keych = keych, maps = maps, alts = alts, rho = rho, task = task,
           age = age, ageref = ageref, agenew0 = agenew0, ctl = ctl, ctlold0 = ctlold0, ctlref = ctlref,
           seeds = [s.seed for s in lf.streams], probe_ex = plf.ex)
    serialize(joinpath(OUT4, "life$(stage)_$(kind)_$(life).jls"), res)
    return res
end

# ---- metrics
const AOFFS = unique(al.(CKSTEP:CKSTEP:CAP)); const LEVOFFS = unique(al.(4550:CKSTEP:CAP))
ebr(d, dref, o, w0) = wl(d[o], w0) - wl(dref[o], w0)
function open1_4(res, eps, w0)
    o = []
    for i in 1:4
        T = TS[i]; a_i = eP(res, T, w0)
        d_i = (wl(res.agenew0[i], w0) - wl(res.ageref[i][0], w0)) - a_i
        e(x) = ebr(res.age[i], res.ageref[i], x, w0)
        b_i = mean(e(x) for x in LEVOFFS); early = e(AOFFS[1])
        meas = d_i >= 3eps; rec = b_i <= a_i + 2eps
        s, sp = reach3(e, b_i, eps, AOFFS)
        ec(x) = ebr(res.ctl[i], res.ctlref, x, w0)
        sc = reach3(ec, mean(ec(x) for x in LEVOFFS), eps, AOFFS)[1]
        push!(o, (i = i, a = a_i, d = d_i, early = early, b = b_i, meas = meas, rec = rec, s = s, s_prev = sp, s_ctl = sc,
                  ctlseries = [wl(res.ctl[i][x], w0) for x in sort!(collect(keys(res.ctl[i])))]))
    end
    s1 = o[1].s
    viol = [x.s !== nothing && s1 !== nothing && x.s > 1.5 * s1 + 250 for x in o[2:end]]
    c1 = o[1].s_ctl
    ctlok = all(x -> x.s_ctl !== nothing, o) && all(x -> x.s_ctl <= 1.5 * c1 + 250 && c1 <= 1.5 * x.s_ctl + 250, o)
    return (o = o, ok = all(x -> x.meas && x.rec && x.s !== nothing, o) && !any(viol), nviol = count(viol), ctlok = ctlok)
end
function ctlgate!(res, eps, w0)    # tables: the difficulty control is bit-identical across ages (§10.2, P4.3)
    res.kind == "TRM" && return true
    j = open1_4(res, eps, w0)
    all(x -> x.ctlseries == j.o[1].ctlseries && x.s_ctl == j.o[1].s_ctl, j.o) ||
        error("difficulty-control equivariance gate failed: stage $(res.stage) $(res.kind) life $(res.life)")
    return true
end
dmap4(res, i, w0) = (b = res.branches[i]; dtwo(b.pA, b.pB, w0))
open2_4(res, delta, w0) = (selfcheck3!(res); all(i -> dmap4(res, i, w0) > delta, 1:4))
wingate!(res) = all(i -> (b = res.branches[i]; b.pA[1] == b.pB[1] && b.pA[2] == b.pB[2]), 1:4) ||
    error("window-table gate failed (Δ_map ≠ 0 after D): stage $(res.stage) life $(res.life)")
loadlife4(stage, kind, life) = (f = joinpath(OUT4, "life$(stage)_$(kind)_$(life).jls"); isfile(f) || error("missing $f"); deserialize(f))

function report_life4!(io, res, w0, eps, delta, theta; epsgrid = Float64[], thetagrid = Float64[])
    println(io, "== stage $(res.stage) $(res.kind) life $(res.life)  rho*=$(res.rho.perm)")
    for e in (isempty(epsgrid) ? (eps === nothing ? Float64[] : [eps]) : epsgrid)
        j = open1_4(res, e, w0)
        println(io, "  OPEN-1(age branch) eps=$e ok=$(j.ok) viol=$(j.nviol) difficulty-ctl-ok=$(j.ctlok)")
        for x in j.o
            println(io, "    i=$(x.i) a=$(f5(x.a)) d=$(f5(x.d)) early=$(f5(x.early)) b=$(f5(x.b)) meas=$(x.meas) rec=$(x.rec) s=$(f5(x.s)) s_prev=$(f5(x.s_prev)) s_ctl=$(f5(x.s_ctl))")
        end
        o3 = open1_3(res, e, w0)    # side indicator: r3 main-stream reach
        println(io, "    side(main stream, r3): s=$(join([f5(x.s) for x in o3.o], ",")) s_fresh=$(join([f5(x.s_fresh) for x in o3.o], ",")) s_pad=$(join([f5(x.s_pad) for x in o3.o], ",")) d_main=$(join([f5(x.d) for x in o3.o], ",")) log(s/s_fresh)=$(join([x.s === nothing || x.s_fresh === nothing ? "not computable" : f5(log(x.s / x.s_fresh)) for x in o3.o], ","))")
    end
    for i in 1:4
        b = res.branches[i]
        println(io, "  OPEN-2 i=$i dmap=$(f5(dmap4(res, i, w0))) dmap_pi/alt=$(f5(wd(b.pA[1], b.pB[1], w0)))/$(f5(wd(b.pA[2], b.pB[2], w0))) ddata(report)=$(f5(dtwo(b.pA, b.pD, w0))) dmap_preD=$(f5(dtwo(b.preA, b.preB, w0))) selfcheck=$(b.selfcheck)")
    end
    delta === nothing || println(io, "  OPEN-2 delta=$delta ok=$(open2_4(res, delta, w0))")
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

function stage1_4()
    jobs = [(k, l) for k in TABKINDS for l in 1:NLIFE]
    foreach(pstream, vcat(PROBE_SEEDS, HOLD_SEEDS))
    tmapv(j -> run_life4(j[1], j[2], 1), jobs)
    R = Dict(j => loadlife4(1, j...) for j in jobs)
    for j in jobs
        j[1] == "WIN" && continue
        r2 = loadlife(1, j...); R[j].P == r2.P && R[j].lref == r2.lref || error("r4 main differs from r2 saved run: $j")
    end
    w0 = TOML.parsefile(W0_R3)["w0"]
    foreach(selfcheck3!, values(R)); foreach(l -> wingate!(R[("WIN", l)]), 1:NLIFE)
    for j in jobs, e in EPS_C; ctlgate!(R[j], e, w0); end
    F(l) = R[("FGT", l)]
    epsok = [e for e in EPS_C if all(l -> open1_4(F(l), e, w0).ok, 1:NLIFE)]
    dok = [d for d in DELTA_C if all(l -> open2_4(F(l), d, w0), 1:NLIFE)]
    eps = isempty(epsok) ? nothing : minimum(epsok); del = isempty(dok) ? nothing : maximum(dok)
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
    println(io, "w0 = $(f5(w0)) (r3 stage 1)  gates: isolation (12 runs, CUM/FGT == r2 saved), self-check 0, window-table Δ_map == 0 bitwise (4 lives), difficulty control bit-identical across ages (tables, all eps)")
    for k in ("FGT", "CUM"), l in 1:NLIFE
        report_life4!(io, R[(k, l)], w0, eps, del, th; epsgrid = EPS_C, thetagrid = THETA_C)
    end
    for e in EPS_C, l in 1:NLIFE
        j = open1_4(F(l), e, w0)
        println(io, "grid FGT eps=$e life $l: ok=$(j.ok) meas $(count(x -> x.meas, j.o))/4 rec $(count(x -> x.rec, j.o))/4 reached $(count(x -> x.s !== nothing, j.o))/4 viol $(j.nviol)")
    end
    for d in DELTA_C; println(io, "grid FGT delta=$d: lives ok $(count(l -> open2_4(F(l), d, w0), 1:NLIFE))/4"); end
    if eps !== nothing
        for t in THETA_C
            println(io, "grid FGT theta=$t (sets at eps=$eps): lives ok $(count(l -> (S = selset(F(l), eps, w0); !isempty(S) && trace1_3(F(l), t, S).ok), 1:NLIFE))/4")
        end
    end
    sel(x) = x === nothing ? "\"not separable in stage 1\"" : string(x)
    thsel = th === nothing && thnote != "" ? "\"$thnote\"" : sel(th)
    q = eps !== nothing && del !== nothing && th !== nothing
    println(io, "R4-Q1 (eps, delta, theta all selectable for L-FGT): $(q ? "holds" : "miss")")
    println(io, "SELECTED eps=$(sel(eps)) delta=$(sel(del)) theta=$thsel")
    s = String(take!(io)); print(s); write(joinpath(OUT4, "stage1.out"), s)
    write(STAGE1_TOML4, "# selected in stage 1 by the §8.6 / §9.3 / §10.3 rules (L-FGT only)\nw0 = $w0\neps = $(sel(eps))\ndelta = $(sel(del))\ntheta = $thsel\n")
end

function judge4()
    isfile(PRED4) || error("stage-2 predictions not frozen: $PRED4")
    th = TOML.parsefile(STAGE1_TOML4); g(x) = x isa String ? nothing : Float64(x)
    w0 = Float64(th["w0"]); eps, del, theta = g(th["eps"]), g(th["delta"]), g(th["theta"])
    kinds = ("CUM", "FGT", "TRM", "WIN")
    R = Dict((k, l) => loadlife4(2, k, l) for k in kinds for l in 1:NLIFE)
    foreach(selfcheck3!, values(R)); foreach(l -> wingate!(R[("WIN", l)]), 1:NLIFE)
    eps === nothing || foreach(r -> ctlgate!(r, eps, w0), values(R))
    io = IOBuffer(); V = Dict{String,Any}()
    println(io, "w0 = $(f5(w0))  eps=$eps delta=$del theta=$theta  gates passed (isolation, self-check, window table, table difficulty control)")
    for k in ("CUM", "FGT", "TRM")
        for l in 1:NLIFE; report_life4!(io, R[(k, l)], w0, eps, del, theta); end
        o1 = eps === nothing ? nothing : [open1_4(R[(k, l)], eps, w0) for l in 1:NLIFE]
        v1 = if o1 === nothing
            nothing
        else
            usable = k == "TRM" ? [j for j in o1 if j.ctlok] : o1    # TRM: lives where the difficulty control fails are undecided (§10.2)
            k == "TRM" && println(io, "TRM OPEN-1 per life: $(join(["life $l: " * (o1[l].ctlok ? (o1[l].ok ? "pass" : "fail") : "undecided (difficulty control failed)") for l in 1:NLIFE], "; "))  -> decided lives $(length(usable))/4")
            isempty(usable) ? nothing : all(j -> j.ok, usable)
        end
        v2 = del === nothing ? nothing : all(l -> open2_4(R[(k, l)], del, w0), 1:NLIFE)
        v3 = (theta === nothing || eps === nothing) ? nothing : begin
            ts = [trace1_3(R[(k, l)], theta, selset(R[(k, l)], eps, w0)) for l in 1:NLIFE]
            println(io, "TRACE-1 summary $k: det_all $(join([f5(t.det_all) for t in ts], " ")) det_sel $(join(["$(t.ndet_sel)/$(t.nsel)" for t in ts], " ")) false $(join([f5(t.false_rate) for t in ts], " "))")
            any(t -> t.nsel == 0, ts) ? nothing : all(t -> t.ok, ts)
        end
        xs = o1 === nothing ? [] : [x for j in o1 for x in j.o]
        if o1 !== nothing
            nm = count(x -> x.meas, xs)
            println(io, "OPEN-1 summary $k: age branches $(length(xs)) unmeasurable $(length(xs) - nm) measurable-not-recovered $(count(x -> x.meas && !x.rec, xs)) not-reached $(count(x -> x.meas && x.s === nothing, xs)) lives-with-violation $(count(j -> j.nviol > 0, o1))/4")
        end
        V[k] = (v1 = v1, v2 = v2, v3 = v3, o1 = o1, xs = xs)
        println(io, "VERDICT $k: OPEN-1 $(something(v1, "not run / undecided"))  OPEN-2 $(something(v2, "not run"))  TRACE-1 $(something(v3, "not run / not computable"))")
    end
    score(vs) = any(v -> v === false, vs) ? "miss" : any(v -> v === nothing, vs) ? "undecidable" : "holds"
    Fv = V["FGT"]; C = V["CUM"]; Tm = V["TRM"]
    println(io, "Q2 (FGT passes all three): $(score([Fv.v1, Fv.v2, Fv.v3]))")
    q3 = C.v1 === nothing ? "undecidable" : (C.v1 == false && (any(x -> x.meas && !x.rec, C.xs) || any(j -> j.nviol > 0, C.o1))) ? "holds" : "miss"
    println(io, "Q3 (CUM fails OPEN-1 via violation or measurable-not-recovered): $q3")
    nd = Tm.o1 === nothing ? 0 : count(j -> j.ctlok, Tm.o1)
    println(io, "Q4 (TRM passes OPEN-1): $(score([Tm.v1])) [scope: decided lives $nd/4; holds only covers those lives]   exploratory: OPEN-2 $(score([Tm.v2]))  TRACE-1 $(score([Tm.v3]))")
    if eps === nothing
        println(io, "Q5: undecidable (eps not selected)")
    else
        xs3 = [x for l in 1:NLIFE for x in open1_3(R[("TRM", l)], eps, w0).o]
        rs = [x.s / x.s_pad for x in xs3 if x.s !== nothing && x.s_pad !== nothing]
        nn = count(x -> x.s === nothing || x.s_pad === nothing, xs3)
        q5 = isempty(rs) ? "undecidable (0 switches where both reached)" : (0.7 <= median(rs) <= 1.3 ? "holds" : "miss")
        println(io, "Q5 (main stream: median s_main/s_pad in [0.7,1.3]): n=$(length(rs)) median=$(isempty(rs) ? "none" : f5(median(rs))) not-both-reached $nn -> $q5")
    end
    s = String(take!(io)); print(s); write(joinpath(OUT4, "judge4.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    mode = ARGS[1]
    if mode == "stage1"
        stage1_4()
    elseif mode == "run4"
        t = @elapsed run_life4(ARGS[2], parse(Int, ARGS[3]), parse(Int, get(ARGS, 4, "2"))); println("done $(ARGS[2]) $(ARGS[3]) sec $(round(t))")
    elseif mode == "all4"
        isfile(PRED4) || error("freeze stage-2 predictions first")
        foreach(pstream, vcat(PROBE_SEEDS, HOLD_SEEDS)); foreach(stream2, SEEDS_ST2)
        jobs = vcat([("TRM", l) for l in 1:NLIFE], [(k, l) for k in TABKINDS for l in 1:NLIFE])
        tmapv(j -> (t = @elapsed run_life4(j[1], j[2], 2); println("done $(j[1]) $(j[2]) sec $(round(t))"); flush(stdout)), jobs)
    elseif mode == "judge4"
        judge4()
    end
end
