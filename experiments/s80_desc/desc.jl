# S80 descriptive check (discussion/specs/S80-draft-trace1-confirm.md §10.5; codex 11:56Z P2-P4, S-R 11:59Z P1-P8).
# Seen lives only; no new seeds. Includes s80_diag/diag.jl unchanged (its main block does not run when included).
# usage: julia --project=. -t 4 experiments/s80_desc/desc.jl
include(joinpath(@__DIR__, "..", "s80_diag", "diag.jl"))
const PRED80E = joinpath(@__DIR__, "predictions.toml"); const OUT80E = joinpath(@__DIR__, "out"); mkpath(OUT80E)
const HSTAR = 7.5; const D4 = 0.01

# C4 increments c_t (independent of h) and the PH path with resets at h: state (m, M) after each t, alarm flags
function c4inc(ℓ)
    N = length(ℓ); c = zeros(N); μ = 0.0
    for t in 1:N; c[t] = ℓ[t] - μ - D4; μ += (ℓ[t] - μ) * MU_K; end   # same order as firemask: μ_t before ℓ_t
    return c
end
function phpath(c, h)
    N = length(c); m = 0.0; M = 0.0; ma = zeros(N); Ma = zeros(N); pre = zeros(N); alarm = falses(N)
    for t in 1:N
        m += c[t]; M = min(M, m); pre[t] = m - M
        if t % PSTEP == 0 && m - M > h; alarm[t] = true; ma[t] = m; Ma[t] = M; m = 0.0; M = 0.0; else ma[t] = m; Ma[t] = M; end
        # ma/Ma at an alarm hold the pre-reset values; the state carried forward is (0, 0)
    end
    return (alarm = alarm, ma = ma, Ma = Ma, pre = pre)
end
# replay c[r] from state (m0, M0) and report whether m - M > h at a decision point <= ta
function replay(c, r, m0, M0, h, ta; zero = 0)
    m = m0; M = M0
    for t in r
        t > ta && break
        m += (t == zero ? 0.0 : c[t]); M = min(M, m)
        t % PSTEP == 0 && m - M > h && return true
    end
    return false
end
signp(k, n) = sum(binomial(n, i) for i in k:n) / 2.0^n   # one-sided sign test P(X >= k), X ~ Bin(n, 1/2)

function run80e()
    isfile(PRED80E) || error("predictions not frozen: $PRED80E")
    io = IOBuffer(); w0 = TOML.parsefile(W0_R3)["w0"]
    lives = [(st, l) for st in (1, 2) for l in 1:NLIFE]
    saved = Dict(j => loadlife4(j[1], "FGT", j[2]) for j in lives)
    D = Dict(j => ownq(saved[j].P, saved[j].Y, nothing) for j in lives)
    S = Dict(j => selset(saved[j], EPS75, w0) for j in lives); Ns = Dict(j => D[j].N for j in lives)
    C = Dict(j => c4inc(D[j].ℓ) for j in lives)
    P = Dict((j, h) => phpath(C[j], h) for j in lives for h in (HSTAR, 19.0))
    # gate: our PH path reproduces firemask at both h, and the counts of s80_diag at h*
    for j in lives, h in (HSTAR, 19.0); P[(j, h)].alarm == firemask("C4", (delta = D4,), h, D[j]) || error("PH gate $j $h"); end
    c = counts(j -> P[(j, HSTAR)].alarm, lives, Ns, S, L80); (c.X, c.K, c.Z, c.W) == (27, 30, 31, 120) || error("count gate $c")
    println(io, "gate: PH path from c_t == firemask (h = 7.5, 19, 8 lives); h* counts 27/30, 31/120 reproduced")
    Y = Dict(j => saved[j].Y for j in lives)
    wins = [(j, :r, w, 0) for j in lives for w in routinewins(Ns[j], L80)]
    append!(wins, [(j, :f, formwin(i, L80), i) for j in lives for i in S[j]])
    count(x -> x[2] == :r, wins) == 120 && count(x -> x[2] == :f, wins) == 30 || error("window gate")
    n0(j, w) = count(!, view(Y[j], w))
    # ---- A
    println(io, "== A: by n0 layer (width 3). per kind: windows / windows with >= 1 alarm / alarms")
    for h in (HSTAR, 19.0)
        println(io, "  h = $h")
        for lo in 0:3:21
            sel(k) = [x for x in wins if x[2] == k && (lo == 21 ? n0(x[1], x[3]) >= 21 : lo <= n0(x[1], x[3]) <= lo + 2)]
            s = [(length(v), count(x -> any(view(P[(x[1], h)].alarm, x[3])), v), sum(x -> count(view(P[(x[1], h)].alarm, x[3])), v; init = 0)) for v in (sel(:r), sel(:f))]
            println(io, "    n0 $(lo == 21 ? "21+" : "$lo-$(lo+2)"): routine $(s[1][1])/$(s[1][2])/$(s[1][3])  formation $(s[2][1])/$(s[2][2])/$(s[2][3])")
        end
    end
    # ---- B
    ab(j, w) = (z = [t for t in w if !Y[j][t]]; isempty(z) ? nothing : (a = mean(C[j][z]), b = mean(D[j].ℓ[z])))
    println(io, "== B: D = a_f - median(a_r) over same-life routine windows with |n0_r - n0_f| <= 1 and n0 > 0")
    Dall = Float64[]; Dlife = Dict(); Elife = Dict(); used = Dict(j => Set{Int}() for j in lives); nfv = Dict(j => 0 for j in lives)
    for j in lives
        rs = [(w, n0(j, w), ab(j, w)) for (jj, k, w, _) in wins if jj == j && k == :r]
        Dj = Float64[]; Ej = Float64[]
        for (jj, k, w, i) in wins
            (jj == j && k == :f) || continue
            nf = n0(j, w); af = ab(j, w)
            cand = [r for r in rs if r[3] !== nothing && abs(r[2] - nf) <= 1]
            exact = [r for r in cand if r[2] == nf]
            if af === nothing || isempty(cand)   # codex I-R P5: separate the two hold reasons
                println(io, "  st$(j[1]) life $(j[2]) i=$i n0=$nf: held ($(af === nothing ? "a_f undefined (n0 = 0)" : "no candidate"))"); continue
            end
            d = af.a - median([r[3].a for r in cand]); db = af.b - median([r[3].b for r in cand])
            de = isempty(exact) ? nothing : af.a - median([r[3].a for r in exact])
            de === nothing || push!(Ej, de); push!(Dj, d); push!(Dall, d); nfv[j] += 1; foreach(r -> push!(used[j], first(r[1])), cand)
            println(io, "  st$(j[1]) life $(j[2]) i=$i n0=$nf: a_f=$(f4(af.a)) D=$(f4(d)) Db=$(f4(db)) candidates=$(length(cand)) exact-D=$(de === nothing ? "-" : f4(de))")
        end
        isempty(Dj) || (Dlife[j] = median(Dj)); isempty(Ej) || (Elife[j] = median(Ej))
    end
    for j in lives
        println(io, "  [life] st$(j[1]) life $(j[2]): valid formation $(nfv[j]), routine windows used $(length(used[j])), median D $(haskey(Dlife, j) ? f4(Dlife[j]) : "-"), exact-n0 sign $(haskey(Elife, j) ? (Elife[j] > 0 ? "+" : Elife[j] < 0 ? "-" : "0") : "held")")   # codex I-R P1
    end
    nv = length(Dall); nl = length(Dlife)
    pos = count(>(0), values(Dlife)); neg = count(<(0), values(Dlife)); zer = nl - pos - neg
    p = pos + neg == 0 ? 1.0 : signp(pos, pos + neg); md = isempty(Dall) ? NaN : median(Dall)
    println(io, "  valid formation $nv, lives $nl; lives + / 0 / - = $pos / $zer / $neg; sign test one-sided p = $(f4(p)); median D over all = $(f4(md))")
    r2 = nv < 15 || nl < 5; r1 = !r2 && p <= 0.05 && md > 0
    println(io, "  rule: R2 $(r2 ? "applies (held)" : "does not apply"); R1 $(r2 ? "-" : r1 ? "holds" : "does not hold") -> $(r2 ? "held" : r1 ? "freeze one prediction for unseen lives" : "hold clock search, back to S80 main run")")
    # ---- C
    println(io, "== C: first alarm in window at h* (routine: alarmed windows; formation: detected windows)")
    tally = Dict(k => [0, 0, 0] for k in (:r, :f))   # windows, carry-over counterexamples, single-example counterexamples
    for (j, k, w, i) in wins
        pp = P[(j, HSTAR)]; ta = findfirst(view(pp.alarm, w)); ta === nothing && continue
        ta = first(w) + ta - 1; t0 = first(w)
        m0, M0 = t0 == 1 ? (0.0, 0.0) : (pp.alarm[t0-1] ? (0.0, 0.0) : (pp.ma[t0-1], pp.Ma[t0-1]))
        S0 = m0 - M0; r = t0:ta
        s0 = sum(C[j][t] for t in r if !Y[j][t]; init = 0.0); s1 = sum(C[j][t] for t in r if Y[j][t]; init = 0.0)
        dM = M0 - pp.Ma[ta]; Sa = pp.ma[ta] - pp.Ma[ta]
        abs(Sa - (S0 + s0 + s1 + dM)) < 1e-9 || error("identity gate $j $w")
        replay(C[j], r, m0, M0, HSTAR, ta) || error("replay gate $j $w")
        ta == t0 || !replay(C[j], r, m0, M0, HSTAR, ta - 1) || error("replay early gate $j $w")   # codex I-R P7
        carry = replay(C[j], r, 0.0, 0.0, HSTAR, ta)
        posc = [t for t in r if C[j][t] > 0]
        single = all(t -> replay(C[j], r, m0, M0, HSTAR, ta; zero = t), posc)
        tl = tally[k]; tl[1] += 1; tl[2] += carry; tl[3] += single
        println(io, "  $(k == :r ? "routine" : "formation i=$i") st$(j[1]) life $(j[2]) $(first(w)):$(last(w)) alarm@$(ta - t0 + 1): S0=$(f4(S0)) Σc(Y=0)=$(f4(s0)) Σc(Y≠0)=$(f4(s1)) ΔM=$(f4(dM)) max c=$(f4(maximum(C[j][r]))) m-M=$(f4(Sa)) n0-to-alarm=$(count(t -> !Y[j][t], r)) | S0=0 still alarms: $carry | survives every single removal: $single")
    end
    for k in (:r, :f); println(io, "  [$(k == :r ? "routine" : "formation")] windows $(tally[k][1]), carry-over counterexamples $(tally[k][2]), single-example counterexamples $(tally[k][3])"); end
    tr = tally[:r]
    (tally[:r][1], tally[:f][1]) == (31, 27) || error("C window gate $(tally[:r][1]), $(tally[:f][1])")   # codex I-R P7
    println(io, "gate: identity, unmodified replay alarms first at the original time, C windows 31 routine / 27 formation")
    println(io, "S80-E1 (R2 does not apply): $(!r2 ? "holds" : "miss")  valid $nv, lives $nl")
    println(io, "S80-E2 (R1 holds): $(r1 ? "holds" : "miss")")
    println(io, "S80-E3 (majority of alarmed routine windows still alarm from S0 = 0): $(2tr[2] > tr[1] ? "holds" : "miss")  $(tr[2])/$(tr[1])")
    println(io, "S80-E4 (majority survive every single removal): $(2tr[3] > tr[1] ? "holds" : "miss")  $(tr[3])/$(tr[1])")
    s = String(take!(io)); print(s); write(joinpath(OUT80E, "desc.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    run80e()
end
