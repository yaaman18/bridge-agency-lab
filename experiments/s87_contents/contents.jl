# S87 the same interface definition on different contents (discussion/specs/S87-draft-trace-across-contents.md; predictions frozen;
# codex S-R 2026-11-26 P1-P8, neon N1-N10; BP14 / H11; TRACE-1 r6 draft). Seen lives only; no new seeds; law numbers unchanged.
# Includes s84_np/np.jl unchanged (and through it s83/s80/s72 r1-r4); their main blocks do not run when included.
# usage: julia --project=. -t 8 experiments/s87_contents/contents.jl [smoke|run]
include(joinpath(@__DIR__, "..", "s84_np", "np.jl"))
using SHA, Serialization, Statistics
const PRED87 = joinpath(@__DIR__, "predictions.toml"); const OUT87 = joinpath(@__DIR__, "out"); mkpath(OUT87)
const FREEZE87 = joinpath(@__DIR__, "..", "freeze-s87.txt")
const GR87 = ("F", "R", "C"); const TABK = ("FGT", "CUM", "WIN")

# ---- one example / one block, with the outcome given explicitly (so a twin can flip it). Same expressions as s72r2/r4 update2!.
function upd!(L::TabL, k, a, y)
    if L.lam < 1; L.n .*= L.lam; L.n1 .*= L.lam; L.rn .*= L.lam; L.rn1 .*= L.lam; end
    L.n[a] += 1; L.n1[a] += y; L.rn[k] += 1; L.rn1[k] += y; return L
end
function upd!(L::WinL, k, a, y)
    push!(L.buf, (k, a, y)); L.n[a] += 1; L.n1[a] += y; L.rn[k] += 1; L.rn1[k] += y
    if length(L.buf) > WINLEN
        k0, a0, y0 = popfirst!(L.buf); L.n[a0] -= 1; L.n1[a0] -= y0; L.rn[k0] -= 1; L.rn1[k0] -= y0
    end
    return L
end
function updblock!(L::TrmL, tok, act, Y)            # = update2!(L::TrmL) with the block's outcomes Y given
    for c in eachindex(act)
        L.head = L.head % RING + 1
        L.ring_tok[:, L.head] .= tok[:, c]; L.ring_act[L.head] = act[c]; L.ring_Y[L.head] = Y[c]
        L.nring = min(L.nring + 1, RING)
    end
    L.nring < BATCH && return L
    w = get!(() -> TrmC0.WorkSet{Float32}(CFG_1X1.Lc + 1, ROPE...), task_local_storage(), :s72_ws)
    g = get!(() -> TrmC0.Params{Float32}(), task_local_storage(), :s72_g)
    bt = Matrix{UInt8}(undef, S, BATCH); ba = Vector{Int}(undef, BATCH); bY = Vector{Bool}(undef, BATCH)
    for b in 1:BATCH
        i = 1 + floor(Int, L.nring * L.r())
        bt[:, b] .= L.ring_tok[:, i]; ba[b] = L.ring_act[i]; bY[b] = L.ring_Y[i]
    end
    TrmC0.train_step!(L.p, g, L.o, w, CFG_1X1, bt, ba, bY, LR, 0.0; ce = CE)
    return L
end
struct Fix; end                                         # F0: reads nothing, predicts 1/2
learner87(kind, life) = kind == "F0" ? Fix() : kind == "WIN" ? new_learner4("WIN", life) : new_learner(kind, life)
fullhash(L) = (io = IOBuffer(); serialize(io, L); bytes2hex(sha256(take!(io))))

# ---- the field: example inputs, maps, probe Q
struct Field; lf; maps; K::Vector{Int}; A::Vector{Int}; Y::Vector{Bool}; seg::Vector{Int}; plf; N::Int; end
function field87(x)
    lf = x.lf; N = lf.N; maps, _ = life_maps(x.life); bounds = vcat(0, TS, N)
    K = zeros(Int, N); A = zeros(Int, N); Y = falses(N); sg = zeros(Int, N)
    for t in 1:N; si, s = lf.ex[t]; st = lf.streams[si]; sg[t] = searchsortedfirst(bounds, t) - 1
        A[t] = st.act[s+1]; Y[t] = st.Y[s+1]; K[t] = keyfor(st, s, A[t], maps[sg[t]]); end
    return Field(lf, maps, K, A, collect(Y), sg, probe_life(x.life), N)
end
# observation O_Q: predictions on the 400 probes under each of the 5 maps (2000 inputs, equal weight)
obsQ(L, F::Field) = vcat([predict2(deepcopy(L), F.plf, 1:F.plf.N, m) for m in F.maps]...)
obsQ(::Fix, F::Field) = fill(0.5, 5 * F.plf.N)
qkeys(F::Field) = vcat([[(st = F.plf.streams[i]; a = st.act[s+1]; keyfor(st, s, a, m)) for (i, s) in F.plf.ex] for m in F.maps]...)
dist(p, q) = (s = 0.0; for i in eachindex(p); s += abs(p[i] - q[i]); end; s / length(p))
tokblock(F::Field, t0, t1) = block_tok2(F.lf, t0:t1, F.maps[F.seg[t0]])

# advance a learner over examples (b0, t] (b0 block-aligned for TRM); flip = index whose outcome is replaced by 1-y (0: none)
function adv!(L::Union{TabL,WinL}, F::Field, b0, t; flip = 0, rec = nothing)
    for u in (b0 + 1):t; y = F.Y[u]; u == flip && (y = !y); rec === nothing || push!(rec, (u, F.K[u], F.A[u], y)); upd!(L, F.K[u], F.A[u], y); end; return L
end
adv!(L::Fix, F::Field, b0, t; flip = 0, rec = nothing) = L
function adv!(L::TrmL, F::Field, b0, t; flip = 0, rec = nothing)       # whole blocks only: (b0, al(t)]
    b0 % BLK == 0 || error("TRM start not block aligned $b0")
    for u0 in (b0 + 1):BLK:al(t)
        u1 = u0 + BLK - 1; F.seg[u0] == F.seg[u1] || error("block crosses a map switch $u0")
        tok, act, Y = tokblock(F, u0, u1); Yc = copy(Y)
        for (c, u) in enumerate(u0:u1); Yc[c] == F.Y[u] || error("Y field gate $u"); u == flip && (Yc[c] = !Yc[c]); end
        rec === nothing || for c in eachindex(act); push!(rec, (u0 + c - 1, hash(tok[:, c]), act[c], Yc[c])); end
        updblock!(L, tok, act, Yc)
    end
    return L
end
start87(::TrmL, t0) = al(t0)                            # TRM state between block ends = last block end (pending examples do not enter O)
start87(_, t0) = t0

# ---- main stream: block predictions (G1), states at starts, observations at read points
function main87(kind, x, F::Field, starts, reads, keep)
    L = learner87(kind, x.life); P = Float64[]; O = Dict{Int,Vector{Float64}}(); St = Dict{Int,Any}(); H = Dict{Int,String}()
    0 in reads && (O[0] = obsQ(L, F)); 0 in starts && (St[0] = deepcopy(L); H[0] = fullhash(L))
    for u0 in 1:BLK:F.N
        u1 = u0 + BLK - 1
        kind == "F0" || append!(P, predict2(L, F.lf, u0:u1, F.maps[F.seg[u0]]))
        if L isa TrmL
            adv!(L, F, u0 - 1, u1)
            for t in u0:u1
                t in reads && (h0 = statehash(L); O[t] = obsQ(L, F); statehash(L) == h0 || error("G7 probe changed TRM state $t"))
                (t in starts && t == u1) && (St[t] = deepcopy(L); H[t] = fullhash(L))
            end
        else
            for t in u0:u1
                adv!(L, F, t - 1, t)
                if t in reads
                    h0 = kind == "F0" ? "" : fullhash(L); O[t] = obsQ(L, F); kind == "F0" || fullhash(L) == h0 || error("G7 probe changed state $t")
                end
                t in starts && (St[t] = deepcopy(L); H[t] = fullhash(L))
                t in keep && (St[-t] = deepcopy(L))          # WIN: state at s+1000 for G6
            end
        end
    end
    return (P = P, O = O, St = St, H = H)
end

# origins: t0 -> list of h over groups F/R/C (union); groups per (t0, h)
function origins87(x, N)
    O = origins84(x); hs = Dict{Int,Set{Int}}(); grp = Dict{Tuple{String,Int},Vector{Int}}()
    for g in GR87, h in HS84
        grp[(g, h)] = O[(g, h)]
        for t0 in O[(g, h)]; push!(get!(hs, t0, Set{Int}()), h); end
    end
    return hs, grp
end

# twin from the main state at start87(t0): flip s = t0+1, follow to s+h, read O at s+h (S86 index rule; s+h must be in the life)
function twins87(kind, F::Field, M, t0, hs; flip = true, rec = nothing)
    Ls = M.St[kind == "TRM" ? al(t0) : t0]; L = deepcopy(Ls); b0 = start87(L, t0); s = t0 + 1
    if !(L isa Fix)
        fullhash(L) == M.H[b0] || error("G8 twin start state $kind $t0")
    end
    out = Dict{Int,Float64}(); cur = b0; st = Dict{Int,Any}()
    for h in sort(collect(hs))
        tr = s + h; tr <= F.N || (out[h] = NaN; continue)
        adv!(L, F, cur, tr; flip = flip ? s : 0, rec = rec); cur = L isa TrmL ? al(tr) : tr
        out[h] = dist(M.O[L isa TrmL ? al(tr) : tr], obsQ(L, F)); st[h] = deepcopy(L)
    end
    return out, st
end

function savedP(kind, x)
    kind == "FGT" && return x.P
    m = match(r"^st(\d) life (\d)$", x.id); m === nothing && return nothing
    f = joinpath(OUT4, "life$(m[1])_$(kind)_$(m[2]).jls"); isfile(f) || return nothing
    return deserialize(f).P
end

function life87(kind, x; tmax = typemax(Int), only = nothing)
    F = field87(x); N = min(F.N, tmax)
    hs, grp = origins87(x, F.N)
    t0s = sort([t for t in keys(hs) if t + 2 <= N && (only === nothing || t in only)])
    ndrop = only === nothing && tmax == typemax(Int) ? count(t -> t + 2 > N, keys(hs)) : 0      # I-R P4: origins dropped whole
    reads = Set{Int}([0]); starts = Set{Int}(); keep = Set{Int}()
    for t0 in t0s
        push!(starts, kind == "TRM" ? al(t0) : t0); push!(reads, kind == "TRM" ? al(t0) : t0)
        for h in hs[t0]
            for tr in (t0 + h, t0 + h + 1); tr <= F.N && push!(reads, kind == "TRM" ? al(tr) : tr); end
            (kind == "WIN" && h == 1000 && t0 + 1001 <= F.N) && push!(keep, t0 + 1001)
        end
    end
    Fc = Field(F.lf, F.maps, F.K, F.A, F.Y, F.seg, F.plf, N)
    M = main87(kind, x, Fc, starts, reads, keep)
    # G1 replay vs saved P (prefix if tmax)
    sp = savedP(kind, x); g1 = "none"
    if sp !== nothing && kind != "F0"
        n = length(M.P); all(i -> bits(M.P[i]) == bits(sp[i]), 1:n) || error("G1 replay $kind $(x.id)"); g1 = "ok($n)"
    end
    # G4 FGT observation = S84 table at Q keys
    if kind == "FGT"
        qk = qkeys(F); p = zeros(NK)
        for t in (0, (isempty(t0s) ? Int[] : [t0s[1]])...)
            L = t == 0 ? learner87("FGT", x.life) : M.St[t]; table!(p, L)
            sameb(obsQ(L, F), p[qk]) || error("G4 FGT O = table $t")
        end
    end
    rd(t) = kind == "TRM" ? al(t) : t
    rows = NamedTuple[]
    for t0 in t0s
        hh = Set(h for h in hs[t0] if t0 + 1 + h <= N)
        r1 = t0 == first(t0s) ? Any[] : nothing; r0 = t0 == first(t0s) ? Any[] : nothing
        D, st = twins87(kind, Fc, M, t0, hh; rec = r1)
        D0, st0 = twins87(kind, Fc, M, t0, hh; flip = false, rec = r0)      # G2 unflipped twin = main
        if r1 !== nothing && kind != "F0"                            # G3 (I-R P1): the inputs actually passed to upd!/updblock!
            (length(r1) == length(r0) && !isempty(r1)) || error("G3 input length $kind $t0")
            dif = [i for i in eachindex(r1) if r1[i] != r0[i]]
            (length(dif) == 1 && r1[dif[1]][1] == t0 + 1 && r1[dif[1]][4] == !r0[dif[1]][4] && r1[dif[1]][1:3] == r0[dif[1]][1:3]) || error("G3 input difference $kind $t0")
            all(i -> r0[i][4] == Fc.Y[r0[i][1]], eachindex(r0)) || error("G3 unflipped inputs = field $kind $t0")
        end
        for h in hh; D0[h] == 0 || error("G2 unflipped twin $kind $t0 $h"); end
        if kind == "WIN"                                            # G6 forgetting proof: state equal at s+1000
            for h in hh
                h == 1000 || continue
                D[h] == 0 || error("G6 WIN D(s+1000) $t0")
                Mw = M.St[-(t0 + 1001)]; Tw = st[h]
                (sameb(Mw.n, Tw.n) && sameb(Mw.n1, Tw.n1) && sameb(Mw.rn, Tw.rn) && sameb(Mw.rn1, Tw.rn1) && Mw.buf == Tw.buf) || error("G6 WIN state $t0")
            end
        end
        if kind == "F0"; all(v -> v == 0, values(D)) || error("G5 F0 D $t0"); end
        for h in hh
            isfinite(D[h]) || error("finite D gate $kind $t0 $h")      # I-R P8
            Nn = dist(M.O[rd(t0)], M.O[rd(t0 + h)]); Gd = dist(M.O[rd(t0 + h)], M.O[0])
            (isfinite(Nn) && isfinite(Gd)) || error("finite N/G gate $kind $t0 $h")
            kind == "F0" && (Nn == 0 && Gd == 0 || error("G5 F0 N/G $t0"))
            push!(rows, (t0 = t0, h = h, D = D[h], N = Nn, G = Gd, groups = [g for g in GR87 if t0 in grp[(g, h)]]))
        end
        for h in setdiff(hs[t0], hh); push!(rows, (t0 = t0, h = h, D = NaN, N = NaN, G = NaN, groups = [g for g in GR87 if t0 in grp[(g, h)]])); end
    end
    return (kind = kind, id = x.id, rows = rows, g1 = g1, ndrop = ndrop)
end

frozen87() = (h = bytes2hex(sha256(read(PRED87))); any(==("$h  experiments/s87_contents/predictions.toml"), split(read(FREEZE87, String), "\n")))

# smoke: gates only on short prefixes, no prediction quantities printed
function smoke87()
    frozen87() || error("predictions not frozen")
    LV = lives83(); length(LV) == 48 || error("48 lives")
    x = LV[findfirst(v -> v.id == "st2 life 1", LV)]; y = LV[end]
    out = String[]
    for k in ("FGT", "CUM", "WIN", "F0")
        for z in (x, y)
            r = life87(k, z; tmax = 12000, only = Set([TS[1]]))
            push!(out, "$k $(z.id): gates ok, G1 $(r.g1), rows $(length(r.rows))")
        end
    end
    r = life87("TRM", x; tmax = 9104, only = Set([TS[1]]))
    push!(out, "TRM $(x.id): gates ok, G1 $(r.g1), rows $(length(r.rows))")
    s = join(out, "\n"); println(s); write(joinpath(OUT87, "smoke.out"), s * "\n")
end

function run87()
    frozen87() || error("predictions not frozen")
    LV = lives83(); length(LV) == 48 || error("48 lives")
    TRMV = [LV[findfirst(v -> v.id == "st2 life $l", LV)] for l in 1:4]
    jobs = vcat([("TRM", x) for x in TRMV], [(k, x) for k in (TABK..., "F0") for x in LV])
    res = tmapv(j -> life87(j[1], j[2]), jobs)
    R = Dict((r.kind, r.id) => r for r in res)
    io = IOBuffer()
    println(io, "gate: G1 replay = saved S72 r4 P bitwise ($(join(sort(unique(["$(r.kind):$(r.g1)" for r in res if r.g1 != "none"])), ", ")) ...); G2 unflipped twin = main; G3 inputs passed to upd!/updblock! differ from the unflipped twin's only in the outcome at s (first origin of each life); G4 FGT O = S84 table at Q keys; G5 F0 all zero; G6 WIN state equal at s+1000; G7 probing leaves state unchanged; G8 twin start state = main (full serialization hash)")
    pool(k, g, h; ids = nothing) = [a for r in res if r.kind == k && (ids === nothing || r.id in ids) for a in r.rows if a.h == h && g in a.groups && !isnan(a.D)]
    nex(k, g, h) = count(a -> a.h == h && g in a.groups && isnan(a.D), vcat([r.rows for r in res if r.kind == k]...))
    tids = Set(x.id for x in TRMV)
    println(io, "origins dropped whole (t0+2 > N): $(sum(r.ndrop for r in res))")
    println(io, "== D_s(s+h) per content / group (pooled; q1 / median / q3; mean |dO| over Q, 2000 inputs)")
    for k in ("FGT", "CUM", "WIN", "TRM", "F0"), g in GR87, h in HS84
        v = pool(k, g, h); isempty(v) && continue
        println(io, "  $k $g h=$h: n $(length(v)) (excluded $(nex(k, g, h)))  D $(q3([a.D for a in v]))  D=0: $(count(a -> a.D == 0, v))  N $(q3([a.N for a in v]))  G $(q3([a.G for a in v]))")
    end
    println(io, "== same 4 TRM lives, tables for comparison")
    for k in ("FGT", "CUM"), g in GR87, h in HS84
        v = pool(k, g, h; ids = tids); isempty(v) && continue
        println(io, "  $k(4 lives) $g h=$h: n $(length(v))  D $(q3([a.D for a in v]))")
    end
    println(io, "== F vs R medians (description, N1/N8)")
    for k in ("FGT", "CUM", "TRM"), h in HS84
        f = [a.D for a in pool(k, "F", h)]; r = [a.D for a in pool(k, "R", h)]
        (isempty(f) || isempty(r)) && continue
        println(io, "  $k h=$h: F $(f4(median(f))) R $(f4(median(r)))  F>R: $(median(f) > median(r))")
    end
    # E1 CUM all > 0
    cu = [a for r in res if r.kind == "CUM" for a in r.rows if !isnan(a.D)]
    e1 = isempty(cu) ? "undecidable" : all(a -> a.D > 0, cu) ? "hit" : "miss"
    println(io, "E1: CUM D>0 at $(count(a -> a.D > 0, cu)) / $(length(cu)) (origin, h) -> $e1")
    # E2/E3 TRM, per origin
    tr = Dict{Tuple{String,Int},Dict{Int,Float64}}()
    for r in res; r.kind == "TRM" || continue; for a in r.rows; isnan(a.D) || (get!(tr, (r.id, a.t0), Dict{Int,Float64}())[a.h] = a.D); end; end
    both = [d for d in values(tr) if haskey(d, 50) && haskey(d, 1000)]
    lat = count(d -> d[50] == 0 && d[1000] > 0, both); z50 = count(d -> d[50] == 0, both)
    e2 = isempty(both) ? "undecidable" : lat >= 1 ? "hit" : "miss"
    d1000 = [d[1000] for d in values(tr) if haskey(d, 1000)]
    e3 = isempty(d1000) ? "undecidable" : any(>(0), d1000) ? "hit" : "miss"
    println(io, "E2: TRM origins readable at s+50 and s+1000: $(length(both)); D(s+50)=0: $z50; of those D(s+1000)>0: $lat -> $e2")
    println(io, "E3: TRM origins with D(s+1000)>0: $(count(>(0), d1000)) / $(length(d1000)) -> $e3")
    # E4 pairs (life, s) FGT vs CUM
    per(k) = (m = Dict{Tuple{String,Int},Dict{Int,Float64}}(); for r in res; r.kind == k || continue
        for a in r.rows; isnan(a.D) || (get!(m, (r.id, a.t0), Dict{Int,Float64}())[a.h] = a.D); end; end; m)
    PF = per("FGT"); PC = per("CUM"); allp = intersect(keys(PF), keys(PC))
    den = [p for p in allp if all(m -> haskey(m[p], 50) && haskey(m[p], 1000) && m[p][50] > 0, (PF, PC))]
    win = count(p -> PF[p][1000] / PF[p][50] < PC[p][1000] / PC[p][50], den)
    e4 = isempty(den) ? "undecidable" : win > length(den) / 2 ? "hit" : "miss"
    rf = [PF[p][1000] / PF[p][50] for p in den]; rc = [PC[p][1000] / PC[p][50] for p in den]
    println(io, "E4: pairs $(length(den)) (excluded $(length(allp) - length(den))); FGT ratio < CUM ratio: $win; ratio FGT $(q3(rf)) CUM $(q3(rc)) -> $e4")
    # E5 C vs R at h=200
    e5p = Dict{String,String}()
    for k in ("CUM", "TRM", "FGT")
        c = [a.D for a in pool(k, "C", 200)]; r = [a.D for a in pool(k, "R", 200)]
        e5p[k] = (isempty(c) || isempty(r)) ? "undecidable" : median(c) > median(r) ? "hit" : "miss"
        println(io, "E5 $k: median C $(isempty(c) ? "-" : f4(median(c))) (n $(length(c)))  R $(isempty(r) ? "-" : f4(median(r))) (n $(length(r))) -> $(e5p[k])$(k == "FGT" ? " (restatement of S86, not a prediction)" : "")")
    end
    e5 = e5p["CUM"] == "hit" && e5p["TRM"] == "hit" ? "hit" : any(k -> e5p[k] == "miss", ("CUM", "TRM")) ? "miss" : "undecidable"
    for (n, e) in (("E1", e1), ("E2", e2), ("E3", e3), ("E4", e4), ("E5", e5)); println(io, "S87-$n: $e"); end
    println(io, "note: seen lives only. O_Q is a lower approximation of the image: D>0 witnesses s < t; D=0 is not a proof of forgetting (only G6-type state equality is).")
    s = String(take!(io)); print(s); write(joinpath(OUT87, "contents.out"), s)
end
if abspath(PROGRAM_FILE) == @__FILE__
    (isempty(ARGS) || ARGS[1] == "run") ? run87() : ARGS[1] == "smoke" ? smoke87() : error("smoke|run")
end
