# S61c r2 gates G1–G5 (discussion/specs/S61c-nesting-cpc-pruning.md §3; predictions experiments/predictions-nesting-cpc-c.md).
# The gates are those of S61b r2 (experiments/nesting_cpc_b/run_gates.jl); added are (G2) the step-by-step identity of
# Runaway-Cancer with the parent S61 r3 (experiments/nesting_cpc/NestingCPC.jl), both variances of (c) as gates, and the
# pruning diagnostics; (G5) the SHA-256 of the three unchanged parent files. No git command is called.
# G0 is `sh formal/check.sh` (formal/NestingLineage.lean unchanged) and is not run here.
# Usage (from the lab root): julia --project=. experiments/nesting_cpc_c/run_gates.jl             evaluation seeds 962..981,
#                                                                                                  writes experiments/results-nesting-cpc-c.out
#                            julia --project=. experiments/nesting_cpc_c/run_gates.jl --readonly  the same, stdout only
#                            julia --project=. experiments/nesting_cpc_c/run_gates.jl dev         development seeds 958..961, stdout only
# Exit code 0 only when every gate passes.
include(joinpath(@__DIR__, "NestingCPCC.jl"))
include(joinpath(@__DIR__, "..", "nesting_cpc", "NestingCPC.jl"))   # the parent S61 r3, a separate module (G2 pre)
using .NestingCPCC
using Printf
using SHA

const DEV = "dev" in ARGS
const READONLY = "--readonly" in ARGS
const SEEDS = DEV ? collect(958:961) : collect(962:981)
const OUT = joinpath(@__DIR__, "..", "results-nesting-cpc-c.out")
const FREEZE = joinpath(@__DIR__, "..", "freeze-nesting-cpc-c.txt")
const LAB = joinpath(@__DIR__, "..", "..")
const PARENTS = [("formal/NestingLineage.lean", "24b55ba1aa7a3b686198866148a8355cf0bde3d7348a7548fb313e8b9c8ea7f1"),
                 ("experiments/nesting_cpc/NestingCPC.jl", "bf2e236cfe1886ca475cdaa68257f2b4331652a78103fb45ca46b830c4c19b9b"),
                 ("experiments/nesting_cpc_b/NestingCPCB.jl", "922b310017b549b9383a7d0550382ca586b48443299c6a277f6644a041800e47")]
const FAMINE_END = 65
const LAGS = 1:12
const G4_CONFIGS = (:CPC, :Fixed, :RotFO, :RotRed, :Omitted)
const G4_EXPECT = Dict(:CPC => :no_core_witnessed, :Fixed => :core_present, :RotFO => :core_present,
                       :RotRed => :core_present, :Omitted => :unresolved)

fmt(x::Float64) = @sprintf("%.6f", x)
seedlist(s) = isempty(s) ? "{}" : "{" * join(s, ",") * "}"

# ---------------------------------------------------------------- G1: discrete witnesses (Stage 0 / Stage 1)

struct Witness
    name::String
    V0::Vector{Symbol}
    V1::Vector{Symbol}
    id0::Dict{Symbol,Int}       # body has no id
    id1::Dict{Symbol,Int}
    edges::Vector{Tuple{Symbol,Symbol,Symbol}}
    next_id::Int
end

const WITNESSES = [
    Witness("H_persist", [:W0, :a0, :b0], [:W1, :a1, :b1], Dict(:a0 => 1, :b0 => 2), Dict(:a1 => 1, :b1 => 2),
            [(:W0, :W1, :persist), (:a0, :a1, :persist), (:b0, :b1, :persist)], 3),
    Witness("H_replace", [:W0, :a0, :b0], [:W1, :a1, :b1], Dict(:a0 => 1, :b0 => 2), Dict(:a1 => 3, :b1 => 4),
            [(:W0, :W1, :persist)], 3),
    Witness("H_shifting", [:W0, :a0, :b0], [:W1, :b1, :c1], Dict(:a0 => 1, :b0 => 2), Dict(:b1 => 2, :c1 => 3),
            [(:W0, :W1, :persist), (:b0, :b1, :split), (:b0, :c1, :split)], 3),
]

"Stage 0 observation up to isomorphism: the star order is fixed by the number of parts; irreducible iff ≥ 2 parts."
stage0(V) = (parts = length(V) - 1, irreducible = length(V) - 1 >= 2, cls = (length(V) - 1 >= 2) ? :individual : :dead)

function witness_wf(w::Witness)
    bad = String[]
    out(u) = [e for e in w.edges if e[1] == u]
    inn(v) = [e for e in w.edges if e[2] == v]
    for (u, v, k) in w.edges
        if k == :persist
            (length(out(u)) == 1 && length(inn(v)) == 1) || push!(bad, "persist $u→$v not exclusive")
            get(w.id1, v, 0) == get(w.id0, u, 0) || push!(bad, "persist $u→$v changes the carrier id")
        elseif k == :split
            (length(out(u)) >= 2 && all(e -> e[3] == :split, out(u)) && length(inn(v)) == 1) ||
                push!(bad, "split $u→$v malformed")
            haskey(w.id0, u) || push!(bad, "split of the body")
            (get(w.id1, v, -1) == w.id0[u] || get(w.id1, v, -1) >= w.next_id) || push!(bad, "split output $v reuses an id")
        end
    end
    for u in w.V0
        ks = [e for e in out(u)]
        conts = count(e -> e[3] == :split && get(w.id1, e[2], -1) == get(w.id0, u, -2), ks)
        conts <= 1 || push!(bad, "split $u has $conts continuants")
    end
    for v in w.V1
        isempty(inn(v)) && haskey(w.id1, v) && w.id1[v] < w.next_id && push!(bad, "birth $v reuses an id")
    end
    length(unique(values(w.id1))) == length(w.id1) || push!(bad, "duplicate id at t=1")
    bad
end

function span_invariant(w::Witness)
    outdeg = sort([(string(u), length([e for e in w.edges if e[1] == u]),
                    join(sort([string(e[3]) for e in w.edges if e[1] == u]), "+")) for u in w.V0], by = x -> (x[2], x[3]))
    deaths = count(u -> !any(e -> e[1] == u, w.edges), w.V0)
    births = count(v -> !any(e -> e[2] == v, w.edges), w.V1)
    ([(d, k) for (_, d, k) in outdeg], deaths, births)
end

function gate1_witnesses(L)
    ok = true
    for w in WITNESSES
        s0, s1 = stage0(w.V0), stage0(w.V1)
        bad = witness_wf(w)
        push!(L, "  $(w.name): stage0(t0)=$(s0) stage0(t1)=$(s1) isomorphic=$(s0 == s1) wf_violations=$(length(bad)) " *
                 "invariant=$(span_invariant(w))")
        ok &= s0 == s1 && isempty(bad) && s0.cls == :individual
    end
    sep = true
    for i in eachindex(WITNESSES), j in i+1:length(WITNESSES)
        d = span_invariant(WITNESSES[i]) != span_invariant(WITNESSES[j])
        push!(L, "  separated($(WITNESSES[i].name), $(WITNESSES[j].name)) = $d")
        sep &= d
    end
    ok && sep
end

# ---------------------------------------------------------------- G1: R2 on every run, and the two negative tests

function gate1_r2(L)
    total = 0
    for c in CONFIGS
        nv = 0
        nsteps = 0
        first = ""
        npruned = 0
        for seed in SEEDS
            r = run_config(c, seed)
            issued = Set(1:4)
            for rec in r.recs
                v = r2_violations(rec, issued)
                nsteps += 1
                npruned += rec.pruned
                if !isempty(v) && isempty(first)
                    first = "seed $seed: $(v[1])"
                end
                nv += length(v)
            end
        end
        push!(L, "  R2 $(rpad(NAMES[c], 28)) transitions=$nsteps violations=$nv pruning_deaths=$npruned $(first)")
        total += nv
    end
    total == 0
end

function with_post(rec, post, events)
    NestingCPCC.StepRec(rec.t, rec.alive_pre, rec.alive_post, rec.body, events, rec.pre_objs, post, rec.next_id_pre,
                        rec.next_id_post, rec.births, rec.deficit, rec.D, rec.h_ema, rec.pruned, rec.D_pre_prune)
end

function gate1_negative(L)
    det_dup = 0
    det_reuse = 0
    n_dup = 0
    n_reuse = 0
    for seed in SEEDS
        r = run_config(:CPC, seed)
        # (1) deepcopy injected as a second continuant output of a split
        issued = Set(1:4)
        for rec in r.recs
            k = findfirst(ev -> ev.kind == :split, rec.events)
            if k !== nothing
                ev = rec.events[k]
                p = ev.srcs[1]
                parent = rec.post_objs[findfirst(m -> m.id == p, rec.post_objs)]
                events = copy(rec.events)
                events[k] = NestingCPCC.Event(:split, [p], [p; ev.outs])
                bad = with_post(rec, [rec.post_objs; deepcopy(parent)], events)
                n_dup += 1
                det_dup += !isempty(r2_violations(bad, copy(issued)))
                break
            end
            r2_violations(rec, issued)
        end
        # (2) the parent destroyed and a copy put back into its slot with the same id
        issued = Set(1:4)
        for rec in r.recs
            k = findfirst(ev -> ev.kind == :persist, rec.events)
            if k !== nothing && rec.t >= 2
                p = rec.events[k].srcs[1]
                orig = rec.pre_objs[findfirst(m -> m.id == p, rec.pre_objs)]
                post = [m.id == p ? deepcopy(orig) : m for m in rec.post_objs]
                n_reuse += 1
                det_reuse += !isempty(r2_violations(with_post(rec, post, rec.events), copy(issued)))
                break
            end
            r2_violations(rec, issued)
        end
    end
    push!(L, "  negative (deepcopy second continuant): detected $det_dup/$n_dup")
    push!(L, "  negative (slot reuse after parent destroyed): detected $det_reuse/$n_reuse")
    n_dup == length(SEEDS) && n_reuse == length(SEEDS) && det_dup == n_dup && det_reuse == n_reuse
end

# ---------------------------------------------------------------- G2: E1

function pearson(x::Vector{Float64}, y::Vector{Float64})
    n = length(x)
    mx, my = sum(x) / n, sum(y) / n
    sxx = sum((x .- mx) .^ 2)
    syy = sum((y .- my) .^ 2)
    (sxx == 0.0 || syy == 0.0) && return NaN
    sum((x .- mx) .* (y .- my)) / sqrt(sxx * syy)
end

"The state shared by S61 r3 and S61c (no h_ema): config, alive, R, D, next_id, ctx, step, mods, grant_cache."
function shared_bytes(sys)
    io = IOBuffer()
    write(io, string(sys.config), sys.alive, sys.R, sys.D, Int64(sys.next_id), Int64(sys.ctx), Int64(sys.step),
          Int64(length(sys.mods)))
    for m in sys.mods
        write(io, Int64(m.id), m.u, Int64(m.born))
        write(io, vec(m.theta))
    end
    write(io, Int64(length(sys.grant_cache)), sys.grant_cache)
    take!(io)
end

"(pre) One configuration of S61c against the parent S61 r3 on the same tape, after every one of the T steps."
function parent_identity(seed, config::Symbol = :Runaway)
    tape, thetas = make_tape(seed)
    ptape, pthetas = NestingCPC.make_tape(seed)
    (all(k -> (tape[k].x, tape[k].h, tape[k].r) == (ptape[k].x, ptape[k].h, ptape[k].r), 1:T) && thetas == pthetas) ||
        return (false, 0)
    sys = init_system(config, thetas)
    psys = NestingCPC.init_system(config, pthetas)
    shared_bytes(sys) == shared_bytes(psys) || return (false, 0)
    for k in 1:T
        rec = step!(sys, tape[k], k)
        prec = NestingCPC.step!(psys, ptape[k], k)
        a = IOBuffer(); write_events(a, rec)
        b = IOBuffer(); NestingCPC.write_events(b, prec)
        same = take!(a) == take!(b) && shared_bytes(sys) == shared_bytes(psys) &&
               (rec.births, rec.deficit, rec.D) == (prec.births, prec.deficit, prec.D)
        same || return (false, k)
    end
    (true, 0)
end

popvar(x) = isempty(x) ? NaN : sum((x .- sum(x) / length(x)) .^ 2) / length(x)

function gate2(L)
    nid = 0
    firstbad = String[]
    for seed in SEEDS
        ok, k = parent_identity(seed)
        nid += ok
        ok || push!(firstbad, "seed $seed step $k")
    end
    pre = nid == length(SEEDS)
    push!(L, "  (pre) Runaway-Cancer identical to S61 r3 NestingCPC (shared state + events, $(T) steps): " *
             "$nid/$(length(SEEDS)) $(join(firstbad, ", "))")
    # negative control of the comparator (not pass/fail): CPC-Prolif changed in S61b and S61c, so it must differ
    negk = Int[]
    for seed in SEEDS
        ok, k = parent_identity(seed, :CPC)
        push!(negk, ok ? 0 : k)
    end
    push!(L, "  [diagnostic] comparator negative control: CPC-Prolif differs from S61 r3 in " *
             "$(count(>(0), negk))/$(length(SEEDS)) (first differing step $(negk))")
    surv = Dict(c => Int[] for c in (:CPC, :Runaway))
    maxd = Dict(c => Float64[] for c in (:CPC, :Runaway))
    maxdpre = Dict(c => Float64[] for c in (:CPC, :Runaway))
    deathstep = Dict(c => Int[] for c in (:CPC, :Runaway))
    births = Float64[]
    defs = Float64[]
    maxm = Dict(c => Int[] for c in (:CPC, :Runaway))
    minm = Dict(c => Int[] for c in (:CPC, :Runaway))
    dpos = Dict(c => Int[] for c in (:CPC, :Runaway))
    prunes = Int[]
    regrow = Int[]
    lagx = Dict(k => Float64[] for k in LAGS)
    lagy = Dict(k => Float64[] for k in LAGS)
    for seed in SEEDS, c in (:CPC, :Runaway)
        r = run_config(c, seed)
        r.sys.alive && push!(surv[c], seed)
        live = [rec for rec in r.recs if rec.alive_pre]
        push!(maxd[c], maximum([0.0; [rec.D for rec in live]]))
        push!(maxdpre[c], maximum([0.0; [rec.D_pre_prune for rec in live]]))
        k = findfirst(rec -> rec.alive_pre && !rec.alive_post, r.recs)
        push!(deathstep[c], k === nothing ? 0 : k)
        # |M_t| over V_t and V_{t+1} of the live steps
        sizes = [length(rec.pre_objs) for rec in live]
        append!(sizes, [length(rec.post_objs) for rec in live if rec.alive_post])
        push!(maxm[c], maximum(sizes; init = 0))
        push!(minm[c], minimum(sizes))   # never empty: step 1 is always live
        push!(dpos[c], count(rec -> rec.D > 0.0, live))
        if c == :CPC
            push!(prunes, sum(rec.pruned for rec in live; init = 0))
            any(rec -> rec.t > FAMINE_END && rec.births > 0, live) && push!(regrow, seed)
            append!(births, [Float64(rec.births) for rec in live])
            append!(defs, [rec.deficit for rec in live])
            # lag pairs (birth_t, deficit_{t+k}) with both steps live, censored at death, within one seed
            for lag in LAGS, t in 1:T-lag
                (r.recs[t].alive_pre && r.recs[t+lag].alive_pre) || continue
                push!(lagx[lag], Float64(r.recs[t].births))
                push!(lagy[lag], r.recs[t+lag].deficit)
            end
        end
    end
    a = issubset(surv[:Runaway], surv[:CPC]) && length(surv[:CPC]) > length(surv[:Runaway])
    mc, mr = sum(maxd[:CPC]) / length(SEEDS), sum(maxd[:Runaway]) / length(SEEDS)
    b = mc < mr
    vb, vd = popvar(births), popvar(defs)
    rr = pearson(births, defs)
    cc = vb > 0.0 && vd > 0.0 && !isnan(rr) && rr < 0.0
    push!(L, "  survivors CPC-Prolif $(length(surv[:CPC]))/$(length(SEEDS)) $(seedlist(surv[:CPC]))")
    push!(L, "  survivors Runaway-Cancer $(length(surv[:Runaway]))/$(length(SEEDS)) $(seedlist(surv[:Runaway]))")
    push!(L, "  death step (0 = survived) CPC-Prolif $(deathstep[:CPC])")
    push!(L, "  death step (0 = survived) Runaway-Cancer $(deathstep[:Runaway])")
    push!(L, "  (a) strict superset of survivors: $a")
    push!(L, "  (b) mean max debt (StepRec.D) CPC-Prolif $(fmt(mc)) < Runaway-Cancer $(fmt(mr)): $b")
    push!(L, "  (c) pooled live steps n=$(length(births)) births_sum=$(Int(sum(births))) deficit_steps=$(count(>(0.0), defs)) " *
             "var(birth_t)=$(fmt(vb)) var(deficit_t)=$(fmt(vd)) " *
             "pearson r(birth_t, deficit_t)=$(isnan(rr) ? "NaN" : fmt(rr)) both var > 0 and r<0: $cc")
    push!(L, "  [diagnostic] mean max D_pre_prune CPC-Prolif $(fmt(sum(maxdpre[:CPC]) / length(SEEDS))) " *
             "Runaway-Cancer $(fmt(sum(maxdpre[:Runaway]) / length(SEEDS)))")
    push!(L, "  [diagnostic] max debt per seed CPC-Prolif $(fmt.(maxd[:CPC]))")
    push!(L, "  [diagnostic] max debt per seed Runaway-Cancer $(fmt.(maxd[:Runaway]))")
    push!(L, "  [diagnostic] max D_pre_prune per seed CPC-Prolif $(fmt.(maxdpre[:CPC]))")
    push!(L, "  [diagnostic] CPC-Prolif prunings total $(sum(prunes)) per seed $(prunes)")
    for c in (:CPC, :Runaway)
        hist = Dict{Int,Int}()
        foreach(m -> hist[m] = get(hist, m, 0) + 1, maxm[c])
        hs = join(["$m:$(hist[m])" for m in sort(collect(keys(hist)))], " ")
        push!(L, "  [diagnostic] max_t |M_t| per seed $(NAMES[c]) $(maxm[c]) (distribution $hs)")
        push!(L, "  [diagnostic] min_t |M_t| per seed $(NAMES[c]) $(minm[c])")
        push!(L, "  [diagnostic] live steps with D > 0 per seed $(NAMES[c]) $(dpos[c]) (total $(sum(dpos[c])))")
    end
    push!(L, "  [diagnostic] CPC-Prolif seeds with a split birth in a live step t > $(FAMINE_END): " *
             "$(length(regrow))/$(length(SEEDS)) $(seedlist(regrow))")
    lags = String[]
    for lag in LAGS
        rl = pearson(lagx[lag], lagy[lag])
        push!(lags, "k=$lag:$(isnan(rl) ? "NaN" : fmt(rl))(n=$(length(lagx[lag])))")
    end
    push!(L, "  [diagnostic] CPC-Prolif lag r(birth_t, deficit_{t+k}) $(join(lags, " "))")
    pre && a && b && cc
end

# ---------------------------------------------------------------- G3: E2

"Digest of the whole trace (state after each step and L_t), or of L_t alone."
function trace_digest(c, seed; t_start = 0, phi_rich = 0.0, interp = "", events_only = false)
    tape, thetas = make_tape(seed)
    sys = init_system(c, thetas)
    io = IOBuffer()
    for k in 1:T
        rec = step!(sys, tape[k], t_start + k; phi_rich = phi_rich, interp = interp)
        write_events(io, rec)
        events_only || write_state(io, sys)
    end
    bytes2hex(sha256(take!(io)))
end

function gate3(L)
    ext_ok = 0
    shift_ok = 0
    hidden_det = 0
    hidden_first = Int[]
    for seed in SEEDS
        base = trace_digest(:CPC, seed)
        ext = trace_digest(:CPC, seed; phi_rich = 1.0e6, interp = "通訳の語り（読み取り専用のはずの入力）")
        shf = trace_digest(:CPC, seed; t_start = 20)
        ext_ok += base == ext
        shift_ok += base == shf
        h0 = trace_digest(:Hidden, seed; events_only = true)
        h20 = trace_digest(:Hidden, seed; t_start = 20, events_only = true)
        hidden_det += h0 != h20
        # the first step whose L_t differs
        tape, thetas = make_tape(seed)
        s0, s20 = init_system(:Hidden, thetas), init_system(:Hidden, deepcopy(thetas))
        fd = 0
        for k in 1:T
            a = IOBuffer(); write_events(a, step!(s0, tape[k], k))
            b = IOBuffer(); write_events(b, step!(s20, tape[k], 20 + k))
            if take!(a) != take!(b)
                fd = k
                break
            end
        end
        push!(hidden_first, fd)
    end
    n = length(SEEDS)
    push!(L, "  CPC-Prolif forbidden inputs (phi_rich, interpreter text) bit-identical: $ext_ok/$n")
    push!(L, "  CPC-Prolif time shift t_start 0 vs 20 bit-identical: $shift_ok/$n")
    push!(L, "  Hidden-Age-Control time shift L_t mismatch detected: $hidden_det/$n (first differing step $(hidden_first))")
    ext_ok == n && shift_ok == n && hidden_det == n
end

# ---------------------------------------------------------------- G4: E3′

function gate4(L)
    ok = true
    for c in G4_CONFIGS
        counts = Dict{Symbol,Int}()
        tstars = Int[]
        calib = 0.0
        notes = String[]
        for seed in SEEDS
            j = judge_e3(c, seed)
            counts[j.verdict] = get(counts, j.verdict, 0) + 1
            push!(tstars, j.tstar)
            calib = max(calib, get(j.info, :calib, Inf))
            if seed == SEEDS[1]
                i = j.info
                ks = sort(collect(keys(i)), by = string)
                push!(notes, join(["$k=$(i[k])" for k in ks], " "))
            end
            j.verdict == :no_tstar && (ok = false)
        end
        exp = G4_EXPECT[c]
        hit = get(counts, exp, 0) == length(SEEDS)
        ok &= hit && calib == 0.0
        cs = join(["$k=$(counts[k])" for k in sort(collect(keys(counts)), by = string)], " ")
        push!(L, "  $(rpad(NAMES[c], 28)) verdicts: $cs (expected $exp $(length(SEEDS))/$(length(SEEDS)): $hit)")
        push!(L, "    t* per seed $(tstars); calibration max|Δp̂| at δ=0: $(calib)")
        push!(L, "    evidence (seed $(SEEDS[1])): $(notes[1])")
    end
    # diagnostic (S61b §1.3 / S61c §3 G4, not pass/fail): every local_link of CPC-Prolif collapsed into one shared rule
    counts = Dict{Symbol,Int}()
    for seed in SEEDS
        j = judge_e3(:CPC, seed; shared = true)
        counts[j.verdict] = get(counts, j.verdict, 0) + 1
    end
    cs = join(["$k=$(counts[k])" for k in sort(collect(keys(counts)), by = string)], " ")
    push!(L, "  [diagnostic] CPC-Prolif with every local_link as one shared rule: $cs")
    ok
end

# ---------------------------------------------------------------- G5 and the summary

function freeze_check(L)
    ok = true
    for line in eachline(FREEZE)
        (isempty(strip(line)) || startswith(line, "#")) && continue
        h, path = split(line; limit = 2)
        path = strip(path)
        actual = bytes2hex(sha256(read(joinpath(dirname(FREEZE), path))))
        push!(L, "  freeze $(path): $(actual == h ? "match" : "MISMATCH $actual")")
        ok &= actual == h
    end
    for (path, h) in PARENTS
        actual = bytes2hex(sha256(read(joinpath(LAB, path))))
        push!(L, "  parent $(path): $(actual == h ? "match" : "MISMATCH $actual")")
        ok &= actual == h
    end
    ok
end

function evaluate()
    L = String[]
    G = Dict{String,Bool}()
    push!(L, "G1 (R1, R2 and the negative tests)")
    w = gate1_witnesses(L)
    r2 = gate1_r2(L)
    neg = gate1_negative(L)
    G["G1"] = w && r2 && neg
    push!(L, "  G1: $(G["G1"] ? "PASS" : "FAIL") (witnesses $w, R2 $r2, negatives $neg)")
    push!(L, "G2 (E1)")
    G["G2"] = gate2(L)
    push!(L, "  G2: $(G["G2"] ? "PASS" : "FAIL")")
    push!(L, "G3 (E2)")
    G["G3"] = gate3(L)
    push!(L, "  G3: $(G["G3"] ? "PASS" : "FAIL")")
    push!(L, "G4 (E3′, priority unresolved > core_present > no_core_witnessed)")
    G["G4"] = gate4(L)
    push!(L, "  G4: $(G["G4"] ? "PASS" : "FAIL")")
    L, G
end

function main()
    head = ["# S61c r2 gates G1–G5 (spec discussion/specs/S61c-nesting-cpc-pruning.md, predictions experiments/predictions-nesting-cpc-c.md)",
            "# seeds $(first(SEEDS))..$(last(SEEDS))$(DEV ? " (development, not evaluation)" : " (evaluation)"); phenomenal_claim = :not_certified",
            "# G0 is sh formal/check.sh (formal/NestingLineage.lean) and is not run by this script"]
    L1, G1 = evaluate()
    L2, G2 = evaluate()
    d1 = bytes2hex(sha256(join(L1, "\n")))
    d2 = bytes2hex(sha256(join(L2, "\n")))
    L5 = ["G5 (determinism, the freeze and the unchanged parents)", "  run 1 digest $d1", "  run 2 digest $d2", "  bit-identical: $(d1 == d2)"]
    fz = freeze_check(L5)
    G = copy(G1)
    G["G5"] = d1 == d2 && fz && G1 == G2
    push!(L5, "  G5: $(G["G5"] ? "PASS" : "FAIL")")
    S = ["Summary (Julia side; P-S61c-1 also needs G0)"]
    for g in ("G1", "G2", "G3", "G4", "G5")
        push!(S, "  $g $(G[g] ? "PASS" : "FAIL")")
    end
    for (p, g) in (("P-S61c-1 (Julia part)", "G1"), ("P-S61c-2", "G2"), ("P-S61c-3", "G3"), ("P-S61c-4", "G4"),
                   ("P-S61c-5", "G5"))
        push!(S, "  $p: $(G[g] ? "held" : "FAILED")")
    end
    allpass = all(values(G))
    push!(S, "  all gates: $(allpass ? "PASS" : "FAIL")")
    text = join([head; L1; L5; S], "\n") * "\n"
    print(text)
    (DEV || READONLY) || write(OUT, text)
    exit(allpass ? 0 : 1)
end

main()
