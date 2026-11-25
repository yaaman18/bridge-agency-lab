# S81 descriptive pairing of C4 and O-win per switch (discussion/specs/S81-draft-pair-c4-owin.md; predictions frozen, codex S-R 12:34Z P1-P5).
# Seen 48 lives only (S72 r4 8 lives + S80 revision-1 40 lives from s80_main/out/rev1); no new seeds. S80 frozen thresholds, L = 1000.
# Includes s80_main/main.jl unchanged (its main block does not run when included).
# usage: julia --project=. -t 8 experiments/s81_pair/s81.jl
include(joinpath(@__DIR__, "..", "s80_main", "main.jl"))
const PRED81 = joinpath(@__DIR__, "predictions.toml"); const OUT81 = joinpath(@__DIR__, "out"); mkpath(OUT81)
const FREEZE81 = joinpath(@__DIR__, "..", "freeze-s81.txt")
const H81 = 13.75; const TH81 = 0.0075; const W81 = 500

# PH path with the valley index: m - M at t equals sum(c[v+1:t]) since the last valley v (M attained or reset), plus nothing else
function phv(c, h)
    N = length(c); m = 0.0; M = 0.0; v = 0; pre = zeros(N); val = zeros(Int, N); alarm = falses(N)
    for t in 1:N
        m += c[t]; m <= M && (M = m; v = t); pre[t] = m - M; val[t] = v
        if t % PSTEP == 0 && m - M > h; alarm[t] = true; m = 0.0; M = 0.0; v = t; end
    end
    return (alarm = alarm, pre = pre, val = val)
end
med(v) = isempty(v) ? nothing : median(v)
fm(x) = x === nothing ? "-" : f4(x)

function run81()
    frozen81 = (h = bytes2hex(sha256(read(PRED81))); any(==("$h  experiments/s81_pair/predictions.toml"), split(read(FREEZE81, String), "\n")))
    frozen81 || error("predictions not frozen")
    thr = TOML.parsefile(THR80); thr["C4 delta=0.01 L=1000"] == H81 && thr["O-win L=1000"] == TH81 || error("threshold gate")
    io = IOBuffer(); w0 = TOML.parsefile(W0_R3)["w0"]
    # lives: (group, id) => (P, Y, U, D, N, S)
    s8 = seen8(); LV = []
    for j in s8.lives
        M = s8.M[j]; push!(LV, (g = "seen8", id = "st$(j[1]) life $(j[2])", Y = s8.saved[j].Y, U = losses(M.P, M.Y) .- losses(M.Pc, M.Y),
                                D = s8.X[j].D, so = s8.X[j].so, N = s8.Ns[j], S = s8.S[j]))
    end
    for j in 1:NL80
        r = deserialize(joinpath(OUT80R, "life_$j.jls")); r.life == life80(j) && r.seeds == seedsR(j, 2) || error("life file gate $j"); twingate(r)
        x = clockdata(r); push!(LV, (g = "s80", id = "life $j", Y = r.Y, U = losses(r.P, r.Y) .- losses(r.Pc, r.Y), D = x.D, so = x.so, N = r.N, S = selset(r, EPS75, w0)))
    end
    # gates: counts reproduce thresh.out (seen 8) and run.out (40)
    for (g, ref) in (("seen8", ((21, 30, 5, 120), (30, 30, 0, 120))), ("s80", ((104, 153, 19, 600), (149, 153, 0, 600))))
        ix = findall(x -> x.g == g, LV); Ns = Dict(k => LV[k].N for k in ix); S = Dict(k => LV[k].S for k in ix)
        c4 = counts(k -> firemask("C4", (delta = 0.01,), H81, LV[k].D), ix, Ns, S, L80)
        co = counts(k -> mask80("O-win", (so = LV[k].so, D = LV[k].D), TH81), ix, Ns, S, L80)
        ((c4.X, c4.K, c4.Z, c4.W), (co.X, co.K, co.Z, co.W)) == ref || error("count gate $g: $c4 $co")
    end
    println(io, "gate: counts reproduce thresh.out (seen 8: C4 21/30 5/120, O-win 30/30 0/120) and rev1 run.out (40: C4 104/153 19/600, O-win 149/153 0/600)")
    rows = []; rrows = []
    for (k, x) in enumerate(LV)
        c = c4inc(x.D.ℓ); p = phv(c, H81)
        p.alarm == firemask("C4", (delta = 0.01,), H81, x.D) || error("PH gate $(x.id)")
        om = BitVector([!isnan(x.so[t]) && x.so[t] > TH81 for t in 1:x.N]); om == mask80("O-win", (so = x.so, D = x.D), TH81) || error("O gate $(x.id)")
        Y = x.Y
        # per-life baseline for F2: a of routine windows with n0 > 0
        rw = routinewins(x.N, L80)
        ra = [mean(c[t] for t in w if !Y[t]) for w in rw if any(t -> !Y[t], w)]; base = med(ra)
        # C4 decomposition at a decision point t* in window w: carry-in from before w, in-window post-valley contributions
        function dec(w, ts)
            v = p.val[ts]; inw = max(v + 1, first(w)):ts
            carry = v + 1 < first(w) ? sum(c[v+1:first(w)-1]) : 0.0
            abs(carry + sum(c[inw]; init = 0.0) - p.pre[ts]) < 1e-9 || error("decomposition gate $(x.id) $ts")
            cs = sort(c[inw], rev = true); s = p.pre[ts]
            return (S = s, carry = carry, top1 = isempty(cs) ? 0.0 : cs[1], top3 = sum(cs[1:min(3, end)]; init = 0.0),
                    in0 = sum((c[t] for t in inw if !Y[t]); init = 0.0), in1 = sum((c[t] for t in inw if Y[t]); init = 0.0))
        end
        dps(w) = [t for t in w if t % PSTEP == 0]
        for (kind, w, i) in vcat([(:f, formwin(i, L80), i) for i in x.S], [(:r, w, 0) for w in rw])
            ta4 = findfirst(view(p.alarm, w)); tao = findfirst(view(om, w))
            ta4 = ta4 === nothing ? nothing : first(w) + ta4 - 1; tao = tao === nothing ? nothing : first(w) + tao - 1
            d4 = ta4 !== nothing; dO = tao !== nothing
            grp = d4 && dO ? "both" : dO ? "O only" : d4 ? "C4 only" : "neither"
            n0 = count(t -> !Y[t], w)
            if kind == :r
                ts = d4 ? ta4 : dps(w)[argmax(p.pre[dps(w)])]
                push!(rrows, (g = x.g, id = x.id, grp = grp, n0 = n0, alarm = d4, dec = dec(w, ts))); continue
            end
            T = TS[i]; ts = d4 ? ta4 : dps(w)[argmax(p.pre[dps(w)])]   # first max decision point when no alarm
            af = n0 > 0 ? mean(c[t] for t in w if !Y[t]) : nothing
            ou = nothing
            if dO   # O-win window at its first alarm, split at T (codex P4)
                ow = tao-W81+1:tao; abs(mean(x.U[ow]) - x.so[tao]) < 1e-12 || error("O window gate $(x.id) $i")
                post = max(T + 1, first(ow)):tao   # codex I-R P3: the part of the actual window after T
                ou = (pre = sum(x.U[t] for t in ow if t <= T; init = 0.0), post0 = sum((x.U[t] for t in post if !Y[t]); init = 0.0),
                      post1 = sum((x.U[t] for t in post if Y[t]); init = 0.0), n0o = count(t -> !Y[t], T+1:tao), el = tao - T)
                abs(ou.pre + ou.post0 + ou.post1 - sum(x.U[ow])) < 1e-9 || error("O split gate $(x.id) $i")
            end
            push!(rows, (g = x.g, id = x.id, i = i, grp = grp, n0 = n0, af = af, base = base, el4 = d4 ? ta4 - T : nothing,
                         short = H81 - maximum(p.pre[dps(w)]), dec = dec(w, ts), ou = ou,
                         s0 = sum((c[t] for t in w if !Y[t]); init = 0.0), s1 = sum((c[t] for t in w if Y[t]); init = 0.0)))
        end
    end
    G = ["both", "O only", "C4 only", "neither"]
    length(rows) == 183 && length(rrows) == 720 || error("window count gate $(length(rows)) $(length(rrows))")
    for g in ("seen8", "s80")   # marginal gate (codex P4)
        f = [r for r in rows if r.g == g]; q = [r for r in rrows if r.g == g]
        (count(r -> r.grp in ("both", "C4 only"), f), count(r -> r.grp in ("both", "O only"), f), count(r -> r.alarm, q)) ==
            (g == "seen8" ? (21, 30, 5) : (104, 149, 19)) || error("marginal gate $g")
        count(r -> r.grp in ("both", "O only"), q) == 0 && (length(f), length(q)) == (g == "seen8" ? (30, 120) : (153, 600)) || error("routine O / row count gate $g")   # codex I-R P4
    end
    println(io, "gate: PH path with valleys == firemask, O-win mask == mask80, decomposition carry + in-window == m - M at every used point, O window mean == score; 183 switches, 720 routine windows; pair marginals match")
    println(io, "== pairs (switches)")
    for g in ("seen8", "s80", "all")
        f = g == "all" ? rows : [r for r in rows if r.g == g]
        println(io, "  $g: " * join(["$gg $(count(r -> r.grp == gg, f))" for gg in G], ", "))
    end
    println(io, "== pairs (routine windows; alarm in window)")
    for g in ("seen8", "s80", "all")
        f = g == "all" ? rrows : [r for r in rrows if r.g == g]
        println(io, "  $g: " * join(["$gg $(count(r -> r.grp == gg, f))" for gg in G], ", "))
    end
    q(v) = isempty(v) ? "-" : "median $(f4(median(v))) [q25 $(f4(quantile(v, 0.25))), q75 $(f4(quantile(v, 0.75)))] n=$(length(v))"
    println(io, "== by group (switches, all 48 lives): frequency n0, size a_f (n0 > 0), C4 shortfall h - max(m-M), Σc(Y=0), Σc(Y≠0) over the window")
    for gg in G
        f = [r for r in rows if r.grp == gg]; isempty(f) && continue
        println(io, "  [$gg] n0 $(q(Float64[r.n0 for r in f]))")
        println(io, "  [$gg] a_f $(q([r.af for r in f if r.af !== nothing])); a_f - base $(q([r.af - r.base for r in f if r.af !== nothing && r.base !== nothing]))")
        println(io, "  [$gg] shortfall $(q([r.short for r in f])); Σc(Y=0) $(q([r.s0 for r in f])); Σc(Y≠0) $(q([r.s1 for r in f]))")
    end
    println(io, "== O-only switches (one line each)")
    for r in rows
        r.grp == "O only" || continue
        o = r.ou
        println(io, "  $(r.g) $(r.id) i=$(r.i): n0=$(r.n0) a_f=$(fm(r.af)) base=$(fm(r.base)) shortfall=$(f4(r.short)) Σc0=$(f4(r.s0)) Σc1=$(f4(r.s1)) | O alarm @$(o.el) n0-to-O=$(o.n0o) Σu pre-T=$(f4(o.pre)) post Y=0 $(f4(o.post0)) post Y≠0 $(f4(o.post1))")
    end
    println(io, "== O-win evidence at its first alarm (switches detected by O): Σu over the 500-window split at T and by Y")
    for gg in ("both", "O only")
        f = [r for r in rows if r.grp == gg]
        println(io, "  [$gg] elapsed $(q(Float64[r.ou.el for r in f])); n0 to O alarm $(q(Float64[r.ou.n0o for r in f]))")
        println(io, "  [$gg] Σu pre-T $(q([r.ou.pre for r in f])); post Y=0 $(q([r.ou.post0 for r in f])); post Y≠0 $(q([r.ou.post1 for r in f]))")
        println(io, "  [$gg] share of post Σu from Y≠0 (post0 + post1 > 0): $(q([r.ou.post1 / (r.ou.post0 + r.ou.post1) for r in f if r.ou.post0 + r.ou.post1 > 0]))")
    end
    println(io, "== reliance on large contributions (C4 at alarm, or at the first max decision point without alarm): S = m - M = carry + in-window; top1/top3 of in-window post-valley c")
    sh(a, b) = b == 0 ? nothing : a / b
    for (lab, f) in (("formation C4-detected", [r.dec for r in rows if r.el4 !== nothing]), ("formation C4-missed", [r.dec for r in rows if r.el4 === nothing]),
                     ("routine alarmed", [r.dec for r in rrows if r.alarm]), ("routine not alarmed", [r.dec for r in rrows if !r.alarm]))
        t1 = filter(!isnothing, [sh(d.top1, d.S) for d in f]); t3 = filter(!isnothing, [sh(d.top3, d.S) for d in f])
        println(io, "  [$lab] n=$(length(f)) S $(q([d.S for d in f])); carry $(q([d.carry for d in f])); top1 $(q([d.top1 for d in f])); top3 $(q([d.top3 for d in f]))")
        println(io, "  [$lab] top1/S $(q(t1)); top3/S $(q(t3)); in-window Y=0 $(q([d.in0 for d in f])); Y≠0 $(q([d.in1 for d in f]))")
    end
    # predictions
    m2(v) = isempty(v) ? nothing : median(v)
    for g in ("seen8", "s80")
        f = [r for r in rows if r.g == g]
        println(io, "  [F1 by group] $g: O only n=$(count(r -> r.grp == "O only", f)) median n0 $(fm(m2(Float64[r.n0 for r in f if r.grp == "O only"]))); both n=$(count(r -> r.grp == "both", f)) median n0 $(fm(m2(Float64[r.n0 for r in f if r.grp == "both"])))")
    end
    mo = m2(Float64[r.n0 for r in rows if r.grp == "O only"]); mb = m2(Float64[r.n0 for r in rows if r.grp == "both"])
    f1 = mo === nothing || mb === nothing ? "not decidable" : mo < mb ? "hit" : "miss"
    println(io, "S81-F1 (median n0 O only < both): $f1  O only $(fm(mo)), both $(fm(mb))")
    oo = [r for r in rows if r.grp == "O only" && r.n0 > 0]; und = count(r -> r.base === nothing, oo)
    Dn = length(oo); Kn = count(r -> r.base !== nothing && r.af > r.base, oo)
    f2 = Dn == 0 || und > 0 ? "not decidable" : 2Kn > Dn ? "hit" : "miss"
    println(io, "S81-F2 (2K > D): $f2  K=$Kn D=$Dn (O only with n0 = 0: $(count(r -> r.grp == "O only" && r.n0 == 0, rows)); undefined base $und)")
    s = String(take!(io)); print(s); write(joinpath(OUT81, "s81.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    run81()
end
