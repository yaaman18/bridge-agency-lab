# S85 tick (endpoint distance to the expected-input twin) and individuality distance G (distance from the birth table, all 1/2)
# (discussion/specs/S85-draft-tick-and-individuality.md; predictions frozen; codex S-R 2026-11-26 P1-P7). Seen 48 lives only.
# Includes s84_np/np.jl unchanged (and through it s83/s81/s80); their main blocks do not run when included.
# usage: julia --project=. -t 8 experiments/s85_tick/tick.jl
include(joinpath(@__DIR__, "..", "s84_np", "np.jl"))
const PRED85 = joinpath(@__DIR__, "predictions.toml"); const OUT85 = joinpath(@__DIR__, "out"); mkpath(OUT85)
const FREEZE85 = joinpath(@__DIR__, "..", "freeze-s85.txt")
# rounding allowance: each table entry is (rn1 + a*((n1+1)/(n+2)))/(rn+a), 6 roundings of <= 1/2 ulp (<= 3 ulp of a value in [0,1] after
# the ratio, <= 4 eps(1.0) with slack); a difference of two entries <= 8 eps(1.0); 130 keys. Derived bound, not a chosen threshold (codex I-R P1).
const ATOL85 = NK * 8 * eps(1.0); const OFFS85 = -2000:50:2000

# counters as a plain mutable bundle (same field names as TabL, so table!/table_ind apply)
mutable struct C85; n::Vector{Float64}; n1::Vector{Float64}; rn::Vector{Float64}; rn1::Vector{Float64}; end
c85(L) = C85(copy(L.n), copy(L.n1), copy(L.rn), copy(L.rn1))
decay!(c, lam) = (c.n .*= lam; c.n1 .*= lam; c.rn .*= lam; c.rn1 .*= lam; c)   # same broadcast order as update2!
add!(c, k, a, y) = (c.n[a] += 1; c.n1[a] += y; c.rn[k] += 1; c.rn1[k] += y; c)   # y may be fractional (expected input)
step!(c, k, a, y, lam) = add!(decay!(c, lam), k, a, y)
raw(c, k) = (a = akey(k); (c.rn1[k] + ALPHA_R1 * ((c.n1[a] + 1) / (c.n[a] + 2))) / (c.rn[k] + ALPHA_R1))   # unclipped estimate
rawtab(c) = [raw(c, k) for k in 1:NK]
tab(c) = table!(zeros(NK), c)
Gof(p) = (s = 0.0; for k in eachindex(p); s += abs(p[k] - 0.5); end; s)
csame(a, b) = sameb(a.n, b.n) && sameb(a.n1, b.n1) && sameb(a.rn, b.rn) && sameb(a.rn1, b.rn1)

# expected-input twin from state c over keys K[t], A[t] for t in rng; returns tables at the requested offsets
function twin(c0, K, A, rng, lam, marks; Y = nothing)
    c = deepcopy(c0); out = Dict{Int,Vector{Float64}}(); j = 0
    for t in rng
        j += 1; decay!(c, lam); yv = Y === nothing ? raw(c, K[t]) : Y[t]; add!(c, K[t], A[t], yv)
        j in marks && (out[j] = tab(c))
    end
    return out, c
end

function life85(x)
    O = origins84(x); orig = Set{Int}(vcat(values(O)...))
    R = replay84(x.lf, x.life, x.P, orig)                       # all S84 gates (P bits, per-block, rebuild, ...)
    lf = x.lf; N = lf.N; maps, _ = life_maps(x.life); bounds = vcat(0, TS, N)
    K = zeros(Int, N); A = zeros(Int, N); Yv = zeros(Float64, N)
    L = new_learner("FGT", x.life); lam = L.lam
    st = Dict{Int,C85}(); 0 in orig && (st[0] = c85(L))
    Gd = zeros(N); Gi = zeros(N); tau = zeros(N); ndecpos = 0; neq = 0
    for t in 1:N
        si, s = lf.ex[t]; stt = lf.streams[si]; seg = searchsortedfirst(bounds, t) - 1
        a = stt.act[s+1]; y = stt.Y[s+1]; k = keyfor(stt, s, a, maps[seg]); K[t] = k; A[t] = a; Yv[t] = y
        c = c85(L); G0 = Gof(view(R.Tab, :, t))
        sameb(tab(c), view(R.Tab, :, t)) || error("table gate $t")
        Dx = decay!(deepcopy(c), lam); pD = tab(Dx); GD = Gof(pD)
        ph = raw(Dx, k)                                            # expected input: unclipped estimate after decay
        xh = add!(deepcopy(Dx), k, a, ph)
        update2!(L, lf, t:t, maps[seg])
        csame(L, add!(deepcopy(Dx), k, a, y)) || error("step = update2! gate $t")        # own step = official law, bitwise
        p1 = view(R.Tab, :, t + 1); G1 = Gof(p1)
        Gd[t] = GD - G0; Gi[t] = G1 - GD; Gd[t] > 0 && (ndecpos += 1)
        ph_t = tab(xh); tau[t] = l1(p1, ph_t)
        # (i-2) closed form on the unclipped tables, and clipped tau <= it
        ru = rawtab(L); rh = rawtab(xh); su = l1(ru, rh)
        g = (1 + ALPHA_R1 / (Dx.n[a] + 3)) / (Dx.rn[k] + 1 + ALPHA_R1)
        for j in 1:NK; (j != k && akey(j) == a) && (g += ALPHA_R1 / ((Dx.n[a] + 3) * (Dx.rn[j] + ALPHA_R1))); end
        cf = abs(y - ph) * g
        isapprox(su, cf; rtol = 1e-12, atol = ATOL85) || error("closed form gate $t su=$su cf=$cf")   # atol: rounding of 130 table differences, not a chosen threshold
        tau[t] <= su * (1 + 1e-12) + ATOL85 || error("clipped tau <= unclipped gate $t")
        tau[t] == l1(clip.(ru), clip.(rh)) || error("tau per-end clip rebuild gate $t")
        t in orig && (st[t] = c85(L))
    end
    G = [Gof(view(R.Tab, :, t + 1)) for t in 0:N]
    cs = 0.0; for t in 1:N; cs += Gd[t] + Gi[t]                                       # (i-1) closure on every prefix
        isapprox(cs, G[t+1] - G[1]; rtol = 1e-9, atol = t * ATOL85) || error("ledger closure gate $t"); end
    G[1] == 0.0 || error("birth G = 0 gate")
    rows = Dict{Tuple{String,Int},Vector{NamedTuple}}()
    for (key, v) in O, t0 in v
        h = key[2]; out, _ = twin(st[t0], K, A, (t0 + 1):(t0 + h), lam, Set([1, h]))
        _, c00 = twin(st[t0], K, A, (t0 + 1):t0, lam, Set{Int}())                        # (i-3) Theta(t,t) = 0
        (csame(c00, st[t0]) && l1(view(R.Tab, :, t0 + 1), tab(c00)) == 0.0) || error("Theta(t,t) = 0 gate $t0")
        Th = l1(view(R.Tab, :, t0 + h + 1), out[h])
        bits(l1(view(R.Tab, :, t0 + 2), out[1])) == bits(tau[t0 + 1]) || error("Theta(t-1,t) = tau gate $t0")   # (i-3)
        if key[1] == "F" && h == 200                                                    # (ii-1) on the multi-step twin
            o2, _ = twin(st[t0], K, A, (t0 + 1):(t0 + h), lam, Set([h]); Y = Yv)
            sameb(o2[h], view(R.Tab, :, t0 + h + 1)) || error("multi-step twin with real y gate $t0")
        end
        Nn, Pp = np_at(R, t0, h); Nd, _ = decay_twin(R, t0, h)
        cd = deepcopy(st[t0]); for _ in 1:h; decay!(cd, lam); end         # (ii-3) h broadcast decays vs scalar loop from the origin
        ci = deepcopy(st[t0]); for v in (ci.n, ci.n1, ci.rn, ci.rn1), i in eachindex(v); xv = v[i]; for _ in 1:h; xv *= lam; end; v[i] = xv; end
        (csame(cd, ci) && sameb(tab(cd), table_ind(ci))) || error("decay table rebuild gate $t0")
        flips = count(kk -> (R.Tab[kk, t0+1] - 0.5) * (R.Tab[kk, t0+h+1] - 0.5) < 0, 1:NK)
        push!(get!(rows, key, NamedTuple[]), (Th = Th, N = Nn, Nd = Nd, dG = G[t0+h+1] - G[t0+1], G0 = G[t0+1], G1 = G[t0+h+1],
            sdec = sum(Gd[(t0+1):(t0+h)]), sinc = sum(Gi[(t0+1):(t0+h)]), stau = sum(tau[(t0+1):(t0+h)]), flips = flips))
    end
    traj = Dict{String,Vector{Vector{Float64}}}()                                      # §5 G around switches and seams
    for (g, key) in (("F", ("F", 200)), ("C", ("C", 200)), ("R", ("R", 200))), t0 in get(O, key, Int[])
        push!(get!(traj, g, Vector{Float64}[]), [0 <= t0 + o <= N ? G[t0+o+1] - G[t0+1] : NaN for o in OFFS85])
    end
    return (id = x.id, rows = rows, traj = traj, ndecpos = ndecpos, nsteps = N, nS = length(x.S), Gend = G[end], Gmax = maximum(G))
end

# synthetic one key (k = 1, action 1), 20000 steps; returns Theta and N_dec at the offsets from t0 = 10000
function synth(pat; unsat = false)
    lam = 1 - 1 / 2000; c = C85(zeros(2), zeros(2), zeros(NK), zeros(NK)); T0 = 10000
    for t in 1:T0; step!(c, 1, 1, Float64(pat[mod1(t, length(pat))]), lam); end
    c0 = deepcopy(c); res = Dict{Int,Tuple{Float64,Float64}}(); rl = deepcopy(c); tw = deepcopy(c); dc = deepcopy(c)
    p0 = tab(c0)
    for j in 1:10000
        y = Float64(pat[mod1(T0 + j, length(pat))])
        step!(rl, 1, 1, y, lam); decay!(tw, lam); add!(tw, 1, 1, raw(tw, 1)); decay!(dc, lam)
        j in (1000, 10000) && (res[j] = (l1(tab(rl), tab(tw)), l1(p0, tab(dc))))
    end
    # (i-3) both fed the expected input: Theta = 0 bitwise
    r2 = deepcopy(c0); t2 = deepcopy(c0)
    for _ in 1:1000; decay!(r2, lam); add!(r2, 1, 1, raw(r2, 1)); decay!(t2, lam); add!(t2, 1, 1, raw(t2, 1)); end
    l1(tab(r2), tab(t2)) == 0.0 || error("expected-input path Theta = 0 gate")
    # codex I-R P3: twin() against an independently built expected-input run, and one changed outcome gives Theta > 0
    Ks = ones(Int, T0 + 10000); As = ones(Int, T0 + 10000); t3 = deepcopy(c0); Ye = zeros(T0 + 10000)
    for j in 1:1000; decay!(t3, lam); Ye[T0 + j] = raw(t3, 1); add!(t3, 1, 1, Ye[T0 + j]); end
    o3, c3 = twin(c0, Ks, As, (T0 + 1):(T0 + 1000), lam, Set([1000])); o4, c4 = twin(c0, Ks, As, (T0 + 1):(T0 + 1000), lam, Set([1000]); Y = Ye)
    (csame(c3, t3) && csame(c4, t3)) || error("synthetic twin vs independent expected-input run gate")
    Y5 = copy(Ye); Y5[T0 + 1] = Ye[T0 + 1] < 0.5 ? 1.0 : 0.0; o5, _ = twin(c0, Ks, As, (T0 + 1):(T0 + 1000), lam, Set([1000]); Y = Y5)
    th5 = l1(o5[1000], o3[1000]); (!unsat || th5 > 0) || error("one changed outcome Theta > 0 gate")
    res[-1] = (th5, NaN)
    return res
end

function run85()
    h = bytes2hex(sha256(read(PRED85))); any(==("$h  experiments/s85_tick/predictions.toml"), split(read(FREEZE85, String), "\n")) || error("predictions not frozen")
    io = IOBuffer()
    sa = synth([1]); sa[1000] == (0.0, 0.0) || error("(ii-2a) saturated Theta = N_dec = 0 gate: $(sa[1000])")
    sb = synth([1, 1, 1, 0]; unsat = true)
    LV = lives83(); length(LV) == 48 || error("48 lives")
    res = tmapv(life85, LV)
    sum(r.nS for r in res) == 183 || error("K gate")
    println(io, "gate: all S84 gates; own step = update2! bitwise every step; twin with real y = law (1 step every step, 200 steps at F); unclipped closed form |y-p^|g (rtol 1e-12, atol $(ATOL85) = 130*8*eps); ledger closure on every prefix (rtol 1e-9, atol t*ATOL); Theta(t,t) = 0; decay h-fold broadcast = scalar loop and tables; synthetic twin() = independent expected-input run; one changed outcome: period-4 Theta = $(sb[-1][1]) > 0 (saturated: $(sa[-1][1]), clip); clipped tau <= unclipped; tau = per-end clip rebuild; ledger closure; G(0) = 0; Theta(t-1,t) = tau bitwise; decay table rebuild; synthetic saturated Theta = N_dec = 0; expected-input path Theta = 0; K = 183")
    pool(g, hh) = vcat([get(r.rows, (g, hh), NamedTuple[]) for r in res]...)
    fld(v, f) = [getfield(a, f) for a in v]
    println(io, "== groups (pooled; Theta = endpoint L1 to the expected-input twin; N = S84 endpoint; Nd = decay-only twin; G = distance from birth table)")
    for g in ("F", "R", "C", "Fp"), hh in HS84
        v = pool(g, hh); isempty(v) && continue
        println(io, "  $g h=$hh: n $(length(v))  Theta $(q3(fld(v, :Th)))  sum tau $(q3(fld(v, :stau)))  N $(q3(fld(v, :N)))  Nd $(q3(fld(v, :Nd)))  G0 $(q3(fld(v, :G0)))  G1 $(q3(fld(v, :G1)))  dG $(q3(fld(v, :dG)))  sum dG_dec $(q3(fld(v, :sdec)))  sum dG_inc $(q3(fld(v, :sinc)))  flips $(q3(Float64.(fld(v, :flips))))")
    end
    med(g, hh, f) = (v = pool(g, hh); isempty(v) ? nothing : median(fld(v, f)))
    mR, mC, mF = med("R", 200, :Th), med("C", 200, :Th), med("F", 200, :Th)
    e1 = any(isnothing, (mR, mC, mF)) ? "undecidable" : mR < mC < mF ? "hit" : "miss"
    lv = [(median(fld(r.rows[("F", 200)], :Th)), median(fld(r.rows[("R", 200)], :Th))) for r in res
          if haskey(r.rows, ("F", 200)) && haskey(r.rows, ("R", 200)) && !isempty(r.rows[("F", 200)]) && !isempty(r.rows[("R", 200)])]
    nl = length(lv); nok = count(p -> p[1] > p[2], lv)
    e2 = nl == 0 ? "undecidable" : nok == nl ? "hit" : "miss"
    mT, mD = med("R", 1000, :Th), med("R", 1000, :Nd)
    e3 = any(isnothing, (mT, mD)) ? "undecidable" : mT < mD ? "hit" : "miss"
    DP = sum(r.ndecpos for r in res); ST = sum(r.nsteps for r in res); e4 = DP >= 1 ? "hit" : "miss"
    mG = med("F", 200, :dG); e5 = mG === nothing ? "undecidable" : mG < 0 ? "hit" : "miss"
    e6 = sb[10000][1] < sb[10000][2] && sb[10000][1] <= 2 * sb[1000][1] ? "hit" : "miss"
    println(io, "E1: median Theta(.,200) R $(fm(mR))  C $(fm(mC))  F $(fm(mF)) (R < C < F; R<F: $(any(isnothing, (mR, mF)) ? "-" : mR < mF), C between: $(e1)) -> $e1")
    println(io, "E2: lives with median Theta(F,200) > median Theta(R,200): $nok / $nl (lives lacking a group: $(48 - nl)) -> $e2")
    println(io, "E3: R h=1000 median Theta $(fm(mT)) < median N_dec $(fm(mD)) -> $e3")
    println(io, "E4: steps with Delta G_dec > 0: $DP / $ST -> $e4")
    println(io, "E5: F median G(T+200) - G(T) = $(fm(mG)) (< 0) -> $e5")
    println(io, "E6: synthetic (1,1,1,0): Theta/N_dec at h=1000 $(sb[1000])  h=10000 $(sb[10000]) -> $e6")
    println(io, "  synthetic (1): h=1000 $(sa[1000])  h=10000 $(sa[10000])")
    println(io, "  G at end of life q1/med/q3 $(q3([r.Gend for r in res]))  max G $(q3([r.Gmax for r in res]))")
    for (i, e) in enumerate((e1, e2, e3, e4, e5, e6)); println(io, "S85-E$i: $e"); end
    open(joinpath(OUT85, "gtraj.csv"), "w") do f                                         # §5 trajectories: G(t0+o) - G(t0), pooled
        println(f, "group,offset,n,q1,median,q3")
        for g in ("F", "C", "R"); M = vcat([get(r.traj, g, Vector{Float64}[]) for r in res]...)
            for (j, o) in enumerate(OFFS85); v = filter(!isnan, [m[j] for m in M]); isempty(v) && continue
                println(f, "$g,$o,$(length(v)),$(quantile(v, 0.25)),$(median(v)),$(quantile(v, 0.75))"); end; end
    end
    println(io, "note: seen lives only; descriptive. No clock or threshold is chosen here.")
    s = String(take!(io)); print(s); write(joinpath(OUT85, "tick.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    run85()
end
