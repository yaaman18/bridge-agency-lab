# S59 gates R1-R5 (discussion/specs/S59-bret2-norm.md r3 §5 and S58 r3 §8), each with a negative control. Windows 726-729
# of S58 (partners 766-769); the S59 windows are not used here. Writes results-bret2-gates.out / .json.
# Usage (from experiments/): julia --project=.. -t 8 check_bret2.jl
include(joinpath(@__DIR__, "bret2_grid.jl"))

function deq(a, b)
    (a isa AbstractDict && b isa AbstractDict) && return Set(keys(a)) == Set(keys(b)) && all(deq(a[k], b[k]) for k in keys(a))
    typeof(a) == typeof(b) || return false
    if a isa AbstractArray
        return size(a) == size(b) && all(deq(a[i], b[i]) for i in eachindex(a))
    elseif a isa Tuple || a isa NamedTuple
        return length(a) == length(b) && all(deq(a[i], b[i]) for i in 1:length(a))
    elseif a === nothing || a isa Number || a isa AbstractString || a isa Symbol || a isa Char || a isa AbstractSet
        return isequal(a, b)
    elseif a isa Function
        return a === b
    else
        return all(deq(getfield(a, f), getfield(b, f)) for f in fieldnames(typeof(a)))
    end
end
sub(r, ref) = Dict(k => r[k] for k in keys(ref) if haskey(r, k))
const TR = (TRACE = true, LSTRACE = true)
const TOL = 1e-14
recs(R) = (R.s, R.sread, R.nused, R.ncand, R.npaid, R.ded, R.short, R.bsize, R.alive)

# ---------- R1 (ii): hand-computed cases ----------
function hand_cases(judgedf, candf, payf)
    ok = Dict{String,Bool}()
    t = 500; now = t + 1; F = FORGETN
    # window edges: used at t - F (candidate), t - F - 1 (not), t only (not: lastUse is updated after the judgment)
    lastC = fill(now - F, 3); sg = [1, 1, 1]; lu = [t - F, t - F - 1, -10^9]
    j = judgedf(3, falses(3), lastC, now)
    ok["window: t-F in, t-F-1 out, t-only out"] = j == [1, 2, 3] && candf(j, sg, lu, t) == [1]
    # confirmed at the step: not judged, not a candidate, no levy
    j = judgedf(3, BitVector([true, false, false]), lastC, now)
    ok["confirmed edge: not judged, no candidate"] = j == [2, 3] && candf(j, sg, [t - 1, t - 1, t - 1], t) == [2, 3]
    # sg = 0 is not a candidate; sg = 1 is
    j = judgedf(2, falses(2), fill(now - 2F, 2), now)
    ok["sg 0 out, sg 1 in"] = candf(j, [0, 1], [t - 5, t - 5], t) == [2]
    # age not a multiple of F, or below F: not judged
    ok["age 99, 101, 150 not judged; 200 judged"] = judgedf(4, falses(4), [now - 99, now - 101, now - 150, now - 200], now) == [4]
    # after a restoration at now (lastC = now) the next judgment is exactly F steps later
    nxt = [n for n in now+1:now+2F if !isempty(judgedf(1, falses(1), [now], n))]
    ok["next judgment exactly F later"] = nxt == [now + F, now + 2F]
    # two candidates, s = 1: B2-ret restores the one at the start t mod 2; B2-free restores both; A none
    ok["two candidates s=1 (t even -> first)"] = payf([3, 7], 500, 1, :B2) == [3]
    ok["two candidates s=1 (t odd -> second)"] = payf([3, 7], 501, 1, :B2) == [7]
    ok["two candidates B2-free both"] = payf([3, 7], 500, 0, :B2free) == [3, 7]
    ok["A-ret none"] = payf([3, 7], 500, 5, :A) == Int[]
    ok["s larger than candidates (t = 502: start 502 mod 3 = 1)"] = payf([3, 7, 9], 502, 10, :B2) == [7, 9, 3]
    return ok
end
# b2_select!'s update of the use record: an edge used at t is not a candidate at t, and lastUse becomes t
function select_case()
    b = newborn(false); ne = length(b.edges)
    k = findfirst(e -> b.kind[e[2]] == 'M', b.edges); m = b.edges[k][2]
    st = init(b); st.lastC = fill(0, ne); st.sg[k] = 1
    r = BRet(); r.t = 500; r.mode = :B2; r.allow = 5; r.lastUse = fill(-10^9, ne)
    drove = falses(ne); drove[k] = true
    st.lastC[k] = 501 - FORGETN
    b2_select!(r, b, drove, [m], falses(ne), st, 501, ne)
    return k in r.used && !(k in r.cand) && r.lastUse[k] == 500
end
# the circuit step itself on a made state: two core edges with sg = 1 judged at now = 200, used at step 150
function step_case(mode, allow, t)
    b = newborn(false); ne = length(b.edges); st = init(b)
    st.t = t; now = t + 1
    st.lastC = fill(now - 1, ne); st.q .= 0
    ks = [k for (k, e) in enumerate(b.edges) if b.kind[e[1]] == 'C' && b.kind[e[2]] == 'C'][1:2]
    for k in ks; st.sg[k] = 1; st.lastC[k] = now - FORGETN; end
    r = BRet(); r.t = t; r.mode = mode; r.allow = allow; r.lastUse = fill(-10^9, ne); r.lastUse[ks] .= t - 50
    step_bret2!(st, b, [0.0, 0.0, 0.0]; noise = Mulberry(1), contrast = :bin3, idle_first = true, core_gate = true, sed_fade = true, ret = r)
    return (ks = ks, cand = r.cand, paid = r.paid, sg = st.sg[ks], lc = st.lastC[ks], now = now)
end

function gates()
    res = Dict{String,Any}()
    okF, ref = freeze_ok()
    say("F: spec and predictions equal freeze 2 of freeze-bret2-norm.txt: ", okF, "  ", ref)
    res["F"] = okF
    # ---------- R1 (i): A-ret = core L2+SF; B2-free / B2-ret with every use erased = A-ret ----------
    c1 = [(u, per) for u in GATEW for per in (nothing, 1)]
    R1 = tmap(c1) do (u, per)
        local px, o, sf, ra, rf0, Rf0, rb0, Rb0, rf, Rf
        px = per === nothing ? (;) : (PER = per,)
        o = merge(BASE, (SCHED = synth_sched(u, WP.P, WP.sigma, WP.L, WP.M), REPORT = true), TR, px)
        sf = body_org_run("ORG", u, o)
        ra, _ = run_one("A-ret", "0", u; extra = merge(TR, px))
        rf0, Rf0 = run_one("B2-free", "0", u; brk = :nouse, extra = merge(TR, px))
        rb0, Rb0 = run_one("B2-ret", "0", u; brk = :nouse, extra = merge(TR, px))
        rf, Rf = run_one("B2-free", "0", u; extra = merge(TR, px))
        (key = "u$u PER=$(per === nothing ? "none" : per)", a = deq(sf, sub(ra, sf)), f0 = deq(sf, sub(rf0, sf)) && sum(Rf0.ncand) == 0,
         b0 = deq(sf, sub(rb0, sf)) && sum(Rb0.ncand) == 0, neg = deq(sf, sub(rf, sf)), nc = sum(Rf.ncand), last = count(>(0), Rf.lastsg),
         cap = count(t -> Rf.capn[t+1] > Rf.capn[t], 1:STEPS-1))
    end
    for x in R1
        say("R1(i) ", rpad(x.key, 14), ": A-ret = core L2+SF ", x.a, ", B2-free without uses = A-ret ", x.f0, ", B2-ret without uses = A-ret ", x.b0,
            " | B2-free candidates ", x.nc, ", steps with the last sg removed ", x.last, ", capacity steps ", x.cap, "   neg: B2-free with uses = core L2+SF (must be false) ", x.neg)
    end
    r1i = all(x -> x.a && x.f0 && x.b0 && !x.neg, R1) && sum(x.last for x in R1) > 0 && sum(x.cap for x in R1) > 0
    # ---------- R1 (ii): hand-computed cases ----------
    H = hand_cases(b2_judged, b2_cand, b2_pay)
    for (k, v) in sort(collect(H)); say("R1(ii) hand: ", k, ": ", v); end
    badcand(j, sg, lu, t) = [k for k in j if sg[k] >= 1 && lu[k] < t && t - lu[k] <= FORGETN + 1]   # fault: window one step too long
    Hn = hand_cases(b2_judged, badcand, b2_pay)
    say("R1(ii) neg: window [t-F-1, t) passes the window case (must be false): ", Hn["window: t-F in, t-F-1 out, t-only out"])
    sc = select_case()
    say("R1(ii) hand: an edge used at t is not a candidate at t and its use is recorded at t: ", sc)
    s1 = step_case(:B2, 1, 199); s2 = step_case(:B2, 1, 200); sf = step_case(:B2free, 0, 199); sa = step_case(:A, 0, 199)
    st_ok = s1.cand == s1.ks && s1.paid == [s1.ks[2]] && s1.sg == [0, 1] && s1.lc == [s1.now - FORGETN, s1.now] &&
            s2.paid == [s2.ks[1]] && s2.sg == [1, 0] && sf.paid == sf.ks && sf.sg == [1, 1] && sf.lc == [sf.now, sf.now] && sa.paid == Int[] && sa.sg == [0, 0]
    say("R1(ii) circuit step on a made state (two sg=1 core edges judged, used 50 steps before): B2-ret s=1 t=199 restores the second ", s1.paid, " sg ", s1.sg,
        ", t=200 the first ", s2.paid, " sg ", s2.sg, ", B2-free both sg ", sf.sg, ", A-ret none sg ", sa.sg, " -> ", st_ok)
    # run-level replay of the rule from the logged uses (all gate runs below), and the capacity case
    # ---------- the gate runs ----------
    P = Dict{Tuple,Any}()
    pj = [(u, c) for u in GATEW for c in CLASSES]
    pr = tmap(pj) do (u, c); run_one("B2-ret", c, u; seed = partner_of(u), log = true, extra = TR); end
    for (i, x) in enumerate(pj); P[("partner", x...)] = pr[i]; end
    jobs = [(arm, u, c) for arm in ARMS for u in GATEW for c in CLASSES]
    ar = tmap(jobs) do (arm, u, c); run_one(arm, c, u; partner = arm == "B2-yoke" ? P[("partner", u, c)][2].s : nothing, log = true, extra = TR); end
    for (i, j) in enumerate(jobs); P[j] = ar[i]; end
    # forced shortfall (gate only): a yoke reading s = 10^6 restores every candidate; and the PER = 1 capacity case
    fj = [(u, per) for u in GATEW for per in (nothing, 1)]
    fr = tmap(fj) do (u, per)
        run_one("B2-yoke", "0", u; partner = fill(10^6, STEPS), log = true, extra = merge(TR, per === nothing ? (;) : (PER = per,)))
    end
    cj = collect(GATEW)
    cr = tmap(cj) do u; run_one("B2-ret", "0", u; log = true, extra = merge(TR, (PER = 1,))); end
    allR = vcat([(string(k), v[1], v[2]) for (k, v) in P], [("forced u$(fj[i][1]) PER=$(fj[i][2])", fr[i]...) for i in eachindex(fj)],
                [("PER1 B2-ret u$(cj[i])", cr[i]...) for i in eachindex(cj)])
    function replay(R)
        R.log === nothing && return (0, 0)
        lu = Dict{Int,Int}(); bad = 0; n = 0
        for x in R.log
            t = x.t; now = t + 1
            cand = [k for (i, k) in enumerate(x.judged) if x.sgBefore[i] >= 1 && get(lu, k, -10^9) < t && t - get(lu, k, -10^9) <= FORGETN]
            want = x.mode == :A ? Int[] : x.mode == :B2free ? cand : (nc = length(cand); [cand[mod(t + j, nc)+1] for j in 0:nc-1][1:min(max(x.allow, 0), nc)])
            ok = cand == x.cand && want == x.paid
            for (i, k) in enumerate(x.judged)
                if k in x.paid
                    ok = ok && x.sgAfter[i] == x.sgBefore[i] && x.lcAfter[i] == now
                else
                    ok = ok && x.sgAfter[i] == max(x.sgBefore[i] - 1, 0) && x.lcAfter[i] != now
                end
            end
            n += length(x.judged); ok || (bad += 1)
            for k in x.used; lu[k] = t; end
        end
        return (bad, n)
    end
    rp = [(k, replay(R)...) for (k, _, R) in allR]
    rpBad = sum(x[2] for x in rp); rpN = sum(x[3] for x in rp)
    nPaidAll = sum(sum(R.npaid) for (_, _, R) in allR)
    say("R1(ii) replay from the logged uses over ", length(allR), " runs: judgments ", rpN, ", restored ", nPaidAll, ", steps disagreeing ", rpBad)
    capev = 0; capok = true
    for (k, _, R) in allR
        R.log === nothing && continue
        for x in R.log
            (x.mode == :B2 && !isempty(x.paid)) || continue
            if any(!, x.keptPaid)
                capev += 1
                capok = capok && abs(R.ded[x.t+1] + R.short[x.t+1] - COST * length(x.paid)) <= TOL
            end
        end
    end
    say("R1(ii) capacity right after a paid restoration removes the edge: events ", capev, ", levy kept (not cancelled) in all: ", capok)
    res["R1"] = r1i && all(values(H)) && !Hn["window: t-F in, t-F-1 out, t-only out"] && sc && st_ok && rpBad == 0 && rpN > 0 && nPaidAll > 0 && capev > 0 && capok
    say("R1: ", res["R1"])
    # ---------- R2 ----------
    function r2(R)
        bad = 0; maxe = 0.0; first = nothing
        for t in 0:STEPS-1
            i = t + 1
            if R.arm in ("A-ret", "B2-free")
                ok = R.ded[i] == 0.0 && R.short[i] == 0.0
            elseif R.arm == "B2-ret"
                e = abs(R.ded[i] - COST * R.npaid[i]); maxe = max(maxe, e)
                ok = R.short[i] <= TOL && e <= TOL && (R.npaid[i] == 0 || R.alive[i])
            else
                e = abs(R.ded[i] + R.short[i] - COST * R.npaid[i]); maxe = max(maxe, e)
                ok = e <= TOL && R.short[i] >= -TOL   # the per-place amount b0 - max(b0 - d, THETA) can exceed d by rounding (1e-16)
            end
            ok = ok && R.broke[i] == 0
            if !ok
                bad += 1; first === nothing && (first = (t = t, ded = R.ded[i], short = R.short[i], npaid = R.npaid[i], broke = R.broke[i], alive = R.alive[i]))
            end
        end
        return bad, maxe, first
    end
    R2 = [(k, r2(R)...) for (k, _, R) in allR]
    nb2 = sum(x[2] for x in R2); me2 = maximum(x[3] for x in R2)
    for x in R2; x[2] > 0 && say("R2 failing run ", x[1], ": ", x[2], " steps, first ", x[4]); end
    shC = sum(sum(R.short) for (k, _, R) in allR if R.arm in ("B2-delay", "B2-yoke")); shN = sum(sum(R.short) for (k, _, R) in allR if R.arm in ("B2-delay", "B2-yoke") && !startswith(k, "forced"))
    shSteps = sum(count(>(1e-12), R.short) for (k, _, R) in allR if R.arm in ("B2-delay", "B2-yoke"))
    _, Rn2 = run_one("B2-ret", "0", first(GATEW); brk = :r2)
    neg2 = r2(Rn2)
    _, Rnf = run_one("B2-yoke", "0", first(GATEW); partner = fill(10^6, STEPS), brk = :nofloor)
    negf = sum(Rnf.broke)
    say("R2: runs ", length(R2), ", steps failing (balance or a place newly below the threshold) ", nb2, ", max |levied (+ shortfall) - KC F x restored| ", me2,
        "; control shortfall ", round(shC / KC; digits = 3), " KC in ", shSteps, " steps (of which without the forced yoke ", round(shN / KC; digits = 3), " KC)")
    say("R2   neg: B2-ret levying one more, failing steps (must be > 0) ", neg2[1], "; forced yoke with S58's levy to 0, places newly below the threshold (must be > 0) ", negf)
    res["R2"] = nb2 == 0 && neg2[1] > 0 && negf > 0 && shC > 0
    say("R2: ", res["R2"])
    # ---------- R3 ----------
    function r3(R, partner)
        bad = 0; n = 0
        for t in T0:STEPS-1
            R.ran[t+1] || continue
            want = R.arm == "B2-delay" ? (t < T0 + R.delta ? R.s[t+1] : R.s[t-R.delta+1]) : partner[t+1]
            n += 1; R.sread[t+1] == want || (bad += 1)
        end
        return bad, n
    end
    R3r = [(string(j), r3(P[j][2], j[1] == "B2-yoke" ? P[("partner", j[2], j[3])][2].s : nothing)...) for j in jobs if j[1] in ("B2-delay", "B2-yoke")]
    nb3 = sum(x[2] for x in R3r); nn3 = sum(x[3] for x in R3r)
    _, Rn3 = run_one("B2-delay", "0", first(GATEW); brk = :r3)
    neg3 = r3(Rn3, nothing)
    c3 = [(u, c) for u in GATEW for c in CLASSES]
    R3i = tmap(c3) do (u, c)
        local rb, Rb, r0, R0, ry, Ry, r1, R1x, same
        rb, Rb = P[("B2-ret", u, c)]
        r0, R0 = run_one("B2-delay", c, u; delta = 0, extra = TR)
        ry, Ry = run_one("B2-yoke", c, u; partner = Rb.s, extra = TR)
        r1, R1x = run_one("B2-delay", c, u; delta = 1, extra = TR)
        same(r, R) = deq(rb, r) && deq(recs(Rb)[[1; 3:9]], recs(R)[[1; 3:9]]) && Rb.sread[T0+1:end] == R.sread[T0+1:end]
        (key = "u$u $c", d0 = same(r0, R0), sy = same(ry, Ry), neg = same(r1, R1x), np = sum(Rb.npaid))
    end
    say("R3: delay 0 = B2-ret in ", count(x -> x.d0, R3i), "/16, self-yoke = B2-ret in ", count(x -> x.sy, R3i), "/16 (restorations in these B2-ret runs ", sum(x.np for x in R3i),
        ")   neg: delay 1 = B2-ret (must be 0) in ", count(x -> x.neg, R3i), "/16")
    say("R3: steps where the read s differs from the record ", nb3, " of ", nn3, "   neg: delay reading t - 376, differing steps (must be > 0) ", neg3[1], " of ", neg3[2])
    res["R3"] = nb3 == 0 && nn3 > 0 && neg3[1] > 0 && all(x -> x.d0 && x.sy && !x.neg, R3i)
    say("R3: ", res["R3"])
    # ---------- R4 ----------
    function prefix_eq(ra, Ra, rb, Rb)
        tp = Ra.tp
        deq(ra["trace"][1:tp], rb["trace"][1:tp]) && ra["lsHash"][1:tp] == rb["lsHash"][1:tp] && deq(Ra.pre, Rb.pre) &&
            all(x -> x[1][1:tp] == x[2][1:tp], zip(recs(Ra), recs(Rb)))
    end
    function spec_ok(R, u)
        tp = R.tp
        R.pre === nothing && return (false, "no state at tp")
        R.pre.alive || return (R.pert === nothing, "dead at tp")
        if R.cls == "a"
            p = R.pert; p === nothing && return (false, "none")
            bd = [i for i in eachindex(R.pre.w.C) if R.pre.w.C[i] != 0]
            okB = p.body == bd && all(i -> (i in bd ? p.B1[i] == p.B0[i] - p.B0[i] / 2 : p.B1[i] == p.B0[i]), eachindex(p.B0)) && p.B0 == R.pre.w.B
            okP = p.res1 == p.res0 + p.given && p.given == sum(p.B0[i] / 2 for i in bd)
            return (okB && okP && p.t == tp, "a")
        elseif R.cls == "b"
            p = R.pert; p === nothing && return (false, "none")
            c = R.pre.circuit
            kept = [k for k in eachindex(c.q) if c.q[k] >= 1 || c.sg[k] >= 1]; cut = kept[mod(u, 2)+1:2:end]
            ok = p.kept == kept && p.cut == cut && all(k -> (k in cut ? p.q1[k] == 0 && p.s1[k] == 0 : p.q1[k] == p.q0[k] && p.s1[k] == p.s0[k]), eachindex(p.q0)) &&
                 p.q0 == c.q && p.s0 == c.sg && p.t == tp
            return (ok, "b")
        elseif R.cls == "c"
            f = sched_of(u, "c", tp); g = synth_table(u, WP.P, WP.sigma, WP.L, WP.M); h = table(u)
            ok = R.pert === nothing && h[1:SW_NS, :] == g && all(s -> all(k -> f(s, k) == (s >= tp - T0 ? h[s+151, k] : h[s+1, k]), 1:2), 0:SW_NS-1) &&
                 any(s -> f(s, 1) != g[s+1, 1] || f(s, 2) != g[s+1, 2], tp-T0:SW_NS-1)
            return (ok, "c")
        else
            return (R.pert === nothing, "0")
        end
    end
    R4 = []
    for arm in vcat(collect(ARMS), ["partner"]), u in GATEW
        key0 = arm == "partner" ? ("partner", u, "0") : (arm, u, "0")
        r0, R0 = P[key0]
        kk(c) = arm == "partner" ? ("partner", u, c) : (arm, u, c)
        pe = all(c -> prefix_eq(r0, R0, P[kk(c)]...), PCLASSES)
        sp = [spec_ok(P[kk(c)][2], u) for c in CLASSES]
        push!(R4, (key = "$arm u$u", pe = pe, sp = all(first, sp), dead = !P[kk("0")][2].pre.alive))
    end
    say("R4: prefix to the head of tp equal across classes in ", count(x -> x.pe, R4), "/", length(R4), ", perturbations as specified in ", count(x -> x.sp, R4), "/", length(R4),
        " (dead at tp: ", join([x.key for x in R4 if x.dead], ", "), ")")
    neg4 = Bool[]
    for c in ("a", "b")
        rn, Rn = run_one("B2-ret", c, first(GATEW); brk = :r4, extra = TR)
        r0, R0 = P[("B2-ret", first(GATEW), "0")]
        push!(neg4, prefix_eq(r0, R0, rn, Rn))
    end
    say("R4   neg: perturbing at tp - 1, prefix equal to class 0 (must be false) for a, b: ", neg4)
    res["R4"] = all(x -> x.pe && x.sp, R4) && !any(neg4)
    say("R4: ", res["R4"])
    # ---------- R5 ----------
    nb5 = sum(count(!, R.r5) for (_, _, R) in allR); nr5 = length(allR) * STEPS
    _, Rn5 = run_one("B2-ret", "a", first(GATEW); brk = :r5)
    neg5 = count(!, Rn5.r5)
    say("R5: steps where B or the body changed between the head and the levy ", nb5, " of ", nr5, " (", length(allR), " runs)",
        "   neg: class-a cut moved between the head and the levy, changed steps (must be > 0) ", neg5)
    res["R5"] = nb5 == 0 && neg5 > 0
    say("R5: ", res["R5"])
    for u in GATEW
        x = summary(P[("B2-ret", u, "0")]...)["pre"]
        say("note u$u (S58 window, gate only): tp ", tp_of(u), ", B2-ret T0..tp-1 candidates ", x["ncand"], ", paid ", x["npaid"], ", unpaid ", x["unpaid"])
    end
    summ = Dict(k => res[k] for k in ("F", "R1", "R2", "R3", "R4", "R5"))
    say("== summary ", JSON.json(summ))
    write(joinpath(EXP, "results-bret2-gates.out"), join(GL, "\n") * "\n")
    write(joinpath(EXP, "results-bret2-gates.json"), JSON.json(Dict("summary" => summ), 2))
end

gates()
