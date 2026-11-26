# S83 descriptive check of the key-experience count rn[k_t] (discussion/specs/S83-draft-key-rn.md; predictions frozen, codex S-R 2026-11-26 P1-P6).
# Seen 48 lives only (S72 r4 8 lives + S80 revision-1 40 lives); no new seeds. No clock, no threshold.
# Includes s81_pair/s81.jl unchanged (and through it s80_main); their main blocks do not run when included.
# usage: julia --project=. -t 8 experiments/s83_key/key.jl
include(joinpath(@__DIR__, "..", "s81_pair", "s81.jl"))
const PRED83 = joinpath(@__DIR__, "predictions.toml"); const OUT83 = joinpath(@__DIR__, "out"); mkpath(OUT83)
const FREEZE83 = joinpath(@__DIR__, "..", "freeze-s83.txt")
const HEAD83 = 200; const L83 = 1000

# replay L-FGT with mainrun's cuts; record rn[k_t] and rn1[k_t] read at prediction time (block-head state), and the rate used
function replay83(lf, life; flipY = false)
    maps, _ = life_maps(life); N = lf.N; pts = main_points(N); bounds = vcat(0, TS, N)
    L = new_learner("FGT", life); rn = zeros(N); rn1 = zeros(N); rate = zeros(N); P = zeros(N); keys = zeros(Int, N)
    for seg in 1:5
        a, b = bounds[seg], bounds[seg+1]; m = maps[seg]; cur = a
        for c in vcat([t for t in pts if a < t < b], b)
            for t0 in (cur + 1):BLK:c
                idx = t0:min(t0 + BLK - 1, c)
                ps = predict2(L, lf, idx, m)
                for (q, t) in enumerate(idx)
                    si, s = lf.ex[t]; st = lf.streams[si]; ac = st.act[s+1]; k = keyfor(st, s, ac, m)
                    keys[t] = k; rn[t] = L.rn[k]; rn1[t] = L.rn1[k]; rate[t] = (L.n1[ac] + 1) / (L.n[ac] + 2); P[t] = ps[q]
                end
                if flipY   # same keys, maps and blocks; outcomes inverted
                    for t in idx
                        si, s = lf.ex[t]; st = lf.streams[si]; ac = st.act[s+1]; y = !st.Y[s+1]; k = keyfor(st, s, ac, m)
                        L.n .*= L.lam; L.n1 .*= L.lam; L.rn .*= L.lam; L.rn1 .*= L.lam
                        L.n[ac] += 1; L.n1[ac] += y; L.rn[k] += 1; L.rn1[k] += y
                    end
                else
                    update2!(L, lf, idx, m)
                end
            end
            cur = c
        end
    end
    return (rn = rn, rn1 = rn1, rate = rate, P = P, keys = keys)
end
seams83(lf) = [t for t in 2:lf.N if lf.ex[t][1] != lf.ex[t-1][1]]

function lives83()
    s8 = seen8(); w0 = s8.w0; LV = []
    for j in s8.lives
        seeds = j[1] == 1 ? SEEDS_ST1 : SEEDS_ST2; streams = Dict(u => stream2(u) for u in seeds)
        lf = make_life2(j[2], seeds, streams)
        push!(LV, (id = "st$(j[1]) life $(j[2])", life = j[2], lf = lf, P = s8.saved[j].P, Y = s8.saved[j].Y, N = s8.saved[j].N,
                   S = s8.S[j], D = s8.X[j].D, so = s8.X[j].so))
    end
    for j in 1:NL80
        r = deserialize(joinpath(OUT80R, "life_$j.jls")); r.life == life80(j) && r.seeds == seedsR(j, 2) || error("life file gate $j"); twingate(r)
        sd = seedsR(j, 2); lf = make_life3(sd, Dict(u => stream80(u) for u in sd))
        [s.seed for s in lf.streams] == r.seeds || error("seed list gate $j")
        x = clockdata(r)
        push!(LV, (id = "s80 life $j", life = r.life, lf = lf, P = r.P, Y = r.Y, N = r.N, S = selset(r, EPS75, w0), D = x.D, so = x.so))
    end
    return LV
end
q3(v) = isempty(v) ? "-" : "$(f4(quantile(v, 0.25))) / $(f4(median(v))) / $(f4(quantile(v, 0.75)))"
function auc(pos, neg)   # P(pos > neg) + 0.5 P(tie)
    (isempty(pos) || isempty(neg)) && return nothing
    s = 0.0; for a in pos, b in neg; s += a > b ? 1.0 : a == b ? 0.5 : 0.0; end
    return s / (length(pos) * length(neg))
end

function run83()
    h = bytes2hex(sha256(read(PRED83))); any(==("$h  experiments/s83_key/predictions.toml"), split(read(FREEZE83, String), "\n")) || error("predictions not frozen")
    thr = TOML.parsefile(THR80); thr["C4 delta=0.01 L=1000"] == H81 && thr["O-win L=1000"] == TH81 || error("threshold gate")
    io = IOBuffer(); LV = lives83(); n = length(LV); n == 48 || error("48 lives")
    R = tmapv(x -> replay83(x.lf, x.life), LV)
    RF = tmapv(x -> replay83(x.lf, x.life; flipY = true), LV)
    Ktot = 0; Wtot = 0
    rows = []; Wa = Float64[]; Wb = Float64[]; d0f = Dict{String,Vector{Float64}}(); d0r = Float64[]; aprime = []
    for (k, x) in enumerate(LV)
        r = R[k]; N = x.N
        x.lf.N == N || error("N gate $(x.id)")
        bits(r.P) == bits(x.P) || error("P bit gate $(x.id)")
        all(t -> bits(clip((r.rn1[t] + ALPHA_R1 * r.rate[t]) / (r.rn[t] + ALPHA_R1))) == bits(x.P[t]), 1:N) || error("recorded rn gate $(x.id)")
        RF[k].rn == r.rn && RF[k].keys == r.keys || error("Y-flip negative control $(x.id)")
        (RF[k].rn1 != r.rn1 || RF[k].rate != r.rate) || error("Y-flip did not change rn1/rate $(x.id)")   # codex I-R P1
        [x.lf.streams[x.lf.ex[t][1]].Y[x.lf.ex[t][2]+1] for t in 1:N] == x.Y || error("Y gate $(x.id)")
        J = seams83(x.lf); rw = routinewins(N, L83); length(rw) == 15 || error("routine windows $(x.id)")
        Ktot += length(x.S); Wtot += length(rw)
        seamset = Set{Int}(); for j in J, t in j:min(j + HEAD83 - 1, N); push!(seamset, t); end
        rset = Set{Int}(); for w in rw, t in w; push!(rset, t); end
        bix = sort!([t for t in rset if !(t in seamset)])
        bind = sort!([t for t in rset if !any(j -> 0 <= t - j < HEAD83, J)]); bind == bix || error("b membership gate $(x.id)")   # codex I-R P2
        aix = [t for i in x.S for t in (TS[i] + 1):(TS[i] + HEAD83)]
        cw = [j:(j + HEAD83 - 1) for j in J if j + HEAD83 - 1 <= N && !any(i -> !isempty(intersect(j:(j + HEAD83 - 1), formwin(i, L83))), 1:4)]
        cix = [t for w in cw for t in w]
        mb = isempty(bix) ? nothing : median(r.rn[bix])
        ra = (mb === nothing || mb == 0) ? "b" : isempty(aix) ? "a" : median(r.rn[aix]) / mb
        rc = (mb === nothing || mb == 0) ? "b" : isempty(cix) ? "c" : median(r.rn[cix]) / mb
        # (d) Y = 0 examples, formation (selected) and routine (no seam exclusion); by S81 pair group
        F4 = firemask("C4", (delta = 0.01,), H81, x.D); FO = BitVector([!isnan(x.so[t]) && x.so[t] > TH81 for t in 1:N])
        for i in x.S
            w = formwin(i, L83); g = (any(F4[w]) ? "C4" : "-") * "/" * (any(FO[w]) ? "O" : "-")
            before = length(get!(d0f, g, Float64[])); z = [t for t in w if !x.Y[t]]; append!(d0f[g], r.rn[z])
            length(d0f[g]) - before == count(!, view(x.Y, w)) || error("d formation count gate $(x.id) $i")   # codex I-R P3
        end
        before = length(d0r); append!(d0r, r.rn[[t for t in rset if !x.Y[t]]])
        length(d0r) - before == sum(count(!, view(x.Y, w)) for w in rw) || error("d routine count gate $(x.id)")
        # window means of w over 200-example chunks
        for i in x.S; push!(Wa, mean(ALPHA_R1 ./ (r.rn[(TS[i] + 1):(TS[i] + HEAD83)] .+ ALPHA_R1))); end
        for w in rw, c0 in first(w):HEAD83:last(w)
            ch = c0:(c0 + HEAD83 - 1); any(t -> t in seamset, ch) && continue
            push!(Wb, mean(ALPHA_R1 ./ (r.rn[ch] .+ ALPHA_R1)))
        end
        for i in setdiff(1:4, x.S); mb isa Number && mb > 0 && push!(aprime, (id = x.id, i = i, ra = median(r.rn[(TS[i] + 1):(TS[i] + HEAD83)]) / mb)); end
        push!(rows, (id = x.id, ra = ra, rc = rc, na = length(aix), nb = length(bix), nc = length(cix), nseam = length(J), ncw = length(cw),
                     ma = isempty(aix) ? nothing : median(r.rn[aix]), mb = mb, mc = isempty(cix) ? nothing : median(r.rn[cix])))
    end
    (Ktot, Wtot) == (183, 720) || error("K/W gate $Ktot $Wtot")
    println(io, "gate: 48 lives; replayed P bit-identical to saved P; recorded rn/rn1/rate rebuild P bit-identically at every example; Y-flip replay gives identical rn and keys; K = 183, W = 720")
    println(io, "== per life (rn at prediction time; medians)")
    for o in rows
        println(io, "  $(o.id): med a $(fm(o.ma)) (n $(o.na))  b $(fm(o.mb)) (n $(o.nb))  c $(fm(o.mc)) (n $(o.nc), seam windows $(o.ncw)/$(o.nseam))  r_a $(o.ra isa Number ? f4(o.ra) : "undef("*o.ra*")")  r_c $(o.rc isa Number ? f4(o.rc) : "undef("*o.rc*")")")
    end
    va = [o.ra for o in rows if o.ra isa Number]; vc = [o.rc for o in rows if o.rc isa Number]
    ua = [o.ra for o in rows if !(o.ra isa Number)]; uc = [o.rc for o in rows if !(o.rc isa Number)]
    println(io, "undefined: r_a $(length(ua)) (b: $(count(==("b"), ua)), a empty: $(count(==("a"), ua)))  r_c $(length(uc)) (b: $(count(==("b"), uc)), c empty: $(count(==("c"), uc)))")
    if isempty(va); k1 = "undecidable"; else
        fa = count(<=(0.1), va); k1 = (median(va) <= 0.1 && 10fa >= 9length(va)) ? "hit" : "miss"
        println(io, "K1: r_a median $(f4(median(va))), r_a <= 0.1 in $fa/$(length(va)) lives, quartiles $(q3(va)), min $(f4(minimum(va))) max $(f4(maximum(va))) -> $k1")
    end
    if isempty(vc); k2 = "undecidable"; else
        fc = count(x -> 0.5 <= x <= 2, vc); k2 = (10fc >= 9length(vc) && 2/3 <= median(vc) <= 3/2) ? "hit" : "miss"
        println(io, "K2: r_c median $(f4(median(vc))), 0.5 <= r_c <= 2 in $fc/$(length(vc)) lives (below 0.5: $(count(<(0.5), vc)), above 2: $(count(>(2), vc))), quartiles $(q3(vc)) -> $k2")
    end
    println(io, "S83-K1: $k1"); println(io, "S83-K2: $k2")
    println(io, "== descriptive (no prediction)")
    mx(v) = isempty(v) ? "-" : f4(maximum(v)); mn(v) = isempty(v) ? "-" : f4(minimum(v)); A = auc(Wa, Wb)   # codex I-R P6
    println(io, "  window mean w over 200 examples: formation heads (selected, n $(length(Wa))) q1/med/q3 $(q3(Wa)) min $(mn(Wa));  routine chunks without seam heads (n $(length(Wb))) $(q3(Wb)) max $(mx(Wb));  AUC $(A === nothing ? "-" : f4(A))")
    println(io, "  formation heads with w <= routine max: $(isempty(Wb) ? "-" : string(count(<=(maximum(Wb)), Wa)))/$(length(Wa))")
    for g in ["C4/O", "-/O", "C4/-", "-/-"]; get!(d0f, g, Float64[]); end
    for g in ["C4/O", "-/O", "C4/-", "-/-"]; println(io, "  (d) Y=0 in formation windows, pair group $g: n $(length(d0f[g])) rn q1/med/q3 $(q3(d0f[g]))"); end
    println(io, "  (d) Y=0 in routine windows: n $(length(d0r)) rn q1/med/q3 $(q3(d0r))")
    vap = [o.ra for o in aprime]; println(io, "  (a') unselected switches: n $(length(vap)) r_a q1/med/q3 $(q3(vap))$(isempty(vap) ? "" : " max $(f4(maximum(vap)))")")
    println(io, "note: seen lives only; descriptive. No clock or threshold is chosen here.")
    s = String(take!(io)); print(s); write(joinpath(OUT83, "key.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    run83()
end
