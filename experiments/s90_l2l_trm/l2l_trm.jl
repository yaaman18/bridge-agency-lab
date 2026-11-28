# S90 L2L-TRM minimal memory type on the seen S87 TRM lives (discussion/specs/S90-draft-l2l-trm-memory-type.md r2,
# discussion/specs/L2L-TRM-draft-memory-type.md r7; predictions frozen in predictions.toml / experiments/freeze-s90.txt).
# Includes s87_contents/contents.jl unchanged (and through it s84 / s83 / s72 / c0r_dev); its main block does not run when included.
# The [memory] contract is mem_core.jl (module S90MemCore). Seen lives st2 life 1..4 only; no new seeds; law numbers unchanged.
# smoke: gates only (GM1-GM5, G6-G8); no layer 1-3 quantity and no E1-E3 is computed. run: S90 r2 §4-§5.
# usage: julia --project=. -t 8 experiments/s90_l2l_trm/l2l_trm.jl [smoke|run]
include(joinpath(@__DIR__, "..", "s87_contents", "contents.jl"))
include(joinpath(@__DIR__, "mem_core.jl"))
const MC = S90MemCore
using Printf
const OUT90 = joinpath(@__DIR__, "out"); mkpath(OUT90)

# ---- capacities (S90 r2 §1.2) and the ample-balance body of the 4-life run
const CAPS90 = (("C0_B8", 8), ("C0_B9", 9), ("C1", 24), ("C2", 40), ("C130", 2088))
const L3CAPS = ("C0_B8", "C1", "C2", "C130")         # layer 3 / twins
const FINCAPS = ("C1", "C2", "C130")
const K_MEM90 = 0.002; const NMAX90 = 4; const DRAWSEED = 900100
const BODY90 = [1, 2, 3, 4]
# B_max and OPS_TRM_MIN are not frozen by S90 r2, and the offline TRM is not metered. OPS_TRM_MIN_OFF is a load-time
# placeholder; B_max leaves exactly OPS_MEM_WRITE_WORST after TRM, so the optional write always runs (ample ops, like the ample balance).
const OPS_TRM_MIN_OFF = 1
function cfg90(B)
    C = fld(B - 8, 16)
    return MC.load_memory_config(reserved_bytes = B, upkeep_rate_per_slot = K_MEM90, max_body_cells = NMAX90,
                                 max_read_ops_per_step = MC.OPS_MEM_READ_WORST(C),
                                 B_max = OPS_TRM_MIN_OFF + MC.OPS_MEM_MANDATORY(C, NMAX90) + MC.OPS_MEM_WRITE_WORST(C),
                                 ops_trm_min = OPS_TRM_MIN_OFF)
end
remops(cfg) = cfg.B_max - MC.OPS_MEM_MANDATORY(cfg) - cfg.ops_trm_min
b32(x::Float32) = reinterpret(UInt32, x)

# ---- discrete context key (L1 (a)): s == 0 -> 64, else bit i-1 = rbit(R1IDX[i]) of the receptor frame s-1. No action, no Y_s.
function ctx_key(st, s, m)
    s == 0 && return UInt64(64)
    k = UInt64(0)
    for i in 1:6
        rbit(st, m, R1IDX[i], s) && (k |= UInt64(1) << (i - 1))
    end
    return k
end
mutable struct KeyFn; st; s::Int; m; n::Int; end
(f::KeyFn)() = (f.n += 1; ctx_key(f.st, f.s, f.m))

# ---- per-step records of one capacity on one trajectory
mutable struct Rec
    t::Vector{Int}; p1::Vector{Float32}; p2::Vector{Float32}; pi1::Vector{Float32}; pi2::Vector{Float32}; ah::Vector{Int8}
    rs::Vector{UInt32}; ops::Vector{Int}; kc::Vector{Int}; zb::Vector{Bool}; key::Vector{UInt64}; hit::Vector{Bool}
    pon::Vector{Float32}; poff::Vector{Float32}; pion::Vector{Float32}; pioff::Vector{Float32}
    keep::Vector{Bool}; ev::Vector{Bool}; clr::Vector{Bool}; occ::Vector{Int}
end
Rec() = Rec((T() for T in fieldtypes(Rec))...)

# ---- G6(b) independent reference: a 130-cell table indexed by keyfor = 2k + a, with insertion stamps for FIFO order
mutable struct RefMem; C::Int; B::Int; occ::Vector{Bool}; y::Vector{UInt8}; stamp::Vector{Int}; clock::Int; end
RefMem(cfg) = RefMem(cfg.C, cfg.B, fill(false, 130), zeros(UInt8, 130), zeros(Int, 130), 0)
refi(k, a) = 2 * Int(k) + a
function refstep!(r::RefMem, k, a, y::Bool, p1t::Float32, p2t::Float32)
    q1 = r.occ[refi(k, 1)] ? 0.5f0 * (p1t + Float32(r.y[refi(k, 1)])) : p1t
    q2 = r.occ[refi(k, 2)] ? 0.5f0 * (p2t + Float32(r.y[refi(k, 2)])) : p2t
    pa = a == 1 ? q1 : q2; pt = a == 1 ? p1t : p2t; i = refi(k, a)
    if (y && pa < 0.5f0) || (!y && pa > 0.5f0)
        if r.occ[i]
            if (y && pt > 0.5f0) || (!y && pt < 0.5f0)
                r.occ[i] = false
            else
                r.clock += 1; r.stamp[i] = r.clock; r.y[i] = UInt8(y)
            end
        else
            if count(r.occ) == r.C
                j = 0
                for jj in 1:130; r.occ[jj] && (j == 0 || r.stamp[jj] < r.stamp[j]) && (j = jj); end
                r.occ[j] = false
            end
            r.clock += 1; r.occ[i] = true; r.stamp[i] = r.clock; r.y[i] = UInt8(y)
        end
    end
    return (q1, q2)
end
function refbytes(r::RefMem)
    buf = zeros(UInt8, r.B); idx = sort([i for i in 1:130 if r.occ[i]]; by = i -> r.stamp[i]); n = length(idx)
    for b in 0:3; buf[1+b] = UInt8((n >> (8b)) & 0xff); end
    for (j, i) in enumerate(idx)
        off = 8 + 16 * (j - 1); k = UInt64((i - 1) ÷ 2); a = i - 2 * Int(k)
        for b in 0:7; buf[off+1+b] = UInt8((k >> (8b)) & 0xff); end
        buf[off+9] = UInt8(a); buf[off+10] = r.y[i]
    end
    return buf
end

# ---- one capacity on one trajectory: memory M, its own draw stream Mulberry(DRAWSEED + life), optional reference
mutable struct CapRun; name::String; cfg::MC.MemoryConfig; M::MC.MemoryState; rng; ref; nev::Int; nclr::Int; end
newcap(name, B, life; ref = true) = (cfg = cfg90(B); CapRun(name, cfg, MC.MemoryState(), Mulberry(DRAWSEED + life),
                                                           (ref && cfg.C > 0) ? RefMem(cfg) : nothing, 0, 0))
snap(c::CapRun) = CapRun(c.name, c.cfg, copy(c.M), deepcopy(c.rng), deepcopy(c.ref), 0, 0)

# C_spec == 0: no ctx_key, no scan, memory cost exactly 0 (NC6 hook)
function mem_read_c0(cfg, M, kfn, p1, p2)
    return (p1, p2, 0)
end

# one step (r7 §3.1-§3.3): read, pi_u4, exactly one draw, then (C > 0) write + prepaid settle with the ample balance [1,1,1,1]
function capstep!(c::CapRun, r::Rec, t, p1t::Float32, p2t::Float32, kf::KeyFn, a::Int, y::Bool)
    cfg = c.cfg; n0 = kf.n
    hit = false; keep = false; ev = false; clr = false; k = UInt64(0); zb = true
    if cfg.C == 0
        p1, p2, ops = mem_read_c0(cfg, c.M, kf, p1t, p2t)
        zb = all(==(0x00), MC.serialize_memory(cfg, c.M))
    else
        k = kf()
        q = c.ref === nothing ? nothing : refstep!(c.ref, k, a, y, p1t, p2t)
        s = MC.memory_step!(cfg, c.M, () -> k, p1t, p2t, UInt8(a), UInt8(y), fill(1.0, NMAX90), BODY90, Ref(0.0);
                            remaining_ops = remops(cfg))
        p1, p2 = s.p1, s.p2
        ops = s.read_ops + s.write.ops + s.settle.ops
        (!s.write.skipped && !s.settle.dead && s.settle.upkeep_evicted == 0) || error("ample mode: write skipped or upkeep eviction $(c.name) t=$t")
        hit = a == 1 ? s.hit[1] : s.hit[2]; keep = s.write.miss; ev = s.write.evicted_d1; clr = s.write.cleared
        c.nev += ev; c.nclr += clr
        if q !== nothing
            (b32(q[1]) == b32(p1) && b32(q[2]) == b32(p2)) || error("G6(b) reference read $(c.name) t=$t")
            bytes2hex(sha256(refbytes(c.ref))) == MC.state_hash(cfg, c.M) || error("G6(b) reference state hash $(c.name) t=$t")
        end
    end
    pis = MC.pi_u4(p1, p2); ah = c.rng() < Float64(pis[1]) ? 1 : 2
    pio = MC.pi_u4(p1t, p2t)
    push!(r.t, t); push!(r.p1, p1); push!(r.p2, p2); push!(r.pi1, pis[1]); push!(r.pi2, pis[2]); push!(r.ah, ah)
    push!(r.rs, c.rng.s); push!(r.ops, ops); push!(r.kc, kf.n - n0); push!(r.zb, zb); push!(r.key, k); push!(r.hit, hit)
    push!(r.pon, a == 1 ? p1 : p2); push!(r.poff, a == 1 ? p1t : p2t); push!(r.pion, a == 1 ? pis[1] : pis[2])
    push!(r.pioff, a == 1 ? pio[1] : pio[2]); push!(r.keep, keep); push!(r.ev, ev); push!(r.clr, clr); push!(r.occ, length(c.M.slots))
    return r
end

# ---- the probe Q (S87: 400 probes x 5 maps): the probe's own action a_q and key k_q
function probe90(F::Field)
    qa = Int[]; qk = UInt64[]; qx = Tuple{Int,Int,Int}[]
    for (mi, m) in enumerate(F.maps), (i, s) in F.plf.ex
        st = F.plf.streams[i]; push!(qa, Int(st.act[s+1])); push!(qk, ctx_key(st, s, m)); push!(qx, (mi, i, s))
    end
    return (qa = qa, qk = qk, qx = qx)
end
# TRM probe predictions for both actions (2 x 2000, clipped Float64), same predict_set calls as S87 obsQ
obsT(L, F::Field) = hcat([(b = block_tok2(F.plf, 1:F.plf.N, m); r = predict_set(L.p, CFG_1X1, ExSet(-1, b[1], b[2], b[3], collect(1:F.plf.N)));
                           clip.(r.P[:, r.idx])) for m in F.maps]...)
obsT_g7(L, F) = (h0 = statehash(L); o = obsT(L, F); statehash(L) == h0 || error("G7 probe changed TRM state"); o)
obs64(Oq, pr) = [Oq[pr.qa[j], j] for j in eachindex(pr.qa)]              # = S87 obsQ (G8 Float64 path)
# composite observation on one capacity: both actions through R-MID, pi_u4, then the probe's own action (S90 r2 §2.4)
function obsM(c::CapRun, Oq::Matrix{Float64}, pr)
    h0 = MC.state_hash(c.cfg, c.M); n = size(Oq, 2)
    Op = Vector{Float32}(undef, n); Opi = Vector{Float32}(undef, n)
    for j in 1:n
        q1, q2, _ = MC.read_memory_pair(c.cfg, c.M, () -> pr.qk[j], Float32(Oq[1, j]), Float32(Oq[2, j]))
        pis = MC.pi_u4(q1, q2)
        Op[j] = pr.qa[j] == 1 ? q1 : q2; Opi[j] = pr.qa[j] == 1 ? pis[1] : pis[2]
    end
    MC.state_hash(c.cfg, c.M) == h0 || error("G7 probe changed M $(c.name)")
    return (p = Op, pi = Opi)
end
dist64(p, q) = (s = 0.0; for i in eachindex(p); s += abs(Float64(p[i]) - Float64(q[i])); end; s / length(p))

# ---- the TRM trace of one trajectory: both-action predictions per step (block start weights), probe matrices at reads
struct Trace; b0::Int; t1::Int; P::Matrix{Float64}; O::Dict{Int,Matrix{Float64}}; St::Dict{Int,Any}; LH::Vector{String}; end
function trm_trace!(L, F::Field, b0, t1; flips = Set{Int}(), reads = Set{Int}(), starts = Set{Int}(), hashes = false)
    (b0 % BLK == 0 && t1 % BLK == 0 && t1 >= b0) || error("trace not block aligned $b0 $t1")
    P = Matrix{Float64}(undef, 2, t1 - b0); O = Dict{Int,Matrix{Float64}}(); St = Dict{Int,Any}(); LH = String[]
    b0 in reads && (O[b0] = obsT_g7(L, F)); b0 in starts && (St[b0] = deepcopy(L))
    for u0 in (b0 + 1):BLK:t1
        u1 = u0 + BLK - 1; F.seg[u0] == F.seg[u1] || error("block crosses a map switch $u0")
        tok, act, Y = tokblock(F, u0, u1)
        Yc = copy(Y)                                              # the trajectory's own labels (flips applied) go to predict_set too
        for c in 1:BLK; (u0 + c - 1) in flips && (Yc[c] = !Yc[c]); end
        r = predict_set(L.p, CFG_1X1, ExSet(-1, tok, act, Yc, collect(u0:u1)))
        for c in 1:BLK
            u = u0 + c - 1
            (Y[c] == F.Y[u] && Int(act[c]) == F.A[u] && F.A[u] in (1, 2)) || error("field gate $u")
            P[1, u-b0] = clip(r.P[1, r.idx[c]]); P[2, u-b0] = clip(r.P[2, r.idx[c]])
        end
        updblock!(L, tok, act, Yc)
        u1 in reads && (O[u1] = obsT_g7(L, F)); u1 in starts && (St[u1] = deepcopy(L)); hashes && push!(LH, statehash(L))
    end
    return Trace(b0, t1, P, O, St, LH)
end
# the twin's own trace (NC5 hook: the cache key is (life, trajectory kind, time); a twin never reads the main's predictions)
function twin_trace(trm::Trace, trt::Trace)
    return trt
end

# ---- memory on a trace (cache sharing across capacities of the same (life, trajectory, time) only)
function mem_run!(caps, recs, tr::Trace, F::Field, pr; flips = Set{Int}(), reads = Set{Int}(), starts = Set{Int}(), Os = Dict{Int,Any}(),
                  snaps = Dict{Int,Any}())
    b0 = tr.b0
    b0 in reads && (Os[b0] = [obsM(c, tr.O[b0], pr) for c in caps]); b0 in starts && (snaps[b0] = snap.(caps))
    for t in (b0 + 1):tr.t1
        si, s = F.lf.ex[t]; st = F.lf.streams[si]; m = F.maps[F.seg[t]]
        kf = KeyFn(st, s, m, 0); p1t = Float32(tr.P[1, t-b0]); p2t = Float32(tr.P[2, t-b0]); y = F.Y[t] ⊻ (t in flips)
        for i in eachindex(caps); capstep!(caps[i], recs[i], t, p1t, p2t, kf, F.A[t], y); end
        t in starts && (snaps[t] = snap.(caps))
        t in reads && (Os[t] = [obsM(c, tr.O[t], pr) for c in caps])
    end
    return Os
end

# ---- origins (S87 origins87, same t0s / h sets as life87)
function setup90(x; tmax = typemax(Int), only = nothing)
    F = field87(x); N = min(F.N, tmax); hs, grp = origins87(x, F.N)
    t0s = sort([t for t in keys(hs) if t + 2 <= N && (only === nothing || t in only)])
    hh = Dict(t0 => Set(h for h in hs[t0] if t0 + 1 + h <= N) for t0 in t0s)
    return (x = x, F = F, N = N, hs = hs, grp = grp, t0s = t0s, hh = hh, pr = probe90(F))
end
function main90(S; caps = CAPS90, hashes = false, ref = true, N = S.N)
    reads = Set([0]); starts = Set{Int}()
    for t0 in S.t0s
        al(t0) <= N || continue
        push!(starts, al(t0)); push!(reads, al(t0))
        for h in S.hh[t0], tr in (t0 + h, t0 + 1 + h); tr <= N && push!(reads, al(tr)); end
    end
    tr = trm_trace!(learner87("TRM", S.x.life), S.F, 0, N; reads, starts, hashes)
    cs = [newcap(n, B, S.x.life; ref) for (n, B) in caps]; rs = [Rec() for _ in cs]; Os = Dict{Int,Any}(); snaps = Dict{Int,Any}()
    mem_run!(cs, rs, tr, S.F, S.pr; reads, starts, Os, snaps)
    return (tr = tr, caps = cs, recs = rs, Os = Os, snaps = snaps, names = [c.name for c in cs], N = N)
end
capidx(mn, name) = findfirst(==(name), mn.names)
function twin90(S, mn, t0; keeprecs = false, audit = true)
    hh = S.hh[t0]; s = t0 + 1; b0 = al(t0); t1 = al(s + maximum(hh)); reads = Set(al(s + h) for h in hh)
    trt = twin_trace(mn.tr, trm_trace!(deepcopy(mn.tr.St[b0]), S.F, b0, t1; flips = Set([s]), reads))
    idx = [capidx(mn, n) for n in L3CAPS]
    cs = [snap(mn.snaps[b0][i]) for i in idx]; rs = [Rec() for _ in cs]; Os = Dict{Int,Any}()
    mem_run!(cs, rs, trt, S.F, S.pr; flips = Set([s]), reads, Os)
    audit && gate_g6a(S, rs[2:end])
    Dp = Dict{String,Dict{Int,Float64}}(); Dpi = Dict{String,Dict{Int,Float64}}(); D64 = Dict{Int,Float64}()
    for (j, n) in enumerate(L3CAPS)
        Dp[n] = Dict(h => dist64(mn.Os[al(s + h)][idx[j]].p, Os[al(s + h)][j].p) for h in hh)
        Dpi[n] = Dict(h => dist64(mn.Os[al(s + h)][idx[j]].pi, Os[al(s + h)][j].pi) for h in hh)
    end
    O = mn.tr.O
    D64 = Dict(h => dist(obs64(O[al(s + h)], S.pr), obs64(trt.O[al(s + h)], S.pr)) for h in hh)
    N64 = Dict(h => dist(obs64(O[al(t0)], S.pr), obs64(O[al(t0 + h)], S.pr)) for h in hh)
    G64 = Dict(h => dist(obs64(O[al(t0 + h)], S.pr), obs64(O[0], S.pr)) for h in hh)
    keep = Dict(n => rs[j].keep[s-b0] for (j, n) in enumerate(L3CAPS))
    nev = Dict(n => cs[j].nev for (j, n) in enumerate(L3CAPS))
    return (t0 = t0, b0 = b0, t1 = t1, hh = hh, Dp = Dp, Dpi = Dpi, D64 = D64, N64 = N64, G64 = G64, keep = keep, nev = nev,
            recs = keeprecs ? rs : nothing, Os = keeprecs ? Os : nothing, reads = reads)
end

# ================================================================ gates on lives
# GM2 reference: existing TrmL (S87 predict2 / adv!) + U4 pi + exactly one draw per step; the other action through predict_set
function base_ref(S, tmax)
    F = S.F; L = learner87("TRM", S.x.life); rng = Mulberry(DRAWSEED + S.x.life)
    p64 = Matrix{Float64}(undef, 2, tmax); p = Matrix{Float32}(undef, 2, tmax); pis = Matrix{Float32}(undef, 2, tmax)
    ah = zeros(Int8, tmax); rs = zeros(UInt32, tmax); LH = String[]
    for u0 in 1:BLK:tmax
        u1 = u0 + BLK - 1; m = F.maps[F.seg[u0]]
        pa = predict2(L, F.lf, u0:u1, m)
        tok, act, Y = tokblock(F, u0, u1)
        po = clip.(predict_set(L.p, CFG_1X1, ExSet(-1, tok, Int8.(3 .- act), Y, collect(u0:u1))).p)
        for c in 1:BLK
            u = u0 + c - 1; a = F.A[u]
            p64[a, u] = pa[c]; p64[3-a, u] = po[c]
            p[1, u] = Float32(p64[1, u]); p[2, u] = Float32(p64[2, u])
            q = MC.pi_u4(p[1, u], p[2, u]); pis[1, u] = q[1]; pis[2, u] = q[2]
            ah[u] = rng() < Float64(q[1]) ? 1 : 2; rs[u] = rng.s
        end
        adv!(L, F, u0 - 1, u1)
        push!(LH, statehash(L))
    end
    return (p64 = p64, p = p, pi = pis, ah = ah, rs = rs, LH = LH)
end
function gate_gm2(S, mn, tmax)
    b = base_ref(S, tmax); n = 0
    mn.tr.LH[1:(tmax ÷ BLK)] == b.LH || error("GM2 TrmL state hash differs from the reference")
    for name in ("C0_B8", "C0_B9")
        r = mn.recs[capidx(mn, name)]
        for u in 1:tmax
            ok = r.t[u] == u && b32(r.p1[u]) == b32(b.p[1, u]) && b32(r.p2[u]) == b32(b.p[2, u]) &&
                 b32(r.pi1[u]) == b32(b.pi[1, u]) && b32(r.pi2[u]) == b32(b.pi[2, u]) && r.ah[u] == b.ah[u] && r.rs[u] == b.rs[u] &&
                 r.ops[u] == 0 && r.kc[u] == 0 && r.zb[u]
            ok || error("GM2 $name differs from the reference at t=$u (p/pi/draw/rng/ops/ctx_key/zero bytes)")
            n += 1
        end
    end
    length(MC.serialize_memory(mn.caps[capidx(mn, "C0_B9")].cfg, MC.MemoryState())) == 9 || error("GM2 C0_B9 buffer length")
    return (steps = tmax, checks = n, blocks = tmax ÷ BLK, ref = b)
end

# threaded map in index order; a job's error is rethrown unwrapped, the first failing index first (deterministic)
function tmap90(f, xs)
    out = Vector{Any}(undef, length(xs))
    Threads.@threads for i in eachindex(xs)
        out[i] = try; (true, f(xs[i])); catch e; (false, e); end
    end
    for o in out; o[1] || throw(o[2]); end
    return [o[2] for o in out]
end

# GM3 (a) flip only Y_t; (b) flip Y_{t+1..} for in-block positions 1..7. Window 1 = the first n examples (S90 r2 §3). In S87 the
# TrmL does not train while nring < BATCH, so on window 1 the TRM p is exactly 1/2 and R1 never writes (an empty test of the read
# order, NC4). Window 2 (added, same checks): n2 consecutive examples after nring >= BATCH, every step with TRM p != 1/2 for the
# taken action, ending at or after the first real R1 write of every C > 0 capacity; each C > 0 capacity must write in a branch.
# Window 2 is located with the G6(b) reference table (RefMem), not with the memory code under test.
function gate_gm3(S; n = 50, posts = vcat(17:23, 41:47), n2 = 50, Tl = 256)
    F = S.F; life = S.x.life; ncmp = 0
    trl = trm_trace!(learner87("TRM", life), F, 0, Tl)
    pa(t) = trl.P[F.A[t], t]
    tw0 = findfirst(t -> pa(t) != 0.5, 1:Tl); tw0 === nothing && error("GM3 no step with TRM p != 1/2 in 1..$Tl")
    tw0 > n || error("GM3 window 1 overlaps the training range t=$tw0")
    fw = Union{Int,Nothing}[]
    for (nm, B) in CAPS90
        cfg = cfg90(B); cfg.C == 0 && continue
        r = RefMem(cfg); f = nothing
        for t in 1:Tl
            si, s = F.lf.ex[t]; y = F.Y[t]; a = F.A[t]
            q = refstep!(r, ctx_key(F.lf.streams[si], s, F.maps[F.seg[t]]), a, y, Float32(trl.P[1, t]), Float32(trl.P[2, t]))
            f === nothing && t >= tw0 && ((y && q[a] < 0.5f0) || (!y && q[a] > 0.5f0)) && (f = t)
        end
        push!(fw, f)
    end
    any(isnothing, fw) && error("GM3 no R1 write after t=$tw0 in 1..$Tl")
    w1 = max(tw0 + n2 - 1, maximum(fw)); W2 = (w1 - n2 + 1):w1
    w1 + 3 * BLK <= Tl || error("GM3 window 2 beyond 1..$Tl")
    all(t -> pa(t) != 0.5, W2) || error("GM3 window 2 has a step with TRM p == 1/2")
    b = BLK * cld(first(W2) - 1, BLK); posts2 = vcat((b + 1):(b + 7), (b + BLK + 1):(b + BLK + 7))
    last(posts2) <= w1 || error("GM3 window 2 shorter than two blocks")
    ts = vcat(1:n, W2)
    tf = tmap90(t -> trm_trace!(learner87("TRM", life), F, 0, al(t - 1) + BLK; flips = Set([t])), ts)
    for (j, t) in enumerate(ts)
        (trl.P[1, t] === tf[j].P[1, t] && trl.P[2, t] === tf[j].P[2, t]) || error("GM3(a) TRM prediction depends on Y_t t=$t")
    end
    cs = [newcap(nm, B, life; ref = false) for (nm, B) in CAPS90]; tset = Set(ts)
    nw = Dict(c.name => [0, 0] for c in cs)                     # window 2: [steps written in the Y_t or flipped branch, real writes]
    for t in 1:w1
        si, s = F.lf.ex[t]; st = F.lf.streams[si]; m = F.maps[F.seg[t]]
        p1t = Float32(trl.P[1, t]); p2t = Float32(trl.P[2, t])
        alt = t in tset ? snap.(cs) : nothing
        for i in eachindex(cs)
            r1 = capstep!(cs[i], Rec(), t, p1t, p2t, KeyFn(st, s, m, 0), F.A[t], F.Y[t])
            alt === nothing && continue
            r2 = capstep!(alt[i], Rec(), t, p1t, p2t, KeyFn(st, s, m, 0), F.A[t], !F.Y[t])
            (b32(r1.p1[1]) == b32(r2.p1[1]) && b32(r1.p2[1]) == b32(r2.p2[1]) && b32(r1.pi1[1]) == b32(r2.pi1[1]) &&
             b32(r1.pi2[1]) == b32(r2.pi2[1]) && r1.ah[1] == r2.ah[1]) || error("GM3(a) step-t output depends on Y_t $(cs[i].name) t=$t")
            ncmp += 1
            t in W2 && (nw[cs[i].name][1] += r1.keep[1] || r2.keep[1]; nw[cs[i].name][2] += r1.keep[1])
        end
    end
    for c in cs
        c.cfg.C == 0 && continue
        (nw[c.name][1] > 0 && nw[c.name][2] > 0) || error("GM3 window 2 without a write $(c.name) $(nw[c.name])")
    end
    allposts = vcat(posts, posts2)
    nb = tmap90(allposts) do t
        T = BLK * cld(t, BLK) + 2 * BLK; fl = Set((t + 1):T); k = 0
        tA = trm_trace!(learner87("TRM", life), F, 0, T); tB = trm_trace!(learner87("TRM", life), F, 0, T; flips = fl)
        cA = [newcap(nm, B, life; ref = false) for (nm, B) in CAPS90]; cB = [newcap(nm, B, life; ref = false) for (nm, B) in CAPS90]
        rA = [Rec() for _ in cA]; rB = [Rec() for _ in cB]
        mem_run!(cA, rA, tA, F, S.pr); mem_run!(cB, rB, tB, F, S.pr; flips = fl)
        for i in eachindex(cA), u in 1:t
            (b32(rA[i].p1[u]) == b32(rB[i].p1[u]) && b32(rA[i].p2[u]) == b32(rB[i].p2[u]) && b32(rA[i].pi1[u]) == b32(rB[i].pi1[u]) &&
             b32(rA[i].pi2[u]) == b32(rB[i].pi2[u]) && rA[i].ah[u] == rB[i].ah[u]) || error("GM3(b) prefix differs $(cA[i].name) t=$t u=$u")
            k += 1
        end
        k
    end
    ncmp += sum(nb)
    return (a = n, b = length(posts), positions = sort(unique(mod1.(posts, BLK))), checks = ncmp, tw0 = tw0, W2 = W2, posts2 = posts2,
            positions2 = sort(unique(mod1.(posts2, BLK))), nw = [(c.name, nw[c.name]...) for c in cs if c.cfg.C > 0])
end

# G6(a) external audit (not part of the memory op count): 2 ctx_key + a == keyfor for both actions, steps and probes
function gate_g6a(S, recsets)
    F = S.F; n = 0
    for r in recsets, j in eachindex(r.t)
        t = r.t[j]; si, s = F.lf.ex[t]; st = F.lf.streams[si]; m = F.maps[F.seg[t]]
        for a in 1:2; 2 * Int(r.key[j]) + a == keyfor(st, s, a, m) || error("G6(a) ctx_key audit t=$t a=$a"); n += 1; end
    end
    for (j, (mi, i, s)) in enumerate(S.pr.qx)
        st = F.plf.streams[i]; m = F.maps[mi]
        for a in 1:2; 2 * Int(S.pr.qk[j]) + a == keyfor(st, s, a, m) || error("G6(a) probe ctx_key audit j=$j a=$a"); n += 1; end
        S.pr.qk[j] == ctx_key(st, s, m) || error("G6(a) probe key recomputation j=$j")
    end
    return n
end

# G6(d) one capacity, no cache: its own TrmL from scratch, step by step, own probe composite
function indep_run(cfg, S, tend; flip = 0, reads = Set{Int}())
    F = S.F; L = learner87("TRM", S.x.life); M = MC.MemoryState(); rng = Mulberry(DRAWSEED + S.x.life)
    p1 = zeros(Float32, tend); p2 = zeros(Float32, tend); q1 = zeros(Float32, tend); q2 = zeros(Float32, tend); ah = zeros(Int8, tend)
    O = Dict{Int,Any}()
    function obs()
        Op = Float32[]; Opi = Float32[]
        for m in F.maps
            tok, act, Y = block_tok2(F.plf, 1:F.plf.N, m)
            r = predict_set(L.p, CFG_1X1, ExSet(-1, tok, act, Y, collect(1:F.plf.N)))
            for c in 1:F.plf.N
                i, s = F.plf.ex[c]; st = F.plf.streams[i]; a = Int(st.act[s+1])
                q = MC.read_memory_pair(cfg, M, () -> ctx_key(st, s, m), Float32(clip(r.P[1, r.idx[c]])), Float32(clip(r.P[2, r.idx[c]])))
                pis = MC.pi_u4(q[1], q[2]); push!(Op, a == 1 ? q[1] : q[2]); push!(Opi, a == 1 ? pis[1] : pis[2])
            end
        end
        return (p = Op, pi = Opi)
    end
    0 in reads && (O[0] = obs())
    for u0 in 1:BLK:tend
        u1 = u0 + BLK - 1; m = F.maps[F.seg[u0]]
        tok, act, Y = block_tok2(F.lf, u0:u1, m)
        Yc = [Y[c] ⊻ (u0 + c - 1 == flip) for c in 1:BLK]        # flipped labels before predict_set (as trm_trace!)
        r = predict_set(L.p, CFG_1X1, ExSet(-1, tok, act, Yc, collect(u0:u1)))
        for c in 1:BLK
            u = u0 + c - 1; si, s = F.lf.ex[u]; st = F.lf.streams[si]
            y = Yc[c]
            o = MC.memory_step!(cfg, M, () -> ctx_key(st, s, m), Float32(clip(r.P[1, r.idx[c]])), Float32(clip(r.P[2, r.idx[c]])),
                                UInt8(act[c]), UInt8(y), fill(1.0, NMAX90), BODY90, Ref(0.0); remaining_ops = remops(cfg))
            pis = MC.pi_u4(o.p1, o.p2)
            p1[u] = o.p1; p2[u] = o.p2; q1[u] = pis[1]; q2[u] = pis[2]; ah[u] = rng() < Float64(pis[1]) ? 1 : 2
        end
        updblock!(L, tok, act, Yc)
        u1 in reads && (O[u1] = obs())
    end
    return (p1 = p1, p2 = p2, pi1 = q1, pi2 = q2, ah = ah, O = O)
end
function cmp_indep(name, r::Rec, ir, O, iO, ts, reads)
    for (j, t) in enumerate(r.t)
        t in ts || continue
        (b32(r.p1[j]) == b32(ir.p1[t]) && b32(r.p2[j]) == b32(ir.p2[t]) && b32(r.pi1[j]) == b32(ir.pi1[t]) &&
         b32(r.pi2[j]) == b32(ir.pi2[t]) && r.ah[j] == ir.ah[t]) || error("G6(d) $name step t=$t differs from the uncached independent run")
    end
    for t in reads
        (all(b32.(O[t].p) .== b32.(iO[t].p)) && all(b32.(O[t].pi) .== b32.(iO[t].pi))) || error("G6(d) $name obsQ at $t differs from the uncached independent run")
    end
    return length(ts)
end
function main_reads(mn); return Set(keys(mn.Os)); end
# the independent runs are threaded (each owns its TrmL, M and draw stream; results do not depend on the thread count);
# check_main = false skips the main trajectory's runs (NC5 mutates only the twin path)
function gate_g6d(S, mn, tw; names = ("C1", "C130"), check_main::Bool = true)
    n = 0; s = tw.t0 + 1; rd = main_reads(mn)
    jobs = [(name, main) for name in names for main in (check_main ? (true, false) : (false,))]
    irs = tmap90(jobs) do (name, main)
        cfg = mn.caps[capidx(mn, name)].cfg
        main ? indep_run(cfg, S, mn.N; reads = rd) : indep_run(cfg, S, tw.t1; flip = s, reads = tw.reads)
    end
    for ((name, main), ir) in zip(jobs, irs)
        ci = capidx(mn, name); j = findfirst(==(name), L3CAPS)
        n += main ? cmp_indep("$name main", mn.recs[ci], ir, Dict(t => mn.Os[t][ci] for t in rd), ir.O, 1:mn.N, rd) :
                    cmp_indep("$name twin t0=$(tw.t0)", tw.recs[j], ir, Dict(t => tw.Os[t][j] for t in tw.reads), ir.O, (tw.b0 + 1):tw.t1, tw.reads)
    end
    return n
end

# G6(c): C130 never D1-evicts (main and every twin)
gate_g6c(mn, tws) = (e = mn.caps[capidx(mn, "C130")].nev + sum(Int[tw.nev["C130"] for tw in tws]; init = 0);
                     e == 0 || error("G6(c) C130 D1 evictions $e"); e)

# G8 rows on the C0_B8 Float64 path, built as life87 builds its TRM rows
function rows64(S, tws)
    T = Dict(tw.t0 => tw for tw in tws); rows = NamedTuple[]
    for t0 in S.t0s
        hh = S.hh[t0]
        for h in hh
            tw = T[t0]; push!(rows, (t0 = t0, h = h, D = tw.D64[h], N = tw.N64[h], G = tw.G64[h], groups = [g for g in GR87 if t0 in S.grp[(g, h)]]))
        end
        for h in setdiff(S.hs[t0], hh); push!(rows, (t0 = t0, h = h, D = NaN, N = NaN, G = NaN, groups = [g for g in GR87 if t0 in S.grp[(g, h)]])); end
    end
    return rows
end
sameNaN(a, b) = (isnan(a) && isnan(b)) || bits(a) == bits(b)

# the gate battery on st2 life 1 (S90 r2 §3); the smoke prefix is tmax = 9104, only = TS[1]
function smoke_gates(io, LV)
    x = LV[findfirst(v -> v.id == "st2 life 1", LV)]
    t = time(); S = setup90(x; tmax = 9104, only = Set([TS[1]]))
    # GM3 and the S87 life87 recomputation do not read the main trajectory: they run as tasks alongside it
    k3 = Threads.@spawn (ta = time(); (gate_gm3(S), time() - ta))
    k87 = Threads.@spawn (tb = time(); (life87("TRM", x; tmax = 9104, only = Set([TS[1]])), time() - tb))
    mn = main90(S; hashes = true); tm = time() - t
    t = time(); tws = [twin90(S, mn, t0; keeprecs = true) for t0 in S.t0s if !isempty(S.hh[t0])]; tt = time() - t
    length(tws) == 1 && tws[1].t0 == TS[1] || error("smoke twin set")
    g = gate_gm2(S, mn, mn.N)
    println(io, "PASS GM2 C0_B8 / C0_B9 = reference (existing TrmL + U4 pi + 1 draw/step) on st2 life 1 1..$(g.steps): ",
            "p1 p2 pi1 pi2 a_hat rng state, memory ops 0, ctx_key calls 0, C0_B9 9-byte buffer all 0x00 at every step; TrmL hash at $(g.blocks) block ends ($(g.checks) step checks)")
    g3, t3 = fetch(k3)
    println(io, "PASS GM3 (a) Y_t flip, first $(g3.a) examples x 5 capacities: step-t (p, pi, a_hat) and TRM p bit-identical; ",
            "(b) Y_{t+1..} flip at $(g3.b) positions (in-block positions $(join(g3.positions, ",")) covered): common prefix 1..t bit-identical; ",
            "window 2 (TRM p == 1/2 for t < $(g3.tw0)) t=$(first(g3.W2))..$(last(g3.W2)): (a) same x 5 capacities, R1 writes [Y_t or flipped branch, real] ",
            join(["$(a) $(b)/$(c)" for (a, b, c) in g3.nw], ", "), "; (b) at t=$(join(g3.posts2, ",")) (in-block positions $(join(g3.positions2, ","))) ($(g3.checks) checks)")
    fin = [mn.recs[capidx(mn, n)] for n in FINCAPS]
    na = gate_g6a(S, vcat(fin, [tw.recs[j] for tw in tws for j in 2:4]))
    println(io, "PASS G6(a) external audit 2*ctx_key + a == keyfor for both actions: $na checks (steps of C1/C2/C130 main + twin, 2000 probes)")
    println(io, "PASS G6(b) independent reference table: per-step read bits and SHA-256 of the serialized M identical, unique (k,a) invariant ",
            "(C1/C2/C130, main $(mn.N) steps + twin t0=$(TS[1]) $(tws[1].t1 - tws[1].b0) steps)")
    e = gate_g6c(mn, tws)
    println(io, "PASS G6(c) C130 D1 evictions main + twin = $e")
    nd = gate_g6d(S, mn, tws[1])
    println(io, "PASS G6(d) C1 / C130, main and twin t0=$(TS[1]): uncached independent TrmL runs bit-identical in (p, pi, a_hat) at $nd steps and obsQ at all read points")
    println(io, "PASS G7 probes non-destructive: TrmL statehash and SHA-256 of M unchanged at every obsQ (main $(length(mn.Os)) read points x 5 capacities, twin $(length(tws[1].reads)) x 4)")
    # G8 smoke: S87 read-only recomputation
    r87, t87 = fetch(k87)
    b = g.ref
    all(u -> bits(b.p64[1, u]) == bits(mn.tr.P[1, u]) && bits(b.p64[2, u]) == bits(mn.tr.P[2, u]), 1:mn.N) ||
        error("G8 smoke (p1, p2) Float64 differs from the S87 recomputation")
    my = rows64(S, tws)
    key(r) = (r.t0, r.h)
    length(my) == length(r87.rows) || error("G8 smoke row count $(length(my)) vs S87 $(length(r87.rows))")
    A = Dict(key(r) => r for r in r87.rows)
    for r in my
        q = get(A, key(r), nothing); q === nothing && error("G8 smoke row $(key(r)) missing in S87")
        (sameNaN(r.D, q.D) && sameNaN(r.N, q.N) && sameNaN(r.G, q.G) && r.groups == q.groups) || error("G8 smoke D/N/G differ at $(key(r))")
    end
    println(io, "PASS G8 smoke: C0_B8 Float64 (p1, p2) = S87 read-only recomputation at $(mn.N) steps (both actions); ",
            "D, N, G of $(length(my)) TRM rows (t0=$(TS[1])) bit-identical to life87 (S87 G1 $(r87.g1))")
    return (S = S, mn = mn, tws = tws, tm = tm, tt = tt, t87 = t87, t3 = t3)
end

function smoke90()
    t00 = time(); io = stdout
    MC.frozen90(); println(io, "PASS G7 frozen90: 3 SHA-256 match experiments/freeze-s90.txt")
    MC.self_test()
    LV = lives83(); length(LV) == 48 || error("48 lives")
    r = smoke_gates(io, LV)
    println(io, "ALL GATES PASS (GM1-GM5, G6(a)-(d), G7, G8 smoke). No layer 1-3 quantity and no E1-E3 computed in smoke.")
    @printf(io, "time: main (5 capacities, %d steps) %.0f s, twin %.0f s, GM3 %.0f s and S87 life87 recomputation %.0f s (tasks alongside the main), total %.0f s, threads %d\n",
            r.mn.N, r.tm, r.tt, r.t3, r.t87, time() - t00, Threads.nthreads())
end

# ================================================================ run (S90 r2 §4-§5); not executed before the independent I-R
g6(x) = @sprintf("%.6g", x)
q3g(v) = isempty(v) ? "-" : "$(g6(quantile(v, 0.25))) / $(g6(median(v))) / $(g6(quantile(v, 0.75)))"
mean0(v) = isempty(v) ? NaN : mean(v)
strat90(t) = t <= FLEN ? "init" : any(i -> TS[i] < t <= TS[i] + FLEN, 1:4) ? "switch" : "steady"
brier(p, y) = (Float64(p) - (y ? 1.0 : 0.0))^2
acc(p, y) = y ? p > 0.5f0 : p < 0.5f0

function g8run(io, Ss, TW)
    lines = filter(l -> occursin(r"^  TRM [FRC] h=", l), readlines(joinpath(OUT87, "contents.out")))
    length(lines) == 9 || error("G8 run: contents.out has $(length(lines)) TRM group rows, expected 9")
    rows = vcat([rows64(Ss[i], TW[i]) for i in eachindex(Ss)]...)
    mine = String[]
    for g in GR87, h in HS84
        v = [a for a in rows if a.h == h && g in a.groups && !isnan(a.D)]; isempty(v) && continue
        nex = count(a -> a.h == h && g in a.groups && isnan(a.D), rows)
        push!(mine, "  TRM $g h=$h: n $(length(v)) (excluded $nex)  D $(q3([a.D for a in v]))  D=0: $(count(a -> a.D == 0, v))  N $(q3([a.N for a in v]))  G $(q3([a.G for a in v]))")
    end
    length(mine) == 9 || error("G8 run: $(length(mine)) TRM group rows computed, expected 9")
    mine == lines || error("G8 run: TRM rows differ from contents.out\n" * join(mine, "\n"))
    println(io, "PASS G8 run: C0_B8 Float64 TRM rows (D, N, G quartiles, n, excluded, D=0) = contents.out, 9 / 9 (raw TRM row count 9)")
end

# gate priority (S90 r2 §5.1): the NC log counts only if it ends with the all-failed line and records the SHA-256 of the
# 3 implementation files exactly once each, all equal to the files now on disk; returns nothing or the reason
const NCFILES = ("mem_core.jl", "l2l_trm.jl", "neg_controls.jl")
function nc_log_check(lines; dir = @__DIR__)
    (!isempty(lines) && last(lines) == "negative controls: all 7 failed at their intended gates") || return "last line is not the all-failed line"
    for f in NCFILES
        h = [m[1] for m in (match(Regex("^sha256 " * replace(f, "." => "\\.") * " ([0-9a-f]{64})\$"), l) for l in lines) if m !== nothing]
        length(h) == 1 || return "sha256 $f recorded $(length(h)) times"
        h[1] == bytes2hex(open(sha256, joinpath(dir, f))) || return "sha256 $f differs from the file on disk"
    end
    return nothing
end

function run90()
    t00 = time(); io = IOBuffer(); gates_ok = true; msg = ""
    tee(s) = (println(io, s); println(s))
    res = nothing
    try
        MC.frozen90(); MC.self_test()
        ncf = joinpath(OUT90, "neg_controls.out")
        isfile(ncf) || error("NC1-NC7: out/neg_controls.out missing")
        ncr = nc_log_check(readlines(ncf)); ncr === nothing || error("NC1-NC7 (out/neg_controls.out): $ncr")
        tee("PASS GM1 GM2-unit GM4 GM5 (mem_core self_test); NC1-NC7 failed at their intended gates (out/neg_controls.out, SHA-256 of $(join(NCFILES, " / ")) = files on disk)")
        LV = lives83(); length(LV) == 48 || error("48 lives")
        sb = IOBuffer(); smoke_gates(sb, LV); tee(String(take!(sb)))
        TRMV = [LV[findfirst(v -> v.id == "st2 life $l", LV)] for l in 1:4]
        Ss = [setup90(x) for x in TRMV]
        MN = tmapv(S -> main90(S), Ss)
        jobs = [(i, t0) for i in eachindex(Ss) for t0 in Ss[i].t0s if !isempty(Ss[i].hh[t0])]
        TWf = tmapv(j -> twin90(Ss[j[1]], MN[j[1]], j[2]), jobs)
        TW = [[TWf[k] for k in eachindex(jobs) if jobs[k][1] == i] for i in eachindex(Ss)]
        # gates on the 4 lives
        na = sum(gate_g6a(Ss[i], [MN[i].recs[capidx(MN[i], n)] for n in FINCAPS]) for i in eachindex(Ss))
        tee("PASS G6(a) 4 lives main C1/C2/C130 + probes: $na key checks (twins audited in twin90); G6(b) reference identical on main and all $(length(jobs)) twins")
        ne = sum(gate_g6c(MN[i], TW[i]) for i in eachindex(Ss)); tee("PASS G6(c) C130 D1 evictions (4 lives, main + all twins) = $ne")
        for i in eachindex(Ss)
            r8 = MN[i].recs[capidx(MN[i], "C0_B8")]; r9 = MN[i].recs[capidx(MN[i], "C0_B9")]
            all(f -> getfield(r8, f) == getfield(r9, f), (:p1, :p2, :pi1, :pi2, :ah, :rs, :ops, :kc, :zb)) || error("GM2 C0_B9 != C0_B8 on $(Ss[i].x.id)")
            all(r9.zb) && all(==(0), r9.ops) && all(==(0), r9.kc) || error("GM2 C0_B9 zero bytes / ops on $(Ss[i].x.id)")
            gate_gm2(Ss[i], main90(Ss[i]; caps = CAPS90[1:2], hashes = true, N = 9104), 9104)
        end
        for i in eachindex(Ss)
            r8 = MN[i].recs[capidx(MN[i], "C0_B8")]; c8 = MN[i].caps[capidx(MN[i], "C0_B8")]
            (all(j -> brier(r8.pon[j], Ss[i].F.Y[r8.t[j]]) - brier(r8.poff[j], Ss[i].F.Y[r8.t[j]]) == 0.0, eachindex(r8.t)) && c8.nev == 0 && c8.nclr == 0 &&
             !any(r8.ev) && !any(r8.clr) && all(==(0), r8.occ)) || error("C0_B8 all steps: Brier diff / D1 evictions / clears / |M| not all 0 on $(Ss[i].x.id)")
        end
        tee("PASS C0_B8 all steps 1..N of the 4 lives: Brier diff == 0.0 at every step, D1 evictions 0, K-UNIQ-CLEAR clears 0, |M| == 0 at every step")
        tee("PASS GM2 C0_B9 short-range check: C0_B9 = C0_B8 bitwise over each full life (p, pi, a_hat, rng, ops 0, ctx_key 0, 9 zero bytes); both = reference on 1..9104 of each of the 4 lives")
        g8run(io, Ss, TW); println("PASS G8 run")
        res = (Ss = Ss, MN = MN, TW = TW)
    catch e
        gates_ok = false; msg = sprint(showerror, e)
    end
    if !gates_ok
        tee("GATE FAILURE: $(first(msg, 400))")
        tee("S90-E1: miss\nS90-E2: undecidable\nS90-E3: undecidable\n(gate priority rule S90 r2 §5.1)")
        write(joinpath(OUT90, "l2l_trm.out"), String(take!(io))); exit(1)
    end
    Ss, MN, TW = res.Ss, res.MN, res.TW
    ids = [S.x.id for S in Ss]
    # ---- layer 1 / layer 2 on the main trajectory of the 4 lives
    E1ok = true; e3 = "undecidable"
    tee("== layer 1 (wiring check; not evidence of superiority) and layer 2 (Brier on R_hit(C)); Float32 path; 4 lives pooled by step")
    for n in FINCAPS
        hitsets = [(i, j) for i in eachindex(Ss) for j in findall(MN[i].recs[capidx(MN[i], n)].hit)]
        R(i) = MN[i].recs[capidx(MN[i], n)]
        nall = sum(length(R(i).t) for i in eachindex(Ss))
        dpi = [abs(Float64(R(i).pion[j]) - Float64(R(i).pioff[j])) for (i, j) in hitsets]
        dp = [abs(Float64(R(i).pon[j]) - Float64(R(i).poff[j])) for (i, j) in hitsets]
        Yof(i, j) = Ss[i].F.Y[R(i).t[j]]
        dB = [brier(R(i).pon[j], Yof(i, j)) - brier(R(i).poff[j], Yof(i, j)) for (i, j) in hitsets]
        aon = mean0([acc(R(i).pon[j], Yof(i, j)) for (i, j) in hitsets]); aoff = mean0([acc(R(i).poff[j], Yof(i, j)) for (i, j) in hitsets])
        cr = mean0([(Float64(R(i).poff[j]) - 0.5) * (Float64(R(i).pon[j]) - 0.5) < 0 for (i, j) in hitsets])
        perlife = join(["$(ids[i]) $(count(R(i).hit))" for i in eachindex(Ss)], ", ")
        tee("L1 $n: |R_hit| $(length(hitsets)) of $nall steps (requery rate $(g6(length(hitsets) / nall)); $perlife)  mean dpi $(g6(mean0(dpi)))  mean dp $(g6(mean0(dp)))  dp>0 & dpi==0: $(count(k -> dp[k] > 0 && dpi[k] == 0, eachindex(dp)))")
        for i in eachindex(Ss)
            hs_ = findall(R(i).hit)
            tee("    $(ids[i]): |R_hit| $(length(hs_))  mean dpi $(g6(mean0([abs(Float64(R(i).pion[j]) - Float64(R(i).pioff[j])) for j in hs_])))  mean dp $(g6(mean0([abs(Float64(R(i).pon[j]) - Float64(R(i).poff[j])) for j in hs_])))")
        end
        tee("L2 $n: mean dBrier $(g6(mean0(dB)))  q1/med/q3 $(q3g(dB))  acc_ON - acc_OFF $(g6(aon - aoff))  1/2 crossing rate $(g6(cr))")
        for z in ("init", "switch", "steady")
            k = [q for q in eachindex(hitsets) if strat90(R(hitsets[q][1]).t[hitsets[q][2]]) == z]
            tee("    $z: |R_hit| $(length(k))  mean dBrier $(g6(mean0(dB[k])))")
        end
        if isempty(hitsets); E1ok = false; tee("    E1 note: |R_hit($n)| == 0, wiring effect undecidable for $n")
        elseif !(mean(dpi) > 0); E1ok = false; end
        n == "C130" && (e3 = isempty(dB) ? "undecidable" : mean(dB) > 0 ? "hit" : "miss")
    end
    # layer 2 descriptive on all steps 1..N, all 4 capacities (S90 r2 §4.2); C0_B8 is checked to be all 0 in the gates above
    tee("== layer 2 all steps 1..N, all 4 capacities (descriptive; 4 lives pooled by step)")
    for n in L3CAPS
        R(i) = MN[i].recs[capidx(MN[i], n)]
        allB = [brier(R(i).pon[j], Ss[i].F.Y[R(i).t[j]]) - brier(R(i).poff[j], Ss[i].F.Y[R(i).t[j]]) for i in eachindex(Ss) for j in eachindex(R(i).t)]
        tee("L2 all $n: mean Brier diff $(g6(mean(allB)))  D1 evictions $(sum(MN[i].caps[capidx(MN[i], n)].nev for i in eachindex(Ss)))  K-UNIQ-CLEAR clears $(sum(MN[i].caps[capidx(MN[i], n)].nclr for i in eachindex(Ss)))  |M| q1/med/q3 $(q3g(Float64.(vcat([R(i).occ for i in eachindex(Ss)]...))))")
    end
    # ---- layer 3: twins, S_common(h) unique (life, t0) with weight 1, all 4 capacities finite, no selection on keep / requery
    tee("== layer 3 (type-internal twins, Float32 path for all capacities; dD_C = D_s(C) - D_s(C0_B8) on S_common(h), 4 lives pooled, weight 1 per (life, t0))")
    e2 = "undecidable"
    for h in HS84
        Sc = [(i, tw) for i in eachindex(Ss) for tw in TW[i] if h in tw.hh && tw.t0 + 1 + h <= Ss[i].N &&
              all(n -> isfinite(tw.Dp[n][h]) && isfinite(tw.Dpi[n][h]), L3CAPS)]
        tee("L3 h=$h: |S_common| $(length(Sc))")
        for n in FINCAPS
            dDp = [tw.Dp[n][h] - tw.Dp["C0_B8"][h] for (_, tw) in Sc]; dDpi = [tw.Dpi[n][h] - tw.Dpi["C0_B8"][h] for (_, tw) in Sc]
            tee("  $n: mean dD^p $(g6(mean0(dDp)))  mean dD^pi $(g6(mean0(dDpi)))  dD^pi q1/med/q3 $(q3g(dDpi))")
            for i in eachindex(Ss)
                k = [q for q in eachindex(Sc) if Sc[q][1] == i]
                tee("    $(ids[i]): n $(length(k))  mean dD^p $(g6(mean0(dDp[k])))  mean dD^pi $(g6(mean0(dDpi[k])))")
            end
            for g in GR87
                k = [q for q in eachindex(Sc) if Sc[q][2].t0 in Ss[Sc[q][1]].grp[(g, h)]]
                tee("    group $g: n $(length(k))  mean dD^p $(g6(mean0(dDp[k])))  mean dD^pi $(g6(mean0(dDpi[k])))")
            end
            mk(q) = MN[Sc[q][1]].recs[capidx(MN[Sc[q][1]], n)].keep[Sc[q][2].t0 + 1]
            for (z, f) in (("main keep", q -> mk(q)), ("twin keep", q -> !mk(q) && Sc[q][2].keep[n]), ("neither", q -> !mk(q) && !Sc[q][2].keep[n]))
                k = [q for q in eachindex(Sc) if f(q)]
                tee("    origin s $z: n $(length(k))  mean dD^p $(g6(mean0(dDp[k])))  mean dD^pi $(g6(mean0(dDpi[k])))")
            end
            # requery correspondence: main R_hit steps in (s, al(s+h)] and their layer-1 dpi
            nh = Int[]; md = Float64[]
            for (i, tw) in Sc
                r = MN[i].recs[capidx(MN[i], n)]; s = tw.t0 + 1; js = [j for j in (s + 1):al(s + h) if r.hit[j]]
                push!(nh, length(js)); isempty(js) || push!(md, mean(abs(Float64(r.pion[j]) - Float64(r.pioff[j])) for j in js))
            end
            tee("    requery in (s, al(s+h)] on main: origins with >=1 hit $(count(>(0), nh)) / $(length(nh))  hits per origin q1/med/q3 $(q3g(Float64.(nh)))  mean layer-1 dpi there $(g6(mean0(md)))")
        end
        if h == 1000 && !isempty(Sc)
            a = mean(tw.Dpi["C130"][h] - tw.Dpi["C0_B8"][h] for (_, tw) in Sc); b = mean(tw.Dp["C130"][h] - tw.Dp["C0_B8"][h] for (_, tw) in Sc)
            e2 = a > 0 && b > 0 ? "hit" : "miss"
        end
    end
    e1 = E1ok ? "hit" : "miss"
    tee("S90-E1: $e1\nS90-E2: $e2\nS90-E3: $e3")
    tee("note: seen lives only; capacities are all reported, none is adopted (#89). Layer 1 is a wiring check only. phenomenal_claim = :not_certified.")
    @printf(io, "time: %.0f s, threads %d\n", time() - t00, Threads.nthreads())
    write(joinpath(OUT90, "l2l_trm.out"), String(take!(io)))
end

if abspath(PROGRAM_FILE) == @__FILE__
    (isempty(ARGS) || ARGS[1] == "smoke") ? smoke90() : ARGS[1] == "run" ? run90() : error("smoke|run")
end
