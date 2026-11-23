# Seam verification gates GS1-GS4 for the canonical Julia minimal 4-seam prototype (r2).
# Scope: specification seam verification only; Rust bed generality remains deferred to Phase 6.
# Does NOT modify core/, experiments/nesting_cpc_c/, formal/, rust/, or ~/bridge-protocol.
# Does NOT consume main-sequence evaluation seeds (uses fixed seam-test seeds only).

using SHA
using Printf

const ROOT = abspath(joinpath(@__DIR__, "..", ".."))

include(joinpath(ROOT, "core", "LabCore.jl"))
include(joinpath(ROOT, "experiments", "nesting_cpc_c", "NestingCPCC.jl"))
include(joinpath(@__DIR__, "bed.jl"))
include(joinpath(@__DIR__, "adapter_aue_a.jl"))
include(joinpath(@__DIR__, "adapter_aue_b.jl"))

using .AUESeamBed
using .AdapterAUEA
using .AdapterAUEB
using .LabCore
using .NestingCPCC

function check_expect_throw(T::Type, f::Function)
    try
        f()
        return (false, "expected $T but succeeded")
    catch e
        if e isa T
            return (true, string(e))
        else
            return (false, "expected $T, got $(typeof(e)): $(e)")
        end
    end
end

function run_all_gates()
    results = Dict{String,Any}()
    all_pass = true

    function record!(name::String, ok::Bool, detail::Dict{String,Any})
        detail["pass"] = ok
        results[name] = detail
        if !ok
            all_pass = false
        end
        @printf("[%s] %s\n", ok ? "PASS" : "FAIL", name)
    end

    # ------------------------------------------------------------------
    # GS1: 2-Species Bed Invariance + Per-Step Full-State Direct-Core Equivalence + Text-Only Replay
    # ------------------------------------------------------------------
    bed_src = read(joinpath(@__DIR__, "bed.jl"), String)
    forbidden_tokens = ["AUE-A", "AUE-B", "AUEA", "AUEB", "OneLife", "LabCore", "NestingCPCC", "CPC-Prolif", "Runaway-Cancer", "body_org"]
    leaked_tokens = [tok for tok in forbidden_tokens if occursin(tok, bed_src)]
    bed_species_free = isempty(leaked_tokens)

    # AUE-A (OneLife L2): 300 steps through bed.jl vs per-step direct LabCore.body_org_run (ON_STEP)
    seed_a = 1
    steps_a = 300
    ad_a = AUEAAdapter()
    in_a = make_aue_a_inputs(steps_a)
    bed_digests_a = String[]
    res_a1 = run_species!(ad_a, "aue-a-seam-1", make_aue_a_initial_state(seed_a), in_a;
                          on_step = (s, st, d) -> push!(bed_digests_a, d))
    res_a2 = run_species!(ad_a, "aue-a-seam-1", make_aue_a_initial_state(seed_a), in_a)
    rep_a = replay_from_audit(ad_a, make_aue_a_initial_state(seed_a), res_a1.audit)

    ref_digests_a = String[]
    ref_a = LabCore.body_org_run("ORG", seed_a, (
        U = 0.02, MCOST = 0.004, KC = 0.004, STEPS = steps_a,
        CONTRAST = "bin3", IDLE = true, GATE = true,
        ON_STEP = obs -> push!(ref_digests_a, canonical_aue_a_digest(obs.w, obs.pool, obs.circuit, obs.noise)),
    ))
    aue_a_det = (res_a1.final_digest == res_a2.final_digest) && (rep_a.final_digest == res_a1.final_digest) &&
                verify_audit_chain(res_a1.audit)
    aue_a_per_step_match = (length(bed_digests_a) == steps_a) && (bed_digests_a == ref_digests_a) &&
                           (LabCore.nconstituents(res_a1.state.w) == ref_a["final"])

    # AUE-B (S61c CPC pruning): 120 steps through bed.jl vs per-step direct NestingCPCC (including full theta matrices)
    seed_b_cpc = 962
    ad_b_cpc = AUEBAdapter(; organ_type = "cpc_local_link_pruning")
    bed_digests_b = String[]
    st_b1, in_b, tape_b, thetas_b = make_aue_b_initial_state(:CPC, seed_b_cpc)
    res_b1 = run_species!(ad_b_cpc, "aue-b-cpc-1", st_b1, in_b;
                          on_step = (s, st, d) -> push!(bed_digests_b, d))
    st_b2, _, _, _ = make_aue_b_initial_state(:CPC, seed_b_cpc)
    res_b2 = run_species!(ad_b_cpc, "aue-b-cpc-1", st_b2, in_b)
    st_b3, _, _, _ = make_aue_b_initial_state(:CPC, seed_b_cpc)
    rep_b = replay_from_audit(ad_b_cpc, st_b3, res_b1.audit)

    # Independent step-by-step reference using NestingCPCC directly (verifying EVERY step's full state & theta)
    ref_digests_b = String[]
    sys_ref_step = NestingCPCC.init_system(:CPC, thetas_b)
    for k in 1:length(tape_b)
        NestingCPCC.step!(sys_ref_step, tape_b[k], k)
        push!(ref_digests_b, canonical_aue_b_digest(sys_ref_step))
    end
    sys_ref_run = NestingCPCC.run_config(:CPC, seed_b_cpc).sys
    aue_b_det = (res_b1.final_digest == res_b2.final_digest) && (rep_b.final_digest == res_b1.final_digest) &&
                verify_audit_chain(res_b1.audit)
    aue_b_per_step_match = (length(bed_digests_b) == length(tape_b)) && (bed_digests_b == ref_digests_b) &&
                           (canonical_aue_b_digest(sys_ref_run) == res_b1.final_digest)

    # Negative control: tamper 1 character in an audit text `input` row -> replay MUST reject
    tampered_audit = deepcopy(res_a1.audit)
    in_row_idx = findfirst(r -> r.kind == "input", tampered_audit.rows)
    orig = tampered_audit.rows[in_row_idx]
    tampered_audit.rows[in_row_idx] = AuditRow(orig.seq, orig.kind, orig.step, orig.payload * " ", orig.prev_hash, orig.hash)
    ok_replay_tamper, msg_replay_tamper = check_expect_throw(ChainIntegrityError, () ->
        replay_from_audit(ad_a, make_aue_a_initial_state(seed_a), tampered_audit))

    header_a_ok = occursin(ad_a.spec.spec_sha256, res_a1.audit.rows[1].payload) &&
                  occursin(ad_a.spec.mapping_spec_hash, res_a1.audit.rows[1].payload) &&
                  occursin("phenomenal_claim=not_certified", res_a1.audit.rows[1].payload)
    header_b_ok = occursin(ad_b_cpc.spec.spec_sha256, res_b1.audit.rows[1].payload) &&
                  occursin(ad_b_cpc.spec.mapping_spec_hash, res_b1.audit.rows[1].payload) &&
                  occursin("phenomenal_claim=not_certified", res_b1.audit.rows[1].payload)

    gs1_ok = bed_species_free && aue_a_det && aue_a_per_step_match && aue_b_det && aue_b_per_step_match &&
             ok_replay_tamper && header_a_ok && header_b_ok
    record!("GS1_two_species_bed_invariance", gs1_ok, Dict{String,Any}(
        "bed_species_free" => bed_species_free,
        "leaked_tokens" => leaked_tokens,
        "aue_a_det_and_text_replay" => aue_a_det,
        "aue_a_per_step_300_exact_match" => aue_a_per_step_match,
        "aue_a_final_digest" => res_a1.final_digest,
        "aue_a_final_constituents" => LabCore.nconstituents(res_a1.state.w),
        "aue_b_det_and_text_replay" => aue_b_det,
        "aue_b_per_step_120_full_theta_exact_match" => aue_b_per_step_match,
        "aue_b_final_digest" => res_b1.final_digest,
        "aue_b_alive" => res_b1.state.sys.alive,
        "aue_b_n_mods" => length(res_b1.state.sys.mods),
        "tampered_audit_text_rejected" => ok_replay_tamper,
        "tamper_msg" => msg_replay_tamper,
        "header_stamps_ok" => header_a_ok && header_b_ok,
    ))

    # ------------------------------------------------------------------
    # GS2: Port, Species-Boundary (Organ-Type), Budget (Step + Instantaneous + Rolling 1h Window), & Dormancy Guards
    # ------------------------------------------------------------------
    in_short = make_aue_a_inputs(5)
    ok_out_port, msg_out_port = check_expect_throw(PortViolation, () ->
        run_species!(AUEAAdapter(; inject_undeclared_port = true), "neg-port-out",
                     make_aue_a_initial_state(1), in_short))
    bad_in = [StampedInput(0, Dict{String,Any}("g1" => 1.0, "g2" => 1.0, "hidden_cheat" => 99.0))]
    ok_in_port, msg_in_port = check_expect_throw(PortViolation, () ->
        run_species!(ad_a, "neg-port-in", make_aue_a_initial_state(1), bad_in))
    ok_organ, msg_organ = check_expect_throw(SpeciesBoundaryViolation, () ->
        run_species!(AUEAAdapter(; organ_type = "unauthorized_llm_controller"), "neg-organ",
                     make_aue_a_initial_state(1), in_short))
    res_var = run_species!(AUEAAdapter(; organ_type = "L2_circuit_bin3_trm_c1"), "pos-organ-variant",
                           make_aue_a_initial_state(1), in_short)
    ok_organ_pos = verify_audit_chain(res_var.audit) && res_var.ledger.steps_completed == 5
    ok_budget_step, msg_budget_step = check_expect_throw(BudgetViolation, () ->
        run_species!(AUEAAdapter(; inject_ops_override = 10001), "neg-budget-step",
                     make_aue_a_initial_state(1), in_short))

    # Instantaneous fine-step wall-clock rate overflow (Counterexample 2a)
    tight_rate_spec = SpeciesSpec(
        "Neg-FineStep-TightRate", "0.1.0", "test", "test",
        Set(["L2_circuit_bin3"]), Set(["g1", "g2"]), Set(["act_patch_1", "act_patch_2", "alive", "constituents"]),
        0.01,   # 10 ms granularity => 360,000 steps/hour
        1000,   # per-step cap looks small
        100000, # hourly cap: 128 * 360,000 = 46,080,000 > 100,000 -> MUST CATCH
        0.001, 4, ad_a.spec.mapping_spec_hash, "not_certified", "0"^64,
    )
    ad_tight_rate = AUEAAdapter(tight_rate_spec, 0.02, 0.004, 0.004, "L2_circuit_bin3", false, nothing, false)
    ok_budget_rate, msg_budget_rate = check_expect_throw(BudgetViolation, () ->
        run_species!(ad_tight_rate, "neg-budget-rate", make_aue_a_initial_state(1), in_short))

    # Rolling 3600s sliding window boundary check (Counterexample 2b):
    # 600s/step => 6 steps = 3600s (1 hour). Cap = 600 ops/h, 100 ops/step passes at step 6 (600<=600) AND step 7 (window slides: still 600<=600).
    # With 101 ops/step, instantaneous rate = 606 > 600 caught; with cap=600, step_gran=600s, ops=100 passes 8 steps across 1h boundary!
    # To isolate rolling window WITHOUT triggering instantaneous rate: test variable ops via step_gran=1200s (3 steps/hr), cap=300 ops/hr, ops=100 -> 4 steps passes (window slides at step 4: 300<=300),
    # and cap=299 with step_gran=1200s, ops=100 -> caught on step 1 (rate 300 > 299). For cumulative sliding window specifically:
    # cap = 300, step_gran = 1800s (2 steps/hr => rate=200<=300), ops = 100 -> 2 steps = 200<=300; with step_gran=900s (4 steps/hr), cap=450, ops=100 -> rate=400<=450, 5 steps across 1h boundary => window slides from 400 to 400 (PASS).
    # And with step_gran=1000s (3.6 steps/hr), cap=360, ops=100 -> rate=360<=360, steps 1..3 = 300, step 4 at t=4000s has win_start=400s => includes steps 1,2,3,4 = 400 > 360 -> CAUGHT by rolling window!
    roll_spec = SpeciesSpec(
        "Test-Rolling-1h-Window", "0.1.0", "test", "test",
        Set(["L2_circuit_bin3"]), Set(["g1", "g2"]), Set(["act_patch_1", "act_patch_2", "alive", "constituents"]),
        1000.0, # 3.6 steps/hour; 100 * 3.6 = 360 <= 360 (passes instantaneous rate)
        200,
        360,    # steps 1..3 (t=1000,2000,3000) sum=300<=360 PASS; step 4 (t=4000, win_start=400) includes t=1000..4000 => 400>360 CATCH!
        0.001, 4, ad_a.spec.mapping_spec_hash, "not_certified", "0"^64,
    )
    ad_roll = AUEAAdapter(roll_spec, 0.02, 0.004, 0.004, "L2_circuit_bin3", false, 100, false)
    res_roll_pre = run_species!(ad_roll, "pos-roll-3steps", make_aue_a_initial_state(1), make_aue_a_inputs(3))
    ok_roll_pre = res_roll_pre.ledger.steps_completed == 3
    ok_roll_cross, msg_roll_cross = check_expect_throw(BudgetViolation, () ->
        run_species!(ad_roll, "neg-roll-4steps", make_aue_a_initial_state(1), make_aue_a_inputs(4)))

    # Free dormancy / seed-bank memory caught (Counterexample 1)
    ok_free_dorm, msg_free_dorm = check_expect_throw(DormancyAccountingViolation, () ->
        run_species!(AUEAAdapter(; inject_free_dormancy = true), "neg-free-dorm",
                     make_aue_a_initial_state(1; emit_spore_at = 2), in_short))

    gs2_ok = ok_out_port && ok_in_port && ok_organ && ok_organ_pos && ok_budget_step &&
             ok_budget_rate && ok_roll_pre && ok_roll_cross && ok_free_dorm
    record!("GS2_port_species_budget_dormancy_guards", gs2_ok, Dict{String,Any}(
        "undeclared_out_port_caught" => ok_out_port,
        "undeclared_in_port_caught" => ok_in_port,
        "disallowed_organ_caught" => ok_organ,
        "allowed_organ_variant_passed" => ok_organ_pos,
        "step_budget_overflow_caught" => ok_budget_step,
        "wall_clock_rate_overflow_caught" => ok_budget_rate,
        "rolling_1h_window_before_boundary_passed" => ok_roll_pre,
        "rolling_1h_window_crossing_caught" => ok_roll_cross,
        "free_dormancy_caught" => ok_free_dorm,
        "messages" => Dict(
            "out_port" => msg_out_port, "in_port" => msg_in_port, "organ" => msg_organ,
            "step_budget" => msg_budget_step, "wall_rate" => msg_budget_rate,
            "roll_window" => msg_roll_cross, "free_dorm" => msg_free_dorm,
        ),
    ))

    # ------------------------------------------------------------------
    # GS3: 3-Way Termination Separation (incl. Full Replay), Zero Post-Death Commits, & Pre-Death Spore Lineage
    # ------------------------------------------------------------------
    ad_b_run = AUEBAdapter(; organ_type = "cpc_runaway_control")
    st_run, in_run, _, _ = make_aue_b_initial_state(:Runaway, 962; emit_spore_at = 5, spore_id = "spore-endo-5")
    res_meta = run_species!(ad_b_run, "aue-b-runaway-dead", st_run, in_run)
    death_s = res_meta.ledger.death_step
    commits_after_death = count(r -> r.kind == "commit" && r.step > death_s, res_meta.audit.rows)
    ok_zero_post_death_commits = (commits_after_death == 0) && (res_meta.ledger.steps_completed == death_s) &&
                                 (res_meta.audit.rows[end].kind == "termination")
    # Replay metabolic death from audit text -> exact full chain + termination match
    st_run_rep, _, _, _ = make_aue_b_initial_state(:Runaway, 962; emit_spore_at = 5, spore_id = "spore-endo-5")
    rep_meta = replay_from_audit(ad_b_run, st_run_rep, res_meta.audit)
    ok_meta_replay = (rep_meta.ledger.termination == METABOLIC_OR_ORG_DEATH) &&
                     (rep_meta.audit.rows[end].hash == res_meta.audit.rows[end].hash)

    ok_meta_death = (res_meta.ledger.termination == METABOLIC_OR_ORG_DEATH) &&
                    (death_s !== nothing) && (death_s > 5) &&
                    (res_meta.ledger.cumulative_dormancy_upkeep > 0.0) &&
                    ok_zero_post_death_commits && ok_meta_replay
    child = germinate_lineage_child(res_meta.ledger, res_meta.audit, "spore-endo-5", "aue-b-child-1")
    ok_child = (!child.same_individual) && child.lineage_child && child.verified_pre_death

    # External post-death spore attempt rejected as ProhibitedRescueError (no internal test hook)
    ok_post_spore, msg_post_spore = check_expect_throw(ProhibitedRescueError, () ->
        attempt_post_death_spore!(res_meta.ledger, res_meta.audit, "illegal-rescue-spore", death_s + 1))

    # Spore requested on exact death step itself rejected as ProhibitedRescueError
    st_run_deathstep, in_run_deathstep, _, _ = make_aue_b_initial_state(:Runaway, 962; emit_spore_at = death_s, spore_id = "death-step-spore")
    ok_deathstep_spore, msg_deathstep_spore = check_expect_throw(ProhibitedRescueError, () ->
        run_species!(ad_b_run, "aue-b-deathstep-spore", st_run_deathstep, in_run_deathstep))

    # Non-metabolic termination verified + FULL REPLAY verification (code, evidence, tail hash)
    res_hw = run_species!(ad_a, "aue-a-powerloss", make_aue_a_initial_state(1), in_short;
                          external_termination = (NON_METABOLIC_TERMINATION_VERIFIED, "boot_id=851197f9;dmesg=power_loss"))
    rep_hw = replay_from_audit(ad_a, make_aue_a_initial_state(1), res_hw.audit)
    ok_hw = (res_hw.ledger.termination == NON_METABOLIC_TERMINATION_VERIFIED) && (res_hw.ledger.death_step === nothing) &&
            (rep_hw.ledger.termination == NON_METABOLIC_TERMINATION_VERIFIED) &&
            (rep_hw.ledger.termination_evidence == "boot_id=851197f9;dmesg=power_loss") &&
            (rep_hw.audit.rows[end].hash == res_hw.audit.rows[end].hash)
    ok_hw_no_ev, _ = check_expect_throw(ChainIntegrityError, () ->
        run_species!(ad_a, "aue-a-powerloss-noev", make_aue_a_initial_state(1), in_short;
                     external_termination = (NON_METABOLIC_TERMINATION_VERIFIED, "   ")))

    # Unexplained truncation + FULL REPLAY verification (code, evidence, tail hash)
    res_trunc = run_species!(ad_a, "aue-a-trunc", make_aue_a_initial_state(1), in_short;
                             external_termination = (UNEXPLAINED_TRUNCATION, ""))
    rep_trunc = replay_from_audit(ad_a, make_aue_a_initial_state(1), res_trunc.audit)
    ok_trunc = (res_trunc.ledger.termination == UNEXPLAINED_TRUNCATION) && (res_trunc.ledger.death_step === nothing) &&
               (rep_trunc.ledger.termination == UNEXPLAINED_TRUNCATION) &&
               (rep_trunc.audit.rows[end].hash == res_trunc.audit.rows[end].hash)
    ok_3way_distinct = length(unique([res_meta.ledger.termination, res_hw.ledger.termination, res_trunc.ledger.termination])) == 3

    gs3_ok = ok_meta_death && ok_child && ok_post_spore && ok_deathstep_spore && ok_hw && ok_hw_no_ev && ok_trunc && ok_3way_distinct
    record!("GS3_termination_3way_and_predeath_spore", gs3_ok, Dict{String,Any}(
        "metabolic_death_confirmed" => ok_meta_death,
        "metabolic_death_step" => death_s,
        "zero_commits_after_death" => ok_zero_post_death_commits,
        "metabolic_death_replay_ok" => ok_meta_replay,
        "pre_death_spore_lineage_child" => ok_child,
        "external_post_death_spore_rejected" => ok_post_spore,
        "death_step_spore_rejected" => ok_deathstep_spore,
        "non_metabolic_verified_and_replay_ok" => ok_hw,
        "non_metabolic_empty_evidence_rejected" => ok_hw_no_ev,
        "unexplained_truncation_and_replay_ok" => ok_trunc,
        "three_way_distinct" => ok_3way_distinct,
        "messages" => Dict("post_spore" => msg_post_spore, "deathstep_spore" => msg_deathstep_spore),
    ))

    # ------------------------------------------------------------------
    # GS4: Shared-Medium Double-Chain & event_ref Double-Spend Guard (Parsed Directly From Audit Text)
    # ------------------------------------------------------------------
    medium_ok = SharedMediumAudit("shared-patch-medium-1")
    in_shared_1 = StampedInput[]
    in_shared_2 = StampedInput[]
    for t in 0:4
        record_medium_event!(medium_ok, "ev-m-$(t)", t, 5.0)
        push!(in_shared_1, StampedInput(t, Dict{String,Any}("g1" => 3.0, "g2" => 0.0), [("ev-m-$(t)", 3.0)]))
        push!(in_shared_2, StampedInput(t, Dict{String,Any}("g1" => 2.0, "g2" => 0.0), [("ev-m-$(t)", 2.0)]))
    end
    r_ind1 = run_species!(ad_a, "ind-1", make_aue_a_initial_state(1), in_shared_1)
    r_ind2 = run_species!(ad_a, "ind-2", make_aue_a_initial_state(2), in_shared_2)
    ok_shared_pass = verify_shared_medium(medium_ok, [r_ind1.audit, r_ind2.audit])

    # Negative control 4a: double-spend (3.0 + 3.0 = 6.0 > 5.0) parsed directly from hash-chained input rows
    medium_ds = SharedMediumAudit("shared-patch-medium-ds")
    in_ds_1 = StampedInput[]
    in_ds_2 = StampedInput[]
    for t in 0:4
        record_medium_event!(medium_ds, "ev-ds-$(t)", t, 5.0)
        push!(in_ds_1, StampedInput(t, Dict{String,Any}("g1" => 3.0, "g2" => 0.0), [("ev-ds-$(t)", 3.0)]))
        push!(in_ds_2, StampedInput(t, Dict{String,Any}("g1" => 3.0, "g2" => 0.0), [("ev-ds-$(t)", 3.0)]))
    end
    r_ds1 = run_species!(ad_a, "ind-ds-1", make_aue_a_initial_state(1), in_ds_1)
    r_ds2 = run_species!(ad_a, "ind-ds-2", make_aue_a_initial_state(2), in_ds_2)
    ok_ds_caught, msg_ds = check_expect_throw(DoubleSpendViolation, () ->
        verify_shared_medium(medium_ds, [r_ds1.audit, r_ds2.audit]))

    # Negative control 4b: stripping `|refs=...` from audit row text to hide claim breaks hash chain -> caught!
    tampered_ds_audit = deepcopy(r_ds2.audit)
    in_ds_idx = findfirst(r -> r.kind == "input", tampered_ds_audit.rows)
    orig_ds = tampered_ds_audit.rows[in_ds_idx]
    stripped_payload = split(orig_ds.payload, "|refs=")[1] * "|refs="
    tampered_ds_audit.rows[in_ds_idx] = AuditRow(orig_ds.seq, orig_ds.kind, orig_ds.step, stripped_payload, orig_ds.prev_hash, orig_ds.hash)
    ok_ds_strip_caught, msg_ds_strip = check_expect_throw(ChainIntegrityError, () ->
        verify_shared_medium(medium_ds, [r_ds1.audit, tampered_ds_audit]))

    gs4_ok = ok_shared_pass && ok_ds_caught && ok_ds_strip_caught
    record!("GS4_shared_medium_event_ref_doublespend", gs4_ok, Dict{String,Any}(
        "valid_split_passed" => ok_shared_pass,
        "double_spend_caught" => ok_ds_caught,
        "stripped_ref_tamper_caught" => ok_ds_strip_caught,
        "double_spend_msg" => msg_ds,
        "strip_tamper_msg" => msg_ds_strip,
    ))

    # ------------------------------------------------------------------
    # Write minimal deterministic JSON report (stdlib only)
    # ------------------------------------------------------------------
    function json_escape(s::AbstractString)
        s = replace(s, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t")
        return "\"$s\""
    end
    function to_json(x, indent::Int = 0)
        pad = " "^indent
        if x === nothing
            return "null"
        elseif x isa Bool
            return x ? "true" : "false"
        elseif x isa Integer
            return string(x)
        elseif x isa AbstractFloat
            return @sprintf("%.12g", x)
        elseif x isa AbstractString || x isa Symbol
            return json_escape(string(x))
        elseif x isa AbstractVector
            isempty(x) && return "[]"
            items = [to_json(v, indent + 2) for v in x]
            return "[" * join(items, ", ") * "]"
        elseif x isa AbstractDict
            ks = sort(collect(keys(x)))
            isempty(ks) && return "{}"
            lines = ["$(pad)  $(json_escape(string(k))): $(to_json(x[k], indent + 2))" for k in ks]
            return "{\n" * join(lines, ",\n") * "\n$(pad)}"
        else
            return json_escape(string(x))
        end
    end

    report = Dict{String,Any}(
        "phenomenal_claim" => "not_certified",
        "scope" => "julia_specification_seam_only_rust_generality_deferred_to_phase6",
        "revision" => "r2",
        "all_pass" => all_pass,
        "hashes" => Dict{String,Any}(
            "bed_jl_sha256" => bytes2hex(sha256(read(joinpath(@__DIR__, "bed.jl")))),
            "species_aue_a_toml_sha256" => ad_a.spec.spec_sha256,
            "species_aue_b_toml_sha256" => ad_b_cpc.spec.spec_sha256,
        ),
        "gates" => results,
    )
    out_path = joinpath(@__DIR__, "results-seam-gates.json")
    write(out_path, to_json(report) * "\n")

    println("\nOVERALL: ", all_pass ? "ALL GATES PASS (GS1-GS4, r2)" : "FAIL")
    all_pass || exit(1)
end

run_all_gates()
