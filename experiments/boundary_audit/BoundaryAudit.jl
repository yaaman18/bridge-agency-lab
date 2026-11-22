# S62 r2 (discussion/specs/S62-aue-boundary-audit.md): the AUE boundary audit B-Test 1–4 on the canonical OneLife{LawL2}
# (core/one_life.jl, core/matter.jl), read only. Every probe works on deep copies; nothing here writes into core/ or
# into a run it does not own. The only re-written step is live_wrapped, a copy of core/one_life.jl `_live` with the
# law L2 constants and two hooks at the consumer of the motor output (block, replay); with no hook it is checked byte
# for byte against onelife_step (GB4). B-Test 1 reads the canonical `exclude_support_bijection` of
# ~/bridge-protocol/tools/verify/blanket_table.jl (include only, the file is not changed).
module BoundaryAudit

include(joinpath(@__DIR__, "..", "..", "core", "one_life.jl"))
include(expanduser("~/bridge-protocol/tools/verify/blanket_table.jl"))

export LawL2, OneLife, onelife_birth, onelife_step, onelife_encode, make_world, seed!, newborn, init, Mulberry, state_int32,
       FEATURES, g_sched, drive_A, drive_B, raise, birth40, mu_bytes, body_of, cellsets, closure1, perturb_A, far_state,
       live_wrapped, wrapped_step, b1_tables, b1_eval, B1_EXPECT, RW_TABLE, rw_audit, src_rng_audit

# ---------------------------------------------------------------- drives and the starting state

g_sched(t) = ((t ÷ 10) % 2 == 0) ? (5, 1) : (1, 5)          # S62 §2.3, t = the step index s.t
drive_A(k) = ((k ÷ 5) % 2 == 0) ? (5, 0) : (0, 5)           # k = 0..19 from s_40
drive_B(k) = ((k ÷ 5) % 2 == 0) ? (0, 5) : (5, 0)           # opposite phase

function raise(s::OneLife{LawL2}, n::Int)
    for _ in 1:n; s, err = onelife_step(s, g_sched(s.t)); err && error("drive error"); end
    return s
end
# Birth on a W×H torus with the canonical rules (onelife_birth with make_world(; W, H, reservoir = 300.0), founder
# at the centre); W = H = 24 is onelife_birth itself.
function birth_on(seed, W, H)
    W == 24 && H == 24 && return onelife_birth(seed, LawL2)
    w = make_world(; W = W, H = H, reservoir = 300.0); seed!(w, W ÷ 2, H ÷ 2, 1)
    perm = collect(1:length(FEATURES)); b = newborn(false; perm = copy(perm), extra = Int[])
    return OneLife{LawL2}(init(b), b, perm, state_int32(Mulberry(seed)), w, [0.0, 0.0], 0, false, nothing)
end
birth40(seed; W = 24, H = 24) = raise(birth_on(seed, W, H), 40)

# ---------------------------------------------------------------- the inner projection μ and the cell sets

body_of(s::OneLife) = [i for i in eachindex(s.w.C) if s.w.C[i] != 0]
# μ(s) = (circuit, pool, noise, C_body, {(i, A, B, C) | i ∈ C_body}); w.port.reservoir is not in μ (S62 §2.2).
function mu_bytes(s::OneLife)
    body = body_of(s); io = IOBuffer()
    _enc(io, s.circuit); _enc(io, s.pool); _enc(io, s.noise); _enc(io, body)
    for i in body; _enc(io, (i, s.w.A[i], s.w.B[i], s.w.C[i])); end
    return take!(io)
end
# The next state of a set of cells (A, B, C), for the outward probes.
far_state(s::OneLife, cells) = (io = IOBuffer(); for i in sort(collect(cells)); _enc(io, (i, s.w.A[i], s.w.B[i], s.w.C[i])); end; take!(io))

function nb4_once(w, S::Set{Int})
    R = copy(S); for x in S, m in 1:4; push!(R, w.nb4[m, x]); end; return R
end
# The one-step closure operator H(S) = S ∪ nb4³(S) ∪ ⋃_{x ∈ nb4³(S)} kIdx(x) (S62 §2.2).
function closure1(w, S::Set{Int})
    N3 = nb4_once(w, nb4_once(w, nb4_once(w, S)))
    R = copy(N3); for x in N3, m in 1:size(w.kIdx, 1); push!(R, w.kIdx[m, x]); end
    return R
end
function cellsets(w, C::Set{Int})
    all = Set(1:length(w.A))
    ring1 = setdiff(nb4_once(w, C), C)
    halo1 = setdiff(closure1(w, C), C)
    mid1 = setdiff(halo1, ring1)
    far1 = setdiff(all, union(C, halo1))
    halo2 = setdiff(closure1(w, closure1(w, C)), C)
    far2 = setdiff(all, union(C, halo2))
    return (C = C, ring1 = ring1, halo1 = halo1, mid1 = mid1, far1 = far1, halo2 = halo2, far2 = far2)
end
function perturb_A(s::OneLife, cells, dA::Float64)
    c = deepcopy(s); for j in cells; c.w.A[j] += dA; end; return c
end

# ---------------------------------------------------------------- the wrapped living step (GB4)

# core/one_life.jl `_live` for LawL2 (U = 0.02, MCOST = 0.004, KC = 0.002, bin3, IDLE, GATE, no SEDFADE), the same
# order and arithmetic. Hooks act only where the motor output is consumed: block = true drops the patch acts of m1, m2
# (P-04, the sending end); replay = (acting, d) consumes another arm's acts. The circuit update is never touched.
# Returns (state, info): info has the circuit's own output, what was consumed, the take, the payments and the port takes.
function live_wrapped(s::OneLife{L}, g; block::Bool = false, replay = nothing) where {L}
    U = 0.02; MCOST = 0.004; KC = 0.002
    c = deepcopy(s)
    circuit = c.circuit; b = c.b; w = c.w; pool = c.pool; noise = Mulberry(c.noise)
    y = [min(5.0, floor(r / U + 1e-9)) for r in pool]
    body = [i for i in eachindex(w.C) if w.C[i] != 0]
    out = step!(circuit, b, [y[1], y[2], 0.0]; noise = noise, contrast = :bin3, idle_first = true, core_gate = true,
                seen_both = false, sed_fade = false)
    acting = [b.patch[m] for m in out.acting if b.patch[m] <= 2]; d = out.d
    acting_c = copy(acting); d_c = copy(d)
    block && (acting = Int[])
    if replay !== nothing; acting = copy(replay[1]); d = copy(replay[2]); end
    nk = count(k -> circuit.q[k] >= 1 || circuit.sg[k] >= 1, eachindex(circuit.q))
    cost = KC * nk; paid = 0.0
    for i in body; m = min(w.B[i], cost / length(body)); w.B[i] -= m; paid += m; end
    port_give!(w.port, paid)
    paid_all = paid; taken = 0.0
    if !isempty(acting)
        for k in 1:2
            if d[k] > 0
                take = min(pool[k], d[k] * U); pool[k] -= take; taken += take
                for i in body; w.A[i] += take / length(body); end
            end
        end
        cost = MCOST * length(acting); paid = 0.0
        for i in body; m = min(w.B[i], cost / length(body)); w.B[i] -= m; paid += m; end
        port_give!(w.port, paid)
        paid_all += paid
    end
    got = [0.0, 0.0]
    for k in 1:2
        got[k] = port_take!(w.port, Float64(g[k]) * U); pool[k] += got[k]; over = pool[k] - 50 * U
        if over > 0; pool[k] -= over; port_give!(w.port, over); end
    end
    step!(w, ())
    info = (y = y, acting_c = acting_c, d_c = d_c, acting = copy(acting), d = copy(d), taken = taken, paid = paid_all, got = got)
    return OneLife{L}(circuit, b, c.perm, state_int32(noise), w, pool, c.t + 1, false, nothing), info
end
# The guards of onelife_step(::OneLife{LawL2}, g) around live_wrapped (info = nothing on the dead / detection paths).
function wrapped_step(s::OneLife{LawL2}, g; kw...)
    s.dead && return (deepcopy(s), nothing)
    _empty_body(s) && return (_detect(s), nothing)
    _drive_ok(g) || error("drive out of range")
    return live_wrapped(s, g; kw...)
end

# ---------------------------------------------------------------- B-Test 1: finite tables

xb(a, b) = string(xor(parse(Int, a), parse(Int, b)))
# Each table: exact integer weights over latent variables (Bern(1/4) = weights 3 : 1), mapped to (mu, eta, s, a);
# b = (s, a). Rows with the same (mu, eta, s, a) are summed.
function b1_tables()
    T = Dict{String,Vector{Dict{String,Any}}}()
    bit = ("0", "1"); bern = (("0", 3), ("1", 1))
    function table(gen)
        acc = Dict{NTuple{4,String},Int}()
        for (k, n) in gen; acc[k] = get(acc, k, 0) + n; end
        return [Dict{String,Any}("mu" => k[1], "eta" => k[2], "s" => k[3], "a" => k[4], "weight" => n) for (k, n) in sort(collect(acc))]
    end
    # 1. noisy chain η → b → μ: b = η ⊕ e1, μ = b ⊕ e2
    T["1 noisy chain"] = table(((m = xb(xb(h, e1), e2); (m, h, xb(h, e1), "0")), w1 * w2)
                               for h in bit for (e1, w1) in bern for (e2, w2) in bern)
    # 2. bijection μ = η = b
    T["2 bijection"] = table(((x, x, x, "0"), 1) for x in bit)
    # 3. BP7 functional dependence: b = (μ, z), η = μ ⊕ e
    T["3 BP7 b=(mu,z)"] = table(((m, xb(m, e), m, z), we) for m in bit for z in bit for (e, we) in bern)
    # 4. near copy: μ̃ = μ ⊕ f (δ = 1/4), b = (μ̃, z), η = μ̃ ⊕ e
    T["4 near copy"] = table(((m, xb(xb(m, f), e), xb(m, f), z), wf * we)
                             for m in bit for (f, wf) in bern for z in bit for (e, we) in bern)
    # 5. shared coordinate: μ = (Z, U), η = (Z, V), b = Z
    T["5 shared coordinate"] = table(((Z * U, Z * V, Z, "0"), 1) for Z in bit for U in bit for V in bit)
    # 6. deterministic readout: b = (η ⊕ e, z), μ = f(b) = the first coordinate of b
    T["6 deterministic readout"] = table(((xb(h, e), h, xb(h, e), z), we) for h in bit for (e, we) in bern for z in bit)
    return T
end
# The theory (BP7, D-BOUNDARY-OA-SYNTHESIS §2 B-Test 1): (CI, dependence, bijection excluded, exact copy, screen).
const B1_EXPECT = Dict(
    "1 noisy chain" => (true, true, false, false, true),
    "2 bijection" => (true, true, true, true, false),
    "3 BP7 b=(mu,z)" => (true, true, false, true, true),          # slips through the bijection exclusion
    "4 near copy" => (true, true, false, false, true),            # limit 1: slips through both
    "5 shared coordinate" => (true, true, false, false, true),    # limit 2: slips through both
    "6 deterministic readout" => (true, true, false, true, true)) # limit 3: the exact-copy flag rejects a readout

function condH(rows, target, given)
    joint = Dict{Tuple,Int}(); marg = Dict{Tuple,Int}(); tot = 0
    for r in rows
        kb = Tuple(r[k] for k in given); kt = (r[target], kb...); n = r["weight"]
        joint[kt] = get(joint, kt, 0) + n; marg[kb] = get(marg, kb, 0) + n; tot += n
    end
    H = 0.0
    for (kt, n) in joint; H -= n / tot * log2(n / marg[kt[2:end]]); end
    return (H = H, zero = length(joint) == length(marg))   # exact: H = 0 ⇔ |supp(target, b)| = |supp(b)|
end
function b1_eval(rows)
    r = BlanketTable.evaluate(rows)
    # own reading of exclude_support_bijection (cross-check of the canonical one)
    supp(ks) = length(unique(Tuple(row[k] for k in ks) for row in rows))
    own_mu = supp(("mu", "s", "a")) == supp(("s", "a")) == supp(("mu",))
    own_eta = supp(("eta", "s", "a")) == supp(("s", "a")) == supp(("eta",))
    hm = condH(rows, "mu", ("s", "a")); he = condH(rows, "eta", ("s", "a"))
    bij = r["blanket_copies_mu"] || r["blanket_copies_eta"]
    return (CI = r["conditional_independence"], dep = r["marginal_dependence"], bij = bij, exact = hm.zero || he.zero,
            screen = r["passes_statistical_screen"], own_bij_agrees = (own_mu == r["blanket_copies_mu"] && own_eta == r["blanket_copies_eta"]),
            Hmu_b = hm.H, Heta_b = he.H)
end

# ---------------------------------------------------------------- B-Test 3: the read/write table of one living step

# Declared from core/one_life.jl `_live` (lines 51-76) and core/matter.jl `step!` (lines 86-130). R = read, W = written.
const RW_TABLE = [
    ("1 y = quantize(pool)",            "R pool",                                         "W (local y)",                         "-"),
    ("2 body = {i | C[i] != 0}",        "R w.C",                                          "W (local body)",                      "-"),
    ("3 circuit step!",                 "R circuit, b, y, noise",                         "W circuit, noise",                    "noise (Mulberry): receptor feature \"noise\" only"),
    ("4 upkeep KC*nk",                  "R circuit.q, circuit.sg, w.B[body]",             "W w.B[body], w.port.reservoir/outflow", "-"),
    ("5 motor take (acting, d)",        "R acting, d, pool",                              "W pool, w.A[body]",                   "-"),
    ("6 motor cost MCOST",              "R acting, w.B[body]",                            "W w.B[body], w.port.reservoir/outflow", "-"),
    ("7 drive g: port_take!, overflow", "R g, w.port.reservoir, pool",                    "W pool, w.port.reservoir/inflow/outflow", "-"),
    ("8 matter step!(w, ())",           "R w.A, w.B, w.C, w.kIdx, w.kW, w.nb4, w.p",      "W w.A, w.B, w.C, w.P, w.out, w.scl, w.pi, w.pj, w.pf, w.port.reservoir/outflow, w.t, w.born, w.died", "none"),
    ("9 t + 1",                         "R t",                                            "W t",                                 "-")]
const RW_WRITES = Set(["circuit", "noise", "pool", "t", "w.A", "w.B", "w.C", "w.P", "w.out", "w.scl", "w.pi", "w.pj", "w.pf",
                       "w.port.reservoir", "w.port.inflow", "w.port.outflow", "w.t", "w.born", "w.died"])
const RW_READONLY = Set(["b", "perm", "w.p", "w.K", "w.kIdx", "w.kW", "w.nb4", "w.spontaneous", "w.port.scale", "w.port.unit",
                         "dead", "death"])
_bytes(x) = (io = IOBuffer(); _enc(io, x); take!(io))
function _fields(s::OneLife)
    F = Dict{String,Vector{UInt8}}()
    for f in (:circuit, :b, :perm, :noise, :pool, :t, :dead, :death); F[string(f)] = _bytes(something(getfield(s, f), -1)); end
    for f in fieldnames(World); f == :port && continue; F["w.$f"] = _bytes(getfield(s.w, f)); end
    for f in fieldnames(Port); F["w.port.$f"] = _bytes(getfield(s.w.port, f)); end
    return F
end
# One canonical step: the fields that changed, the undeclared writes, the read-only fields written, the input mutated.
function rw_audit(s::OneLife{LawL2}, g)
    before = onelife_encode(s); F0 = _fields(s)
    s1, _ = onelife_step(s, g); F1 = _fields(s1)
    changed = Set(k for k in keys(F0) if F0[k] != F1[k])
    return (changed = changed, undeclared = setdiff(changed, RW_WRITES), readonly_written = intersect(changed, RW_READONLY),
            unlisted = setdiff(Set(keys(F0)), union(RW_WRITES, RW_READONLY)), input_mutated = onelife_encode(s) != before)
end
# Static scan of the sources for random sources: matter.jl must have none; in one_life.jl `_live` the noise lines.
function src_rng_audit()
    root = joinpath(@__DIR__, "..", "..", "core")
    pat = r"Mulberry|rand\(|Random|noise"
    mat = [l for l in eachline(joinpath(root, "matter.jl")) if occursin(pat, l)]
    ol = readlines(joinpath(root, "one_life.jl"))
    a = findfirst(l -> startswith(l, "function _live("), ol); z = a + findfirst(l -> l == "end", ol[a:end]) - 1
    live_noise = [strip(l) for l in ol[a:z] if occursin(pat, l)]
    return (matter_hits = length(mat), live_noise = live_noise)
end

end
