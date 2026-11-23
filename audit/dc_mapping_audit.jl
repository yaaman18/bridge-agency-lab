# Read-only audit of Lab's Bool/DC semantic mapping vulnerabilities (discussion/notes/D-BOOL-MAPPING.md).
# Checks four countermeasures without modifying core/, formal/, or ~/bridge-protocol:
#   1. Canonical mapping_spec_hash (SHA-256 of FEATURES/CROSS/ALPHA_FEATURES/lab_gate/dc_record/dc_window + source files).
#   2. Countermeasure #1 (perm cross! 31-step window straddling): compares standard dc_window vs boundary-split dc_window
#      across a real body_org_run trajectory with REVR = 2000 (testing falsification: any check_dc or value_gfp diff?).
#   3. Countermeasure #3 (alpha declaration vs empirical intervention): checks ALPHA_FEATURES + lab_gate against actual
#      outward receptor flips under world (y>0 / y==0) vs non-world scripted phases (+ negative control).
#   4. Countermeasure #4 (length(onpatch) <= 1 guard & via non-coupled receptor r5/r6 sensitivity): checks onpatch<=1 on
#      every step and whether filtering uncoupled receptors out of via changes coupled-receptor value_gfp or ranking.
# Usage: julia --project=. audit/dc_mapping_audit.jl
using SHA, JSON

const ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ROOT, "core", "LabCore.jl"))
using .LabCore
using .LabCore: DCStep, DCWindow, Circuit, nu_fin, value_gfp, ALPHA_FEATURES, lab_gate, unit, coupled

sha_file(p) = bytes2hex(open(sha256, p))
sha_str(s) = bytes2hex(sha256(Vector{UInt8}(codeunits(s))))

function extract_block(path, start_pat, end_pat)
    txt = read(path, String)
    i = findfirst(start_pat, txt); i === nothing && error("start anchor not found in $path: $start_pat")
    j = findnext(end_pat, txt, i[1]); j === nothing && error("end anchor not found in $path: $end_pat")
    return txt[i[1]:j[end]]
end

# 1. Canonical mapping_spec_hash
function compute_mapping_hash()
    p_cir = joinpath(ROOT, "core", "circuit.jl")
    p_dc  = joinpath(ROOT, "core", "dc.jl")
    p_ln  = joinpath(ROOT, "formal", "LabCircuit.lean")
    b_feat = extract_block(p_cir, "const FEATURES = ", "feature(perm, s) = FEATURES[perm[s]][2]")
    b_dc   = extract_block(p_dc, "const DC_L = ", "    DCWindow(copy(last.kept), copy(last.on), rep, aff, via)\nend")
    spec_payload = "===FEATURES===\n" * b_feat * "\n===DC_MAP===\n" * b_dc * "\n"
    return Dict(
        "mapping_spec_hash" => sha_str(spec_payload),
        "core_circuit_sha256" => sha_file(p_cir),
        "core_dc_sha256" => sha_file(p_dc),
        "formal_labcircuit_sha256" => sha_file(p_ln),
    )
end

# 2 & 4. Pure-core trajectory with REVR = 2000: cross! straddling + onpatch<=1 + via sensitivity
function audit_trajectory(; seed::Int = 1, steps::Int = 3000, revr::Int = 2000)
    recs = DCStep[]
    perms = Vector{Vector{Int}}()
    onpatch_lens = Int[]
    b = newborn(false)
    st = init(b)
    noise = Mulberry(seed)
    # Standard raising (800 steps) then world phase with cross!(perm) at step revr
    for t in 0:steps-1
        t == revr && cross!(b.perm)
        phase = t < 800 ? "nursery" : "world"
        # Periodic contrasting yields so both patches alternate high/0 and trigger confirmations & DC
        y1 = (t % 40 < 20) ? 4.0 : 0.0
        y2 = (t % 40 < 20) ? 0.0 : 4.0
        y = [y1, y2, 0.0]
        out = step!(st, b, y; noise = noise, contrast = :bin3, idle_first = true, core_gate = true)
        onp = [m for m in out.acting if b.patch[m] <= 2]
        push!(onpatch_lens, length(onp))
        push!(perms, copy(b.perm))
        push!(recs, dc_record(b, out, st; partner_live = false, y = y, phase = phase))
    end

    max_onpatch = maximum(onpatch_lens)
    straddle_windows = 0
    dc_diff_count = 0
    clause_diffs = Dict("self" => 0, "smc" => 0, "act" => 0, "bound" => 0)
    vgfp_coupled_diffs = 0
    vgfp_all_diffs = 0
    vgfp_max_abs_diff = 0

    # Via uncoupled receptor (r5=noise, r6=clock3) sensitivity across all world windows
    via_world_windows = 0
    via_uncoupled_nonzero = 0
    via_coupled_diff = 0
    via_rank_diff = 0

    for t in DC_L:steps
        win_recs = recs[t-DC_L+1:t]
        win_perms = perms[t-DC_L+1:t]
        b_cur = Circuit(b.names, b.kind, b.feat, b.theta, b.patch, b.edges, b.q0, b.initial, win_perms[end], b.ins)
        w_std = dc_window(b_cur, win_recs; alpha = :state)
        c_std = check_dc(b_cur, w_std)
        nu_std = nu_fin(b_cur, w_std)

        # Check perm straddling
        distinct_perms = length(unique(win_perms))
        if distinct_perms > 1
            straddle_windows += 1
            # Boundary-split window: keep only suffix sharing win_perms[end]
            first_same = findfirst(p -> p == win_perms[end], win_perms)
            w_spl = dc_window(b_cur, win_recs[first_same:end]; alpha = :state)
            c_spl = check_dc(b_cur, w_spl)
            nu_spl = nu_fin(b_cur, w_spl)
            if c_std.dc != c_spl.dc; dc_diff_count += 1; end
            for k in (:self, :smc, :act, :bound)
                if getproperty(c_std, k) != getproperty(c_spl, k); clause_diffs[string(k)] += 1; end
            end
            for u in eachindex(b_cur.names)
                b_cur.kind[u] == 'R' || continue
                v1 = value_gfp(b_cur, w_std, nu_std, u)
                v2 = value_gfp(b_cur, w_spl, nu_spl, u)
                if v1 != v2
                    vgfp_all_diffs += 1
                    vgfp_max_abs_diff = max(vgfp_max_abs_diff, abs(v1 - v2))
                    if LabCore.coupled(b_cur, w_std, u); vgfp_coupled_diffs += 1; end
                end
            end
        end

        # Via sensitivity on world-phase windows
        if t > 800
            via_world_windows += 1
            # Check if uncoupled receptors (r5, r6) have nonzero value_gfp in w_std
            uncoupled_r = [u for u in eachindex(b_cur.names) if b_cur.kind[u] == 'R' && !LabCore.coupled(b_cur, w_std, u)]
            coupled_r   = [u for u in eachindex(b_cur.names) if b_cur.kind[u] == 'R' && LabCore.coupled(b_cur, w_std, u)]
            if any(u -> value_gfp(b_cur, w_std, nu_std, u) > 0, uncoupled_r)
                via_uncoupled_nonzero += 1
            end
            # Filter uncoupled receptors from via matrix
            via_filt = copy(w_std.via)
            for u in uncoupled_r; via_filt[u, :] .= false; end
            w_filt = DCWindow(w_std.kept, w_std.on, w_std.reproduced, w_std.affects, via_filt)
            nu_filt = nu_fin(b_cur, w_filt)
            vals_std  = [value_gfp(b_cur, w_std, nu_std, u) for u in coupled_r]
            vals_filt = [value_gfp(b_cur, w_filt, nu_filt, u) for u in coupled_r]
            if vals_std != vals_filt; via_coupled_diff += 1; end
            if sortperm(vals_std) != sortperm(vals_filt); via_rank_diff += 1; end
        end
    end

    return Dict(
        "steps" => steps,
        "revr" => revr,
        "max_onpatch_per_step" => max_onpatch,
        "onpatch_le_1_pass" => max_onpatch <= 1,
        "cross_straddle_windows" => straddle_windows,
        "cross_dc_verdict_diffs" => dc_diff_count,
        "cross_clause_diffs" => clause_diffs,
        "cross_vgfp_all_receptor_diffs" => vgfp_all_diffs,
        "cross_vgfp_coupled_receptor_diffs" => vgfp_coupled_diffs,
        "cross_vgfp_max_abs_diff" => vgfp_max_abs_diff,
        "via_world_windows" => via_world_windows,
        "via_uncoupled_r5r6_nonzero_windows" => via_uncoupled_nonzero,
        "via_coupled_vgfp_diffs_after_filter" => via_coupled_diff,
        "via_coupled_rank_diffs_after_filter" => via_rank_diff,
    )
end

# 3. Empirical intervention audit of ALPHA_FEATURES + lab_gate (Countermeasure #3)
# Tests whether motor m acting on patch p in core/matter + core/body_org yield semantics can change each receptor feature
# across: (a) world phase with y[p] > 0, (b) world phase with y[p] == 0, (c) non-world (scripted) phase,
# plus negative control (mutating ALPHA_FEATURES must fail the audit).
function audit_alpha_intervention()
    U = 0.02
    # Empirical reach of motor m (patch p in {1,2}) under (in_world, ypos):
    # Can executing act=[p] vs act=[] change feature f evaluated on the post-harvest y' = [min(5, floor(pool'/U+1e-9))]
    # across a grid of pre-act pool states consistent with (y[1]>0, y[2]>0)?
    function empirical_reach(p::Int, in_world::Bool, ypos::NTuple{2,Bool})
        reached = Set{Int}()
        # Grid of pool states spanning 0..6*U in steps of 0.5*U
        grid = [k * 0.5 * U for k in 0:12]
        for p1 in grid, p2 in grid
            y_pre = [min(5.0, floor(p1 / U + 1e-9)), min(5.0, floor(p2 / U + 1e-9))]
            ((y_pre[1] > 0) == ypos[1] && (y_pre[2] > 0) == ypos[2]) || continue
            # No-act vs act on patch p: in world phase, acting harvests allocate(offer)[p] * U from pool[p]
            # (body_org.jl:132-136); in scripted phases, yields are scripted and unaffected by acts.
            y_noact = y_pre
            if in_world
                offer = [0.0, 0.0]; offer[p] = y_pre[p]
                d = allocate(offer)
                pool_act = [p1, p2]
                pool_act[p] = max(0.0, pool_act[p] - d[p] * U)
                y_act = [min(5.0, floor(pool_act[1] / U + 1e-9)), min(5.0, floor(pool_act[2] / U + 1e-9))]
            else
                y_act = y_pre
            end
            for f in 1:8   # r1..r8 of newborn(false)
                # Deterministic features (r5=noise, r6=clock3 do not depend on y)
                fn = FEATURES[f][2]
                r_no = fn([y_noact[1], y_noact[2], 0.0, 0.0], 1, () -> 0.25)
                r_ac = fn([y_act[1], y_act[2], 0.0, 0.0], 1, () -> 0.25)
                if r_no != r_ac; push!(reached, f); end
            end
        end
        return sort(collect(reached))
    end

    b = newborn(false)
    cases = []
    all_match = true
    for in_world in (true, false), yp1 in (true, false), yp2 in (true, false)
        dummy = DCStep(falses(length(b.edges)), falses(length(b.names)), Int[], Tuple{Int,Int}[], Tuple{Int,Int}[], false, in_world, (yp1, yp2))
        for (mn, p) in (("m1", 1), ("m2", 2))
            m = unit(b, mn)
            decl = lab_gate(b, dummy, m) ? sort(ALPHA_FEATURES[mn]) : Int[]
            emp  = empirical_reach(p, in_world, (yp1, yp2))
            ok = (decl == emp)
            all_match &= ok
            push!(cases, Dict("motor" => mn, "in_world" => in_world, "ypos" => [yp1, yp2], "declared" => decl, "empirical" => emp, "match" => ok))
        end
    end
    # Negative control: drop feature 1 from m1's declared list -> must mismatch
    bad_decl = sort(filter(!=(1), ALPHA_FEATURES["m1"]))
    neg_caught = (bad_decl != empirical_reach(1, true, (true, true)))
    return Dict("n_cases" => length(cases), "all_match" => all_match, "neg_control_caught" => neg_caught, "cases" => cases)
end

function main()
    h = compute_mapping_hash()
    tr = audit_trajectory()
    al = audit_alpha_intervention()
    out = Dict(
        "date" => "2026-11-23",
        "phenomenal_claim" => "not_certified",
        "hashes" => h,
        "trajectory_audit" => tr,
        "alpha_intervention_audit" => al,
    )
    out_path = joinpath(ROOT, "audit", "results-dc-mapping-audit.json")
    open(out_path, "w") do io
        JSON.print(io, out, 2)
    end
    println("=== DC Semantic Mapping Audit ===")
    println("mapping_spec_hash: ", h["mapping_spec_hash"])
    println("core/circuit.jl:   ", h["core_circuit_sha256"][1:16], "...  core/dc.jl: ", h["core_dc_sha256"][1:16], "...")
    println("[#1 perm cross! straddling] windows=", tr["cross_straddle_windows"],
            ", dc_verdict_diffs=", tr["cross_dc_verdict_diffs"],
            ", clause_diffs=", tr["cross_clause_diffs"],
            ", vgfp_coupled_diffs=", tr["cross_vgfp_coupled_receptor_diffs"],
            ", vgfp_all_diffs=", tr["cross_vgfp_all_receptor_diffs"],
            ", max_abs_diff=", tr["cross_vgfp_max_abs_diff"])
    println("[#3 alpha intervention]     cases=", al["n_cases"],
            ", all_match=", al["all_match"],
            ", neg_control_caught=", al["neg_control_caught"])
    println("[#4 onpatch<=1 & via]       max_onpatch=", tr["max_onpatch_per_step"],
            " (pass=", tr["onpatch_le_1_pass"], ")",
            ", r5/r6_nonzero_via_windows=", tr["via_uncoupled_r5r6_nonzero_windows"], "/", tr["via_world_windows"],
            ", coupled_vgfp_diffs_after_filter=", tr["via_coupled_vgfp_diffs_after_filter"],
            ", coupled_rank_diffs=", tr["via_coupled_rank_diffs_after_filter"])
    println("saved: ", out_path)
    (al["all_match"] && al["neg_control_caught"] && tr["onpatch_le_1_pass"]) || exit(1)
end

main()
