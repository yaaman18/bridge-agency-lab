# S84 endpoint difference N and path length P of the L-FGT prediction table (discussion/specs/S84-draft-endpoint-path.md;
# predictions frozen, codex S-R 2026-11-26 P1-P7). Seen 48 lives only; no new seeds. No clock, no threshold selection.
# Includes s83_key/key.jl unchanged (and through it s81/s80); their main blocks do not run when included.
# usage: julia --project=. -t 8 experiments/s84_np/np.jl
include(joinpath(@__DIR__, "..", "s83_key", "key.jl"))
const PRED84 = joinpath(@__DIR__, "predictions.toml"); const OUT84 = joinpath(@__DIR__, "out"); mkpath(OUT84)
const FREEZE84 = joinpath(@__DIR__, "..", "freeze-s84.txt")
const HS84 = (50, 200, 1000); const NK = 130

akey(k) = isodd(k) ? 1 : 2       # k = 2b + a (s72.jl r1key_map), a in {1, 2}
function table!(p, L)             # same expression order as predict2 (s72r2.jl)
    for k in 1:NK
        a = akey(k); rate = (L.n1[a] + 1) / (L.n[a] + 2)
        p[k] = clip((L.rn1[k] + ALPHA_R1 * rate) / (L.rn[k] + ALPHA_R1))
    end
    return p
end
table_ind(L) = map(k -> clip((L.rn1[k] + ALPHA_R1 * ((L.n1[2 - k % 2] + 1) / (L.n[2 - k % 2] + 2))) / (L.rn[k] + ALPHA_R1)), 1:NK)   # independent rebuild (P6)
l1(p, q) = (s = 0.0; for k in eachindex(p); s += abs(p[k] - q[k]); end; s)
cnt(L) = (copy(L.n), copy(L.n1), copy(L.rn), copy(L.rn1))
sameb(a, b) = length(a) == length(b) && all(i -> bits(a[i]) == bits(b[i]), eachindex(a))

# replay: official update2! one example at a time; a second learner updated per block as mainrun; full table after every example
function replay84(lf, life, savedP, origins)
    maps, _ = life_maps(life); N = lf.N; pts = main_points(N); bounds = vcat(0, TS, N)
    L = new_learner("FGT", life); L2 = new_learner("FGT", life)
    Tab = Matrix{Float64}(undef, NK, N + 1); table!(view(Tab, :, 1), L)
    sameb(table_ind(L), Tab[:, 1]) || error("table rebuild gate t=0")
    st0 = Dict{Int,Any}(); 0 in origins && (st0[0] = cnt(L))
    for seg in 1:5
        a, b = bounds[seg], bounds[seg+1]; m = maps[seg]; cur = a
        for c in vcat([t for t in pts if a < t < b], b)
            for t0 in (cur + 1):BLK:c
                idx = t0:min(t0 + BLK - 1, c)
                ps = predict2(L, lf, idx, m); ph = Tab[:, t0]   # table after example t0-1 = block head
                for (q, t) in enumerate(idx)
                    si, s = lf.ex[t]; stt = lf.streams[si]; ac = stt.act[s+1]; k = keyfor(stt, s, ac, m)
                    akey(k) == ac || error("key/action gate $t")
                    bits(ps[q]) == bits(savedP[t]) && bits(ph[k]) == bits(savedP[t]) || error("P bit gate $t")
                end
                for t in idx
                    update2!(L, lf, t:t, m); table!(view(Tab, :, t + 1), L)
                    sameb(table_ind(L), view(Tab, :, t + 1)) || error("table rebuild gate t=$t")
                    t in origins && (st0[t] = cnt(L))
                end
                update2!(L2, lf, idx, m)
                sameb(L.n, L2.n) && sameb(L.n1, L2.n1) && sameb(L.rn, L2.rn) && sameb(L.rn1, L2.rn1) || error("per-example vs per-block gate $(last(idx))")
            end
            cur = c
        end
    end
    d = [l1(view(Tab, :, s), view(Tab, :, s + 1)) for s in 1:N]          # d[s] = d(p(s-1), p(s))
    z = count(s -> sameb(view(Tab, :, s), view(Tab, :, s + 1)), 1:N)      # E4: whole table bit-identical
    vz = 0; for t in 1:N; si, s = lf.ex[t]; stt = lf.streams[si]; seg = searchsortedfirst(bounds, t) - 1
        k = keyfor(stt, s, stt.act[s+1], maps[seg]); bits(Tab[k, t]) == bits(Tab[k, t + 1]) && (vz += 1); end
    return (Tab = Tab, d = d, z = z, vz = vz, st0 = st0, lam = L.lam)
end

function np_at(R, t0, h)
    N = l1(view(R.Tab, :, t0 + 1), view(R.Tab, :, t0 + h + 1))
    P = 0.0; for s in (t0 + 1):(t0 + h); P += R.d[s]; end
    P2 = sum(R.d[(t0 + 1):(t0 + h)]); isapprox(P, P2; rtol = 1e-9) || error("P resum gate $t0 $h")
    0 <= N <= P * (1 + 1e-12) || error("0 <= N <= P gate $t0 $h N=$N P=$P")   # P7
    return N, P
end
function decay_twin(R, t0, h)
    n, n1, rn, rn1 = deepcopy(R.st0[t0]); L = (n = n, n1 = n1, rn = rn, rn1 = rn1); lam = R.lam
    p = zeros(NK); q = zeros(NK); table!(p, L); p0 = copy(p); P = 0.0
    for _ in 1:h
        L.n .*= lam; L.n1 .*= lam; L.rn .*= lam; L.rn1 .*= lam    # update2! decay, no increments
        table!(q, L); P += l1(p, q); p .= q
    end
    for (v, v0) in zip((L.n, L.n1, L.rn, L.rn1), R.st0[t0])         # P6: every component = origin * lam^h (scalar loop)
        for i in eachindex(v); x = v0[i]; for _ in 1:h; x *= lam; end; bits(x) == bits(v[i]) || error("decay twin gate $t0"); end
    end
    return l1(p0, p), P
end

function origins84(x)
    N = x.N; J = seams83(x.lf); rw = routinewins(N, L83)
    O = Dict{Tuple{String,Int},Vector{Int}}()
    for h in HS84
        O[("F", h)] = [TS[i] for i in x.S]
        O[("Fp", h)] = [TS[i] for i in setdiff(1:4, x.S)]
        O[("R", h)] = [first(w) - 1 for w in rw if !any(j -> first(w) - 1 - 199 <= j <= first(w) - 1 + h, J)]
        O[("C", h)] = [j - 1 for j in J if j + h - 1 <= N && !any(i -> !isempty(intersect(j:(j + h - 1), formwin(i, L83))), 1:4)]
    end
    return O
end

function run84()
    h = bytes2hex(sha256(read(PRED84))); any(==("$h  experiments/s84_np/predictions.toml"), split(read(FREEZE84, String), "\n")) || error("predictions not frozen")
    io = IOBuffer(); LV = lives83(); length(LV) == 48 || error("48 lives")
    res = tmapv(LV) do x
        O = origins84(x); orig = Set{Int}(vcat(values(O)...))
        R = replay84(x.lf, x.life, x.P, orig)
        rows = Dict{Tuple{String,Int},Vector{NTuple{4,Float64}}}()
        for (key, v) in O, t0 in v
            N, P = np_at(R, t0, key[2]); Nd, Pd = decay_twin(R, t0, key[2])
            push!(get!(rows, key, NTuple{4,Float64}[]), (N, P, Nd, Pd))
        end
        (id = x.id, rows = rows, z = R.z, vz = R.vz, nsteps = x.N, nS = length(x.S))
    end
    sum(r.nS for r in res) == 183 || error("K gate")
    println(io, "gate: 48 lives; per-example update2! = per-block update2! counters bitwise; block-head table and predict2 = saved P bitwise; independent table rebuild bitwise at every step; P resum; 0<=N<=P; decay twin = origin*lam^h bitwise; K = 183")
    pool(g, hh) = vcat([get(r.rows, (g, hh), NTuple{4,Float64}[]) for r in res]...)
    rho(v) = [a[1] / a[2] for a in v if a[2] > 0]
    med(g, hh) = (v = rho(pool(g, hh)); isempty(v) ? nothing : median(v))
    println(io, "== groups (pooled over origins; rho = N/P; dec = decay-only twin, control value, not a share)")
    for g in ("F", "R", "C", "Fp"), hh in HS84
        v = pool(g, hh); r = rho(v); np0 = count(a -> a[2] == 0, v)
        nd = [a[3] / a[1] for a in v if a[1] > 0]; pd = [a[4] / a[2] for a in v if a[2] > 0]
        println(io, "  $g h=$hh: n $(length(v)) (P=0: $np0)  rho q1/med/q3 $(q3(r))  N $(q3([a[1] for a in v]))  P $(q3([a[2] for a in v]))  P/h med $(isempty(v) ? "-" : f4(median([a[2] for a in v]) / hh))  Ndec/N $(q3(nd))  Pdec/P $(q3(pd))")
    end
    for (g, hh) in (("F", 200), ("R", 1000))
        pl = [median(rho(r.rows[(g, hh)])) for r in res if haskey(r.rows, (g, hh)) && !isempty(rho(r.rows[(g, hh)]))]
        println(io, "  per-life medians $g h=$hh: lives $(length(pl)) q1/med/q3 $(q3(pl))")
    end
    mF = med("F", 200); mR = med("R", 1000); mR2 = med("R", 200); mC = med("C", 200)
    e1 = mF === nothing ? "undecidable" : mF >= 0.5 ? "hit" : "miss"
    lo, hi = 1 / (3sqrt(1000)), 3 / sqrt(1000)
    e2 = mR === nothing ? "undecidable" : lo <= mR <= hi ? "hit" : "miss"
    e3 = any(isnothing, (mF, mR2, mC)) ? "undecidable" : mR2 < mC < mF ? "hit" : "miss"
    Z = sum(r.z for r in res); ST = sum(r.nsteps for r in res); e4 = Z == 0 ? "hit" : "miss"
    VZ = sum(r.vz for r in res)
    println(io, "E1: median rho(F, 200) = $(fm(mF)) (>= 0.5) -> $e1")
    println(io, "E2: median rho(R, 1000) = $(fm(mR)) (in [$(f4(lo)), $(f4(hi))]) -> $e2")
    println(io, "E3: median rho(., 200): R $(fm(mR2))  C $(fm(mC))  F $(fm(mF)) (R < C < F) -> $e3")
    println(io, "E4: whole-table bit-identical law steps $Z / $ST checked steps (all updates incl. first) -> $e4")
    println(io, "  visited key's p bit-identical across its own update: $VZ / $ST")
    println(io, "S84-E1: $e1"); println(io, "S84-E2: $e2"); println(io, "S84-E3: $e3"); println(io, "S84-E4: $e4")
    println(io, "note: seen lives only; descriptive. No clock or threshold is chosen here.")
    s = String(take!(io)); print(s); write(joinpath(OUT84, "np.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    run84()
end
