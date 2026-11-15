# S58 gates R1-R5 (discussion/specs/S58-bret-norm.md r3 §8), each with a negative control (a deliberate fault that must
# make the gate fail). Pilot windows 726-729, partners 766-769. Writes results-bret-gates.out / .json.
# Usage (from experiments/): julia --project=.. -t 8 check_bret.jl
include(joinpath(@__DIR__, "bret_grid.jl"))

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
recs(R) = (R.s, R.sread, R.nused, R.ntried, R.npaid, R.ded, R.short, R.bsize, R.alive)

function gates()
    res = Dict{String,Any}()
    okF, ref = freeze_ok()
    say("F: spec and predictions equal freeze 2 of freeze-bret-norm.txt: ", okF, "  ", ref)
    res["F"] = okF
    # ---------- R1: A-ret = core L2+SF, AB-free = core SFD, every step (TRACE: acts, costs, pools, world hash; LSTRACE: learning state) ----------
    c1 = [(u, per) for u in PILOT for per in (nothing, 1)]
    R1 = tmap(c1) do (u, per)
        px = per === nothing ? (;) : (PER = per,)
        o = merge(BASE, (SCHED = synth_sched(u, WP.P, WP.sigma, WP.L, WP.M), REPORT = true), TR, px)
        sf = body_org_run("ORG", u, o); sfd = body_org_run_sfd("ORG", u, o)
        ra, Ra = run_one("A-ret", "0", u; extra = merge(TR, px)); rf, Rf = run_one("AB-free", "0", u; from = 0, extra = merge(TR, px))
        # the arm as run in the experiment (A-ret raising to T0, then AB-free): equal to core L2+SF to T0
        re, Re = run_one("AB-free", "0", u; extra = merge(TR, px))
        pre = deq(sf["trace"][1:T0], re["trace"][1:T0]) && sf["lsHash"][1:T0] == re["lsHash"][1:T0] && !deq(sf, sub(re, sf))
        capst(R) = count(t -> R.capn[t+1] > R.capn[t], 1:STEPS-1)
        (key = "u$u PER=$(per === nothing ? "none" : per)", a = deq(sf, sub(ra, sf)), f = deq(sfd, sub(rf, sfd)),
         negA = deq(sf, sub(rf, sf)), negF = deq(sfd, sub(ra, sfd)),
         lastA = count(>(0), Ra.lastsg), lastF = count(>(0), Rf.lastsg), capA = capst(Ra), capF = capst(Rf), sfdDiff = !deq(sf, sfd),
         deathA = ra["death"], deathF = rf["death"], pre = pre)
    end
    for x in R1
        say("R1 ", rpad(x.key, 14), ": A-ret = core L2+SF ", x.a, ", AB-free = core SFD ", x.f, " | steps where the decay took the last sg: ", x.lastA, " / ", x.lastF,
            ", steps where the capacity acted: ", x.capA, " / ", x.capF, " | deaths ", x.deathA, " / ", x.deathF,
            " | AB-free from T0 = core L2+SF to T0 and differs after: ", x.pre,
            "   neg: AB-free = core L2+SF (must be false) ", x.negA, ", A-ret = core SFD (must be false) ", x.negF)
    end
    smpLast = sum(x.lastA + x.lastF for x in R1); smpCap = sum(x.capA + x.capF for x in R1)
    say("R1 sample: steps with the last sg removed by the decay ", smpLast, ", steps with the capacity acting ", smpCap,
        " (the world of S55 has no capacity PER; the runs with PER = 1 are added only for this gate)")
    say("R1 note: spec §1 raises every arm as A-ret to T0, and core's SFD uses the drive rule from step 0; so AB-free is compared",
        " with core SFD with the arm's rule from step 0 (gate only), and the experiment's AB-free (from T0) with core L2+SF to T0")
    res["R1"] = all(x -> x.a && x.f && x.pre && !x.negA && !x.negF, R1) && smpLast > 0 && smpCap > 0
    say("R1: ", res["R1"])
    # ---------- the gate runs: every arm and class in the pilot windows (partners first) ----------
    P = Dict{Tuple,Any}()
    pr = tmap([(u, c) for u in PILOT for c in CLASSES]) do (u, c); run_one("B-ret", c, u; seed = partner_of(u), extra = TR); end
    for (i, (u, c)) in enumerate([(u, c) for u in PILOT for c in CLASSES]); P[("partner", u, c)] = pr[i]; end
    jobs = [(arm, u, c) for arm in ARMS for u in PILOT for c in CLASSES]
    ar = tmap(jobs) do (arm, u, c); run_one(arm, c, u; partner = arm == "B-yoke" ? P[("partner", u, c)][2].s : nothing, extra = TR); end
    for (i, j) in enumerate(jobs); P[j] = ar[i]; end
    allR = [(string(k), v[1], v[2]) for (k, v) in P]
    # ---------- R2: the balance at every step ----------
    function r2(R)
        bad = 0; maxe = 0.0
        for t in 0:STEPS-1
            i = t + 1
            if R.arm in ("A-ret", "AB-free")
                ok = R.npaid[i] == 0 && R.ded[i] == 0.0 && R.short[i] == 0.0
            elseif R.arm in ("B-ret", "AB-ret")
                e = abs(R.ded[i] - KC * R.npaid[i]); maxe = max(maxe, e)
                ok = R.short[i] == 0.0 && R.clamp[i] == 0 && e <= TOL && (R.npaid[i] == 0 || R.alive[i])
            else
                e = abs(R.ded[i] + R.short[i] - KC * R.npaid[i]); maxe = max(maxe, e)
                ok = e <= TOL && R.short[i] >= 0.0 && (R.npaid[i] == 0 || R.alive[i])
            end
            ok || (bad += 1)
        end
        return bad, maxe
    end
    R2 = [(k, r2(R)...) for (k, _, R) in allR]
    nb2 = sum(x[2] for x in R2); me2 = maximum(x[3] for x in R2)
    shortC = sum(sum(R.short) for (k, _, R) in allR if R.arm in ("B-delay", "B-yoke")); paidAll = sum(sum(R.npaid) for (k, _, R) in allR)
    _, Rn2 = run_one("B-ret", "0", first(PILOT); brk = :r2)
    neg2 = r2(Rn2)
    say("R2: runs ", length(R2), ", steps failing the balance ", nb2, ", max |levied (+ shortfall) - KC x restored| ", me2,
        " (restored in all runs ", paidAll, ", control shortfall ", shortC, ")   neg: B-ret levying one KC too many, failing steps (must be > 0) ", neg2[1])
    res["R2"] = nb2 == 0 && neg2[1] > 0 && paidAll > 0
    say("R2: ", res["R2"])
    # ---------- R3: the s a control reads; delay 0 and the self-yoke equal B-ret at every step ----------
    function r3(R, partner)
        bad = 0; n = 0
        for t in T0:STEPS-1
            R.ran[t+1] || continue
            want = R.arm == "B-delay" ? (t < T0 + R.delta ? R.s[t+1] : R.s[t-R.delta+1]) : partner[t+1]
            n += 1; R.sread[t+1] == want || (bad += 1)
        end
        return bad, n
    end
    R3r = [(string(j), r3(P[j][2], j[1] == "B-yoke" ? P[("partner", j[2], j[3])][2].s : nothing)...) for j in jobs if j[1] in ("B-delay", "B-yoke")]
    nb3 = sum(x[2] for x in R3r); nn3 = sum(x[3] for x in R3r)
    _, Rn3 = run_one("B-delay", "0", first(PILOT); brk = :r3)
    neg3 = r3(Rn3, nothing)
    c3 = [(u, c) for u in PILOT for c in CLASSES]
    R3i = tmap(c3) do (u, c)
        rb, Rb = P[("B-ret", u, c)]
        r0, R0 = run_one("B-delay", c, u; delta = 0, extra = TR)
        ry, Ry = run_one("B-yoke", c, u; partner = Rb.s, extra = TR)
        r1, R1x = run_one("B-delay", c, u; delta = 1, extra = TR)
        same(r, R) = deq(rb, r) && deq(recs(Rb)[[1; 3:9]], recs(R)[[1; 3:9]]) && Rb.sread[T0+1:end] == R.sread[T0+1:end]
        (key = "u$u $c", d0 = same(r0, R0), sy = same(ry, Ry), neg = same(r1, R1x))
    end
    for x in R3i; say("R3 ", x.key, ": delay 0 = B-ret ", x.d0, ", self-yoke = B-ret ", x.sy, "   neg: delay 1 = B-ret (must be false) ", x.neg); end
    say("R3: steps where the read s differs from the record ", nb3, " of ", nn3, "   neg: delay reading t - 376, differing steps (must be > 0) ", neg3[1], " of ", neg3[2])
    res["R3"] = nb3 == 0 && nn3 > 0 && neg3[1] > 0 && all(x -> x.d0 && x.sy && !x.neg, R3i)
    say("R3: ", res["R3"])
    # ---------- R4: the perturbations as specified; runs of one arm and window equal across classes up to the head of tp ----------
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
            return (okB && okP && p.t == tp, "a: body places $(length(bd)), given $(round(p.given; digits = 5))")
        elseif R.cls == "b"
            p = R.pert; p === nothing && return (false, "none")
            c = R.pre.circuit
            kept = [k for k in eachindex(c.q) if c.q[k] >= 1 || c.sg[k] >= 1]
            cut = kept[mod(u, 2)+1:2:end]
            ok = p.kept == kept && p.cut == cut && all(k -> (k in cut ? p.q1[k] == 0 && p.s1[k] == 0 : p.q1[k] == p.q0[k] && p.s1[k] == p.s0[k]), eachindex(p.q0)) &&
                 p.q0 == c.q && p.s0 == c.sg && p.t == tp
            return (ok, "b: kept $(length(kept)), cut $(length(cut)) (start $(mod(u, 2)))")
        elseif R.cls == "c"
            f = sched_of(u, "c", tp); g = synth_table(u, WP.P, WP.sigma, WP.L, WP.M); h = table(u)
            ok = R.pert === nothing && h[1:SW_NS, :] == g && all(s -> all(k -> f(s, k) == (s >= tp - T0 ? h[s+151, k] : h[s+1, k]), 1:2), 0:SW_NS-1) &&
                 any(s -> f(s, 1) != g[s+1, 1] || f(s, 2) != g[s+1, 2], tp-T0:SW_NS-1)
            return (ok, "c: drive from world time $(tp - T0) read 150 ahead")
        else
            return (R.pert === nothing, "0: none")
        end
    end
    R4 = []
    for arm in ARMS, u in PILOT
        r0, R0 = P[(arm, u, "0")]
        pe = all(c -> prefix_eq(r0, R0, P[(arm, u, c)]...), PCLASSES)
        sp = [spec_ok(P[(arm, u, c)][2], u) for c in CLASSES]
        push!(R4, (key = "$arm u$u", pe = pe, sp = all(first, sp), info = join(last.(sp), "; ")))
    end
    for (k, (r, R)) in P
        k[1] == "partner" || continue
        r0, R0 = P[("partner", k[2], "0")]
        push!(R4, (key = "partner u$(k[2]) $(k[3])", pe = prefix_eq(r0, R0, r, R), sp = spec_ok(R, k[2])[1], info = ""))
    end
    for x in R4; isempty(x.info) || say("R4 ", rpad(x.key, 12), ": prefix to the head of tp equal across classes ", x.pe, ", perturbations as specified ", x.sp, "  (", x.info, ")"); end
    say("R4 partner runs: prefix equal and as specified in ", count(x -> x.pe && x.sp, filter(x -> startswith(x.key, "partner"), R4)), "/16")
    neg4 = Bool[]
    for c in ("a", "b")
        rn, Rn = run_one("B-ret", c, first(PILOT); brk = :r4, extra = TR)
        r0, R0 = P[("B-ret", first(PILOT), "0")]
        push!(neg4, prefix_eq(r0, R0, rn, Rn))
    end
    say("R4   neg: perturbing at tp - 1, prefix equal to class 0 (must be false) for a, b: ", neg4)
    res["R4"] = all(x -> x.pe && x.sp, R4) && !any(neg4)
    say("R4: ", res["R4"])
    # ---------- R5: B and the body unchanged between the head of the step and the levy, every arm and step ----------
    nb5 = sum(count(!, R.r5) for (_, _, R) in allR); nr5 = length(allR) * STEPS
    _, Rn5 = run_one("B-ret", "a", first(PILOT); brk = :r5)
    neg5 = count(!, Rn5.r5)
    say("R5: steps where B or the body changed between the head and the levy ", nb5, " of ", nr5, " (", length(allR), " runs)",
        "   neg: class-a cut moved between the head and the levy, changed steps (must be > 0) ", neg5)
    res["R5"] = nb5 == 0 && neg5 > 0
    say("R5: ", res["R5"])
    # ---------- facts used later (not gates) ----------
    for u in PILOT
        R = P[("B-ret", u, "0")][2]
        say("note u$u: tp ", tp_of(u), ", B-ret class 0 death ", P[("B-ret", u, "0")][1]["death"], ", restored T0..tp-1 ", sum(R.npaid[T0+1:R.tp]),
            " of used ", sum(R.nused[T0+1:R.tp]), ", mean s T0..tp-1 ", round(sum(R.s[T0+1:R.tp]) / (R.tp - T0); digits = 2))
    end
    summ = Dict(k => res[k] for k in ("F", "R1", "R2", "R3", "R4", "R5"))
    say("== summary ", JSON.json(summ))
    write(joinpath(EXP, "results-bret-gates.out"), join(GL, "\n") * "\n")
    write(joinpath(EXP, "results-bret-gates.json"), JSON.json(Dict("summary" => summ), 2))
end

gates()
