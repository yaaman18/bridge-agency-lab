# S62b r2 gates GB1–GB5 (discussion/specs/S62b-aue-boundary-audit.md §3; predictions experiments/predictions-boundary-audit-b.md).
# A strict diff of experiments/boundary_audit/run_gates.jl (S62 r2): new seeds, the GB2(5) port fixture, the GB4c identified
# pair fixture, the signed Live > Yoke condition inside GB4b, and the SHA-256 check of the parent S62 files in GB5.
# Usage (from the lab root): julia --project=. experiments/boundary_audit_b/run_gates.jl       evaluation seeds 986..1005,
#                                                                                           writes experiments/results-boundary-audit-b.out
#                            julia --project=. experiments/boundary_audit_b/run_gates.jl dev   development seeds 982..985, stdout only
#                            ... run_gates.jl --readonly                                    evaluation seeds, stdout only
# Exit code 0 only when every gate passes. The perturbation family is declared here before the run (S62 §2.2, P-11):
# ΔA ∈ {0.05, 0.20, 0.45} added to w.A of every cell of the target set at once (set-wise) and, for the sets that must not
# leak (far1, far2), also to each cell alone (cell-wise); the internal (outward) family is noise ⊻ 1, circuit q = sg = 0,
# pool + 5U. A leak is any byte of μ (S62 §2.2) that differs from the unperturbed run. No git command is called.
include(joinpath(@__DIR__, "BoundaryAuditB.jl"))
using .BoundaryAuditB
using .BoundaryAuditB.BoundaryAudit
using Printf
using SHA

const BA = BoundaryAuditB.BoundaryAudit
const DEV = !isempty(ARGS) && ARGS[1] == "dev"
const READONLY = "--readonly" in ARGS
const SEEDS = DEV ? collect(982:985) : collect(986:1005)
const NS = length(SEEDS)
const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const OUT = joinpath(ROOT, "experiments", "results-boundary-audit-b.out")
const FREEZE = joinpath(ROOT, "experiments", "freeze-boundary-audit-b.txt")
const DAS = (0.05, 0.20, 0.45)
const MAJ = NS ÷ 2 + 1                  # GB4b majority: 11 of the 20 evaluation seeds
const RES_FLOOR = 300.0 - 40 * 0.20   # S62b §1.2: the reservoir at s_40 is >= 292.0 (300.0 at birth, at most 10U per step)
# sha256 of the parent S62 r2 files (GB5, read only)
const PARENT_SHA = [
    "BoundaryAudit.jl" => "af289ecd1c51f38309d5530e86127e778c415f348577c3c1a66df16d29f9d513",
    "run_gates.jl" => "0d7964e977fd4c183976d747721b33ab799f253242ece9518b14b7d4f3625046",
]
# sha256 of core/*.jl at bbdb1c2 (GB5 checks these without git)
const CORE_SHA = [
    "LabCore.jl" => "2a687291b52d9d158bdb971e4feb333377fb4a918937bfe67b9d5d0748ade21c",
    "body_org.jl" => "022e3699e91b19eea24d93d94df061036b1bc4f50a07aeec90ab0bb7e595e942",
    "circuit.jl" => "295a6e17b4d99f90a67961187911ca36270d199b5806a9acbe4be4d8a20d1473",
    "dc.jl" => "05eb8b60c1640f87fe65172f5630945166bc1760a782a66a14e298b16af946a0",
    "evo.jl" => "f0f1fbd98c00218e5d4acb0f4d80ebe0db94caef67cdde3d4f7ab5dc58360e38",
    "jsmath.jl" => "65cc0230ada6e88d91a527d30dc9660fb6da265cd4e3cd7bc0e7aebb109090b1",
    "life.jl" => "b2673155459badb225c5e8666a95f223bb00ca47c3b5fa4e934de95e64037011",
    "matter.jl" => "00e14d20a41e9d647ec5901b0cc4ae4f9fd8d7276d7013efdc5a76ad3c9c73ca",
    "one_life.jl" => "c61c5a2152e47c9bb8555e4ed91e815255ebbf2560bf456d6faa1f9943fb6044",
]

fmt(x::Float64) = @sprintf("%.6f", x)
seedlist(s) = isempty(s) ? "{}" : "{" * join(s, ",") * "}"
frac(n) = "$n/$NS"
step1(s) = first(onelife_step(s, g_sched(s.t)))
step2(s) = step1(step1(s))
# Leaks of μ after nsteps from a perturbed copy of s (set-wise over DAS, and cell-wise if asked).
function leaks(s, cells, base_mu, nsteps; cellwise = false)
    run(p) = nsteps == 1 ? step1(p) : step2(p)
    n = 0
    for dA in DAS
        mu_bytes(run(perturb_A(s, cells, dA))) != base_mu && (n += 1)
        if cellwise
            for j in sort(collect(cells)); mu_bytes(run(perturb_A(s, (j,), dA))) != base_mu && (n += 1); end
        end
    end
    return n
end
taken_in(s0, s1) = s1.w.port.inflow - s0.w.port.inflow

# ---------------------------------------------------------------- GB1

function gate1(L)
    T = b1_tables(); ok = 0
    push!(L, "  case | CI dep bij_excluded exact_copy screen | H(mu|b) H(eta|b) | expected | match")
    for k in sort(collect(keys(T)))
        r = b1_eval(T[k]); got = (r.CI, r.dep, r.bij, r.exact, r.screen); e = B1_EXPECT[k]
        m = got == e && r.own_bij_agrees; m && (ok += 1)
        push!(L, "  $k | $(join(got, " ")) | $(fmt(r.Hmu_b)) $(fmt(r.Heta_b)) | $(join(e, " ")) | $m (own bijection reading agrees: $(r.own_bij_agrees))")
    end
    push!(L, "  matched $ok/6 (screen = passes_statistical_screen is a necessary-condition diagnostic only, not a boundary certificate)")
    return ok == 6
end

# ---------------------------------------------------------------- GB2

function sizes_line(tag, S40, S39)
    "$(tag) |C40|=$(length(S40.C)) |halo1|=$(length(S40.halo1)) (ring1 $(length(S40.ring1)), mid1 $(length(S40.mid1))) |far1|=$(length(S40.far1)) | |C39|=$(length(S39.C)) |halo2|=$(length(S39.halo2)) |far2|=$(length(S39.far2))"
end

function gate2(L)
    alive = 0; far1pos = 0; naive = 0; shell_in = 0; take_mis = 0; outward = 0; eff = zeros(Int, 3)
    ring1rm = 0; mid1rm = 0; portrm = 0; port_pool = 0; portex = ""; paidmax = -Inf; pdmin = Inf
    f2pos24 = 0; f2leak24 = 0; f2pos40 = 0; f2leak40 = 0; res40diff = 0
    sz24 = Set{String}(); sz40 = Set{String}()
    for seed in SEEDS
        s39 = BA.raise(BA.birth_on(seed, 24, 24), 39); s40 = step1(s39)
        (!s40.dead && !isempty(body_of(s40))) && (alive += 1)
        S = cellsets(s40.w, Set(body_of(s40))); S39 = cellsets(s39.w, Set(body_of(s39)))
        push!(sz24, sizes_line("24x24", S, S39))
        b41 = step1(s40); mu0 = mu_bytes(b41); in0 = taken_in(s40, b41)
        isempty(S.far1) || (far1pos += 1)
        # 1. b_naive = ring1 + port: mid1 is outside it
        leaks(s40, S.mid1, mu0, 1) > 0 && (naive += 1)
        # 2. b_shell = halo1 + port: far1 is outside it (set-wise and cell-wise); the port takes must agree
        leaks(s40, S.far1, mu0, 1; cellwise = true) > 0 && (shell_in += 1)
        any(dA -> (p = perturb_A(s40, S.far1, dA); taken_in(p, step1(p)) != in0), DAS) && (take_mis += 1)
        # 4. outward: internal perturbations must not reach the next state of far1
        far0 = far_state(b41, S.far1); out_leak = false
        for q in 1:3   # noise ^ 1, circuit q = sg = 0, pool + 5U
            p = deepcopy(s40)
            p = BA.OneLife{BA.LawL2}(p.circuit, p.b, p.perm, q == 1 ? xor(p.noise, 1) : p.noise, p.w, p.pool, p.t, p.dead, p.death)
            q == 2 && (p.circuit.q .= 0; p.circuit.sg .= 0)
            q == 3 && (p.pool .+= 0.1)
            p41 = step1(p)
            far_state(p41, S.far1) != far0 && (out_leak = true)
            mu_bytes(p41) != mu0 && (eff[q] += 1)
        end
        out_leak && (outward += 1)
        # 5. minimality: ring1 removed, mid1 removed (= b_naive), the port removed (S62b fixture: pool [0, 0], g = (5, 5),
        #    reservoir 0.00 vs 0.25)
        leaks(s40, S.ring1, mu0, 1) > 0 && (ring1rm += 1)
        leaks(s40, S.mid1, mu0, 1) > 0 && (mid1rm += 1)
        pf = port_fixture(s40); l41 = pf.A; h41 = pf.B
        l41.pool != h41.pool && (port_pool += 1)
        (l41.pool != h41.pool && mu_bytes(l41) != mu_bytes(h41)) && (portrm += 1)
        paidmax = max(paidmax, pf.paid_A, pf.paid_B); pdmin = min(pdmin, maximum(abs.(l41.pool .- h41.pool)))
        seed == SEEDS[1] && (portex = "seed $seed: paid_all $(fmt(pf.paid_A)) vs $(fmt(pf.paid_B)); got $(fmt.(pf.got_A)) vs $(fmt.(pf.got_B)); pool_41 $(fmt.(l41.pool)) vs $(fmt.(h41.pool)); reservoir_41 $(fmt(l41.w.port.reservoir)) vs $(fmt(h41.w.port.reservoir))")
        # 3. two steps 39 → 41 on 24x24 (reported; run when far2 is not empty)
        if !isempty(S39.far2)
            f2pos24 += 1
            leaks(s39, S39.far2, mu_bytes(step2(s39)), 2; cellwise = true) > 0 && (f2leak24 += 1)
        end
        # 3. two steps 39 → 41 on 40x40 (make_world(; W = 40, H = 40, reservoir = 300.0), the canonical step)
        t39 = BA.raise(BA.birth_on(seed, 40, 40), 39); t40 = step1(t39)
        T40 = cellsets(t40.w, Set(body_of(t40))); T39 = cellsets(t39.w, Set(body_of(t39)))
        push!(sz40, sizes_line("40x40", T40, T39))
        if !isempty(T39.far2)
            f2pos40 += 1
            leaks(t39, T39.far2, mu_bytes(step2(t39)), 2; cellwise = true) > 0 && (f2leak40 += 1)
            p = perturb_A(t39, T39.far2, 0.45)
            step1(p).w.port.reservoir != t40.w.port.reservoir && (res40diff += 1)
        end
    end
    for z in sort(collect(sz24)); push!(L, "  sizes $z  ($(length(sz24)) distinct line(s) over the seeds)"); end
    for z in sort(collect(sz40)); push!(L, "  sizes $z  ($(length(sz40)) distinct line(s) over the seeds)"); end
    push!(L, "  s_40 alive with a non-empty body: $(frac(alive))")
    push!(L, "  1. 24x24 |far1| > 0: $(frac(far1pos)); b_naive (ring1+port), mid1 perturbed set-wise: leak $(frac(naive))")
    push!(L, "  2. 24x24 b_shell (halo1+port), far1 perturbed set-wise and cell-wise, 3 dA: inward leak $(frac(shell_in)); port-take mismatch $(frac(take_mis))")
    push!(L, "  3. 24x24 two steps 39->41: |far2| > 0 in $(frac(f2pos24))$(f2pos24 == 0 ? " (the 2-step closure saturates the 24x24 torus)" : " (not saturated on 24x24)"); far2 leak $f2leak24/$f2pos24 (reported, not gated)")
    push!(L, "     40x40 two steps 39->41: |far2| > 0 $(frac(f2pos40)); far2 perturbed set-wise and cell-wise, 3 dA: leak $(frac(f2leak40))")
    push!(L, "     (the port reservoir at s_40 differs after far2 +0.45 in $(frac(res40diff)) seeds: erosion of the added mass; the port is not clamped at 300)")
    push!(L, "  4. outward: internal perturbations (noise^1, circuit q=sg=0, pool+5U) reach far1 at t+1: $(frac(outward)); they change mu_41 in $(eff[1]), $(eff[2]), $(eff[3]) of $NS seeds (non-vacuity)")
    push!(L, "  5. minimality: ring1 removed leak $(frac(ring1rm)); mid1 removed (= b_naive) leak $(frac(mid1rm)); port removed (pool [0,0], g = (5,5), reservoir 0.00 vs 0.25) pool differs $(frac(port_pool)), pool and mu_41 differ $(frac(portrm))")
    push!(L, "     diagnostics: max paid_all over the seeds and arms $(fmt(paidmax)) (bound 0.052); min over the seeds of max_k |pool_41 A - B| $(fmt(pdmin))")
    push!(L, "     $portex")
    push!(L, "     (0/$NS leaks are claimed for the declared perturbation family only, P-11)")
    return alive == NS && far1pos == NS && naive == NS && shell_in == 0 && take_mis == 0 && f2pos40 == NS && f2leak40 == 0 &&
           outward == 0 && ring1rm == NS && mid1rm == NS && portrm == NS
end

# ---------------------------------------------------------------- GB3

function gate3(L)
    for (ph, r, w, rng) in BA.RW_TABLE; push!(L, "  rw | $ph | $r | $w | rng: $rng"); end
    src = src_rng_audit()
    exp_noise = ["noise = Mulberry(c.noise)", "noise = noise", "state_int32(noise)"]
    src_ok = src.matter_hits == 0 && length(src.live_noise) == 3 && all(i -> occursin(exp_noise[i], src.live_noise[i]), 1:3)
    push!(L, "  source scan: random sources in core/matter.jl $(src.matter_hits); lines of one_life.jl _live with noise $(length(src.live_noise)) (Mulberry(c.noise) / step!(...; noise) / state_int32(noise)): $src_ok")
    undecl = 0; ro = 0; unl = 0; mut = 0; steps = 0; farnoise = 0; gnoise = 0; effn = 0; rep = 0
    for seed in SEEDS
        s = birth40(seed)
        for _ in 1:20
            s.dead && break
            a = rw_audit(s, g_sched(s.t)); steps += 1
            isempty(a.undeclared) || (undecl += 1); isempty(a.readonly_written) || (ro += 1)
            isempty(a.unlisted) || (unl += 1); a.input_mutated && (mut += 1)
            s = step1(s)
        end
        s40 = birth40(seed); S = cellsets(s40.w, Set(body_of(s40)))
        p = BA.OneLife{BA.LawL2}(deepcopy(s40.circuit), deepcopy(s40.b), copy(s40.perm), xor(s40.noise, 1), deepcopy(s40.w),
                                 copy(s40.pool), s40.t, false, nothing)
        a41, ia = wrapped_step(s40, g_sched(40)); p41, ip = wrapped_step(p, g_sched(40))
        far_state(a41, S.far1) != far_state(p41, S.far1) && (farnoise += 1)
        (ia.got != ip.got || taken_in(s40, a41) != taken_in(p, p41)) && (gnoise += 1)
        mu_bytes(a41) != mu_bytes(p41) && (effn += 1)
        r1 = onelife_encode(step1(s40)); (onelife_encode(step1(s40)) == r1 && onelife_encode(step1(s40)) == r1) && (rep += 1)
    end
    push!(L, "  dynamic read/write audit, $steps canonical steps from s_40: undeclared writes $undecl, read-only fields written $ro, fields not in the table $unl, input mutated $mut")
    push!(L, "  noise-only perturbation (noise^1): far1 next state differs $(frac(farnoise)); port takes of the drive g differ $(frac(gnoise)); mu_41 differs $(frac(effn)) (non-vacuity)")
    push!(L, "  E[xi_t] = 0 (auxiliary): 3 replicate steps from s_40 byte-identical $(frac(rep)) (the step is deterministic given the state; xi = 0 holds trivially, as S62 B-Test 3 notes)")
    return src_ok && undecl == 0 && ro == 0 && unl == 0 && mut == 0 && farnoise == 0 && gnoise == 0 && rep == NS
end

# ---------------------------------------------------------------- GB4

Bsum(s) = sum((s.w.B[i] for i in body_of(s)); init = 0.0)
function arm(s, drive; block = false, replay = nothing)
    taken = 0.0; paid = 0.0; acts = Tuple{Vector{Int},Vector{Float64}}[]; noise = Int[]
    for k in 0:19
        rp = replay === nothing ? nothing : replay[k+1]
        s, inf = wrapped_step(s, drive(k); block = block, replay = rp)
        if inf === nothing; push!(acts, (Int[], [0.0, 0.0])); else
            taken += inf.taken; paid += inf.paid; push!(acts, (inf.acting, inf.d))
        end
        push!(noise, s.noise)
    end
    return (s = s, taken = taken, paid = paid, acts = acts, noise = noise)
end
median(v) = (x = sort(v); n = length(x); isodd(n) ? x[(n + 1) ÷ 2] : (x[n ÷ 2] + x[n ÷ 2 + 1]) / 2)
wdl(v) = (count(>(0), v), count(==(0), v), count(<(0), v))

function gate4(L)
    ident = 0; outd = 0; acted = 0; dt = Float64[]; dB = Float64[]; nz = 0; nmatch = 0; dmatch = 0
    dist = 0; distc = 0; dist_all = 0
    sat_y = 0; sat_out = 0; sat_circ = 0; sat_pool1 = 0; sat_pool2 = 0; sat_mu2 = 0; sat_all = 0; sat_take = 0; satex = ""
    resmin = Inf; dp1 = Float64[]; dp2 = Float64[]
    for seed in SEEDS
        s40 = birth40(seed); resmin = min(resmin, s40.w.port.reservoir)
        # identity wrapper: 20 steps of drive_A, canonical and wrapped byte for byte
        a = s40; b = s40; same = true
        for k in 0:19
            a, _ = onelife_step(a, drive_A(k)); b, _ = wrapped_step(b, drive_A(k))
            onelife_encode(a) == onelife_encode(b) || (same = false)
        end
        same && (ident += 1)
        # 4a: the sending end of m1, m2 blocked
        n = arm(s40, drive_A); x = arm(s40, drive_A; block = true)
        any(t -> !isempty(t[1]), n.acts) && (acted += 1)
        (n.s.pool != x.s.pool || n.paid != x.paid || Bsum(n.s) != Bsum(x.s)) && (outd += 1)
        # 4b: Live (drive_A), Donor (drive_B), Yoke (drive_A, the Donor's acts consumed); one initial noise
        live = n; donor = arm(s40, drive_B); yoke = arm(s40, drive_A; replay = donor.acts)
        nmatch += count(k -> yoke.noise[k] == live.noise[k], 1:20); dmatch += count(k -> donor.noise[k] == live.noise[k], 1:20)
        push!(dt, live.taken - yoke.taken); push!(dB, Bsum(live.s) - Bsum(yoke.s))
        (dt[end] != 0 || dB[end] != 0) && (nz += 1)
        # 4c distinguished pair: pool = [0, 0], g_t = (5,0) vs (0,5), then g_sched(41) in both
        u = deepcopy(s40); u.pool .= [0.0, 0.0]
        u1, _ = wrapped_step(u, (5, 0)); v1, _ = wrapped_step(u, (0, 5))
        u2, iu = wrapped_step(u1, g_sched(41)); v2, iv = wrapped_step(v1, g_sched(41))
        dy = iu.y != iv.y; dm = mu_bytes(u2) != mu_bytes(v2); dc = BA._bytes(u2.circuit) != BA._bytes(v2.circuit)
        (dy && dm) && (dist += 1); dc && (distc += 1); (dy && dc && dm) && (dist_all += 1)
        # 4c identified pair (S62b fixture): pool = [0.40, 0.40], g_t = (4,4) vs (5,5), then g_sched(41) in both
        f = sat_fixture(s40); u1 = f.u1; v1 = f.v1; u2 = f.u2; v2 = f.v2; i0 = f.i0; iu = f.iu; iv = f.iv
        i0.taken > 0 && (sat_take += 1)
        yok = iu.y == [5.0, 5.0] && iv.y == [5.0, 5.0]; ook = iu.acting_c == iv.acting_c && iu.d_c == iv.d_c
        cok = BA._bytes(u2.circuit) == BA._bytes(v2.circuit)
        p1 = u1.pool != v1.pool; p2 = u2.pool != v2.pool; m2 = mu_bytes(u2) != mu_bytes(v2)
        yok && (sat_y += 1); ook && (sat_out += 1); cok && (sat_circ += 1)
        p1 && (sat_pool1 += 1); p2 && (sat_pool2 += 1); m2 && (sat_mu2 += 1)
        (yok && ook && cok && p1 && p2 && m2) && (sat_all += 1)
        push!(dp1, maximum(abs.(u1.pool .- v1.pool))); push!(dp2, maximum(abs.(u2.pool .- v2.pool)))
        seed == SEEDS[1] && (satex = "seed $seed: reservoir_40 $(fmt(s40.w.port.reservoir)), take at t $(fmt(i0.taken)) vs $(fmt(f.j0.taken)), pool_t+1 $(fmt.(u1.pool)) vs $(fmt.(v1.pool)), y_t+1 $(iu.y) vs $(iv.y), take at t+1 $(fmt(iu.taken)) vs $(fmt(iv.taken)), pool_t+2 $(fmt.(u2.pool)) vs $(fmt.(v2.pool))")
    end
    push!(L, "  identity wrapper = onelife_step, 20 steps of drive_A from s_40, byte for byte: $(frac(ident))")
    push!(L, "  4a P-04 block of m1, m2 at the consumer: outward difference (pool, paid sum, body B sum) $(frac(outd)); the normal arm acted at least once in $(frac(acted))")
    wt = wdl(dt); wb = wdl(dB)
    push!(L, "  4b noise after each step, Yoke = Live: $nmatch/$(20NS) steps; Donor = Live: $dmatch/$(20NS) steps")
    push!(L, "     d_taken = taken_live - taken_yoke: win/draw/lose $(wt[1])/$(wt[2])/$(wt[3]), median $(fmt(median(dt)))")
    push!(L, "     d_B = B_live - B_yoke: win/draw/lose $(wb[1])/$(wb[2])/$(wb[3]), median $(fmt(median(dB)))")
    signed = wt[1] > wt[3] && wb[1] > wb[3]
    push!(L, "     seeds with d_taken != 0 or d_B != 0: $(frac(nz)) (GB4b needs a majority, >= $(frac(MAJ)))")
    push!(L, "     signed Live > Yoke (wins > losses on d_taken and on d_B): $signed")
    push!(L, "     d_taken per seed: $(join(fmt.(dt), " "))")
    push!(L, "     d_B per seed: $(join(fmt.(dB), " "))")
    wt[1] <= wt[3] && push!(L, "     d_taken: Live wins <= losses: no adaptive advantage detected for LawL2 raised 40 steps")
    wb[1] <= wb[3] && push!(L, "     d_B: Live wins <= losses: no adaptive advantage detected for LawL2 raised 40 steps")
    push!(L, "  4c distinguished pair (pool 0, (5,0) vs (0,5)): y_t+1 differs and mu_t+2 differs $(frac(dist)); circuit state at t+2 differs $(frac(distc)); all three $(frac(dist_all))")
    push!(L, "  4c identified pair (pool [0.40,0.40], (4,4) vs (5,5), g_t+1 = g_sched(41)): min reservoir at s_40 over the seeds $(fmt(resmin)) (>= $(fmt(RES_FLOOR)): $(resmin >= RES_FLOOR))")
    push!(L, "     y_t+1 = [5,5] in both $(frac(sat_y)); circuit output at t+1 identical $(frac(sat_out)); circuit state at t+2 identical $(frac(sat_circ))")
    push!(L, "     raw pool at t+1 differs $(frac(sat_pool1)); pool at t+2 differs $(frac(sat_pool2)); mu_t+2 differs $(frac(sat_mu2)); all six $(frac(sat_all))")
    push!(L, "     max_k |pool A - B| (reference): t+1 min $(fmt(minimum(dp1))) max $(fmt(maximum(dp1))); t+2 min $(fmt(minimum(dp2))) max $(fmt(maximum(dp2)))")
    push!(L, "     the circuit took from the pool at step t (before the y_t+1 read) in $(frac(sat_take)); $satex")
    gate = ident == NS && outd == NS && nmatch == 20NS && nz >= MAJ && signed && dist_all == NS && sat_all == NS && resmin >= RES_FLOOR
    return gate, nz
end

# ---------------------------------------------------------------- GB5

function freeze_check(L)
    ok = true
    for line in eachline(FREEZE)
        (startswith(line, "#") || isempty(strip(line))) && continue
        h, path = split(line; limit = 2); path = strip(path)
        actual = bytes2hex(sha256(read(joinpath(dirname(FREEZE), path))))
        m = actual == h; ok &= m
        push!(L, "  freeze $path: $(m ? "match" : "MISMATCH $actual")")
    end
    return ok
end
function core_check(L)
    ok = true
    for (f, h) in CORE_SHA
        actual = bytes2hex(sha256(read(joinpath(ROOT, "core", f))))
        m = actual == h; ok &= m
        push!(L, "  core/$f: $(m ? "match" : "MISMATCH $actual")")
    end
    extra = sort(setdiff(filter(f -> endswith(f, ".jl"), readdir(joinpath(ROOT, "core"))), first.(CORE_SHA)))
    push!(L, "  extra core/*.jl files: $(isempty(extra) ? "none" : join(extra, ","))")
    return ok && isempty(extra)
end
function parent_check(L)
    ok = true
    for (f, h) in PARENT_SHA
        actual = bytes2hex(sha256(read(joinpath(ROOT, "experiments", "boundary_audit", f))))
        m = actual == h; ok &= m
        push!(L, "  experiments/boundary_audit/$f: $(m ? "match" : "MISMATCH $actual")")
    end
    return ok
end

function evaluate()
    L = String[]; G = Dict{String,Bool}()
    push!(L, "GB1 (B-Test 1, six finite tables)"); G["GB1"] = gate1(L); push!(L, "  GB1: $(G["GB1"] ? "PASS" : "FAIL")")
    push!(L, "GB2 (B-Test 2, two-way D-BaSS, minimality, two-step history)"); G["GB2"] = gate2(L); push!(L, "  GB2: $(G["GB2"] ? "PASS" : "FAIL")")
    push!(L, "GB3 (B-Test 3, read/write table and the separation of the random source)"); G["GB3"] = gate3(L); push!(L, "  GB3: $(G["GB3"] ? "PASS" : "FAIL")")
    push!(L, "GB4 (B-Test 4, three separated interventions)"); g4, nz = gate4(L); G["GB4"] = g4; push!(L, "  GB4: $(G["GB4"] ? "PASS" : "FAIL")")
    return L, G, nz
end

function main()
    head = ["# S62b r2 gates GB1–GB5 (spec discussion/specs/S62b-aue-boundary-audit.md, predictions experiments/predictions-boundary-audit-b.md)",
            "# seeds $(first(SEEDS))..$(last(SEEDS))$(DEV ? " (development, not evaluation)" : " (evaluation)"); phenomenal_claim = :not_certified",
            "# start s_40: onelife_birth(seed, LawL2), 40 steps of g_t = ((t ÷ 10) % 2 == 0 ? (5,1) : (1,5)); the step to s_41 uses g_40 = (5,1)",
            "# no Lean statement in S62b (formal/ is outside FILE:); sh formal/check.sh was run unchanged before this script"]
    L1, G1, nz1 = evaluate()
    L2, G2, nz2 = evaluate()
    d1 = bytes2hex(sha256(join(L1, "\n"))); d2 = bytes2hex(sha256(join(L2, "\n")))
    L5 = ["GB5 (determinism, the freeze, core/ and the parent S62 files unchanged)", "  run 1 digest $d1", "  run 2 digest $d2", "  bit-identical: $(d1 == d2)"]
    fz = freeze_check(L5); cz = core_check(L5); pz = parent_check(L5)
    G = copy(G1); G["GB5"] = d1 == d2 && G1 == G2 && fz && cz && pz
    push!(L5, "  GB5: $(G["GB5"] ? "PASS" : "FAIL")")
    S = ["Summary"]
    for g in ("GB1", "GB2", "GB3", "GB4", "GB5"); push!(S, "  $g $(G[g] ? "PASS" : "FAIL")"); end
    P = [("P-S62b-1", G["GB1"]), ("P-S62b-2", G["GB2"]), ("P-S62b-3", G["GB3"]), ("P-S62b-4", G["GB4"]), ("P-S62b-5", G["GB5"])]
    for (p, h) in P; push!(S, "  $p: $(h ? "held" : "FAILED")"); end
    push!(S, "  (P-S62b-4 = GB4: the identity wrapper, 4a, 4b noise 400/400 and >= 11/20 non-zero and signed Live > Yoke, 4c both pairs)")
    allpass = all(values(G))
    push!(S, "  all gates: $(allpass ? "PASS" : "FAIL")")
    text = join([head; L1; L5; S], "\n") * "\n"
    print(text)
    DEV || READONLY || write(OUT, text)
    exit(allpass ? 0 : 1)
end

main()
