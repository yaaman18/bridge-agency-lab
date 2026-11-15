# S58 gates R3 and R4 re-checked (codex I-R: in check_bret.jl the threaded closures of R3 shared the outer r0, R0 with R4).
# Same judging expressions and negative controls as check_bret.jl; every variable of a threaded closure is local.
# check_bret.jl (frozen) is not changed. Windows 726-729, partners 766-769. Appends to results-bret-gates-recheck.out the
# R3 / R4 lines and their comparison with the R3 / R4 lines of results-bret-gates.out.
# Usage (from experiments/): julia --project=.. -t 1 check_bret_recheck.jl ; julia --project=.. -t 8 check_bret_recheck.jl
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
const TR = (TRACE = true, LSTRACE = true)
recs(R) = (R.s, R.sread, R.nused, R.ntried, R.npaid, R.ded, R.short, R.bsize, R.alive)

function gate_runs()
    P = Dict{Tuple,Any}()
    pj = [(u, c) for u in PILOT for c in CLASSES]
    pr = tmap(pj) do (u, c); run_one("B-ret", c, u; seed = partner_of(u), extra = TR); end
    for (i, x) in enumerate(pj); P[("partner", x...)] = pr[i]; end
    jobs = [(arm, u, c) for arm in ARMS for u in PILOT for c in CLASSES]
    ar = tmap(jobs) do (arm, u, c); run_one(arm, c, u; partner = arm == "B-yoke" ? P[("partner", u, c)][2].s : nothing, extra = TR); end
    for (i, j) in enumerate(jobs); P[j] = ar[i]; end
    return P, jobs
end
function r3(R, partner)
    bad = 0; n = 0
    for t in T0:STEPS-1
        R.ran[t+1] || continue
        want = R.arm == "B-delay" ? (t < T0 + R.delta ? R.s[t+1] : R.s[t-R.delta+1]) : partner[t+1]
        n += 1; R.sread[t+1] == want || (bad += 1)
    end
    return bad, n
end
function r3_identity(P, u, c)
    local rb, Rb, r0, R0, ry, Ry, r1, R1x
    rb, Rb = P[("B-ret", u, c)]
    r0, R0 = run_one("B-delay", c, u; delta = 0, extra = TR)
    ry, Ry = run_one("B-yoke", c, u; partner = Rb.s, extra = TR)
    r1, R1x = run_one("B-delay", c, u; delta = 1, extra = TR)
    same(r, R) = deq(rb, r) && deq(recs(Rb)[[1; 3:9]], recs(R)[[1; 3:9]]) && Rb.sread[T0+1:end] == R.sread[T0+1:end]
    return (key = "u$u $c", d0 = same(r0, R0), sy = same(ry, Ry), neg = same(r1, R1x))
end
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

function recheck()
    lines = String[]; out(x...) = (s = string(x...); println(s); push!(lines, s))
    P, jobs = gate_runs()
    # R3
    R3r = [(string(j), r3(P[j][2], j[1] == "B-yoke" ? P[("partner", j[2], j[3])][2].s : nothing)...) for j in jobs if j[1] in ("B-delay", "B-yoke")]
    nb3 = sum(x[2] for x in R3r); nn3 = sum(x[3] for x in R3r)
    _, Rn3 = run_one("B-delay", "0", first(PILOT); brk = :r3)
    neg3 = r3(Rn3, nothing)
    c3 = [(u, c) for u in PILOT for c in CLASSES]
    R3i = tmap(c3) do (u, c); r3_identity(P, u, c); end
    for x in R3i; out("R3 ", x.key, ": delay 0 = B-ret ", x.d0, ", self-yoke = B-ret ", x.sy, "   neg: delay 1 = B-ret (must be false) ", x.neg); end
    out("R3: steps where the read s differs from the record ", nb3, " of ", nn3, "   neg: delay reading t - 376, differing steps (must be > 0) ", neg3[1], " of ", neg3[2])
    r3ok = nb3 == 0 && nn3 > 0 && neg3[1] > 0 && all(x -> x.d0 && x.sy && !x.neg, R3i)
    out("R3: ", r3ok)
    # R4
    R4 = []
    for arm in ARMS, u in PILOT
        local r0, R0
        r0, R0 = P[(arm, u, "0")]
        pe = all(c -> prefix_eq(r0, R0, P[(arm, u, c)]...), PCLASSES)
        sp = [spec_ok(P[(arm, u, c)][2], u) for c in CLASSES]
        push!(R4, (key = "$arm u$u", pe = pe, sp = all(first, sp), info = join(last.(sp), "; ")))
    end
    for (k, (r, R)) in P
        k[1] == "partner" || continue
        local r0, R0
        r0, R0 = P[("partner", k[2], "0")]
        push!(R4, (key = "partner u$(k[2]) $(k[3])", pe = prefix_eq(r0, R0, r, R), sp = spec_ok(R, k[2])[1], info = ""))
    end
    for x in R4; isempty(x.info) || out("R4 ", rpad(x.key, 12), ": prefix to the head of tp equal across classes ", x.pe, ", perturbations as specified ", x.sp, "  (", x.info, ")"); end
    out("R4 partner runs: prefix equal and as specified in ", count(x -> x.pe && x.sp, filter(x -> startswith(x.key, "partner"), R4)), "/16")
    neg4 = Bool[]
    for c in ("a", "b")
        local rn, Rn, r0, R0
        rn, Rn = run_one("B-ret", c, first(PILOT); brk = :r4, extra = TR)
        r0, R0 = P[("B-ret", first(PILOT), "0")]
        push!(neg4, prefix_eq(r0, R0, rn, Rn))
    end
    out("R4   neg: perturbing at tp - 1, prefix equal to class 0 (must be false) for a, b: ", neg4)
    r4ok = all(x -> x.pe && x.sp, R4) && !any(neg4)
    out("R4: ", r4ok)
    # comparison with the frozen record
    orig = [l for l in eachline(joinpath(EXP, "results-bret-gates.out")) if startswith(l, "R3") || startswith(l, "R4")]
    so = Set(orig); sn = Set(lines)
    onlyO = [l for l in orig if !(l in sn)]; onlyN = [l for l in lines if !(l in so)]
    hdr = "== recheck with $(Threads.nthreads()) thread(s): R3 $(r3ok), R4 $(r4ok); R3/R4 lines: recheck $(length(lines)), original $(length(orig)); " *
          "identical as sets: $(isempty(onlyO) && isempty(onlyN))"
    println(hdr)
    open(joinpath(EXP, "results-bret-gates-recheck.out"), "a") do io
        println(io, hdr)
        for l in lines; println(io, l); end
        for l in onlyO; println(io, "only in the original: ", l); end
        for l in onlyN; println(io, "only in the recheck: ", l); end
    end
end

recheck()
