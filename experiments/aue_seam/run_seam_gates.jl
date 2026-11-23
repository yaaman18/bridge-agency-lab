# Seam verification gates GS1-GS5 for the canonical Julia minimal 4-seam prototype.
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
    # GS1: 2-Species Bed Invariance + Direct-Core Equivalence + Determinism + Replay
    # ------------------------------------------------------------------
    bed_src = read(joinpath(@__DIR__, "bed.jl"), String)
    forbidden_tokens = ["AUE-A", "AUE-B", "AUEA", "AUEB", "OneLife", "LabCore", "NestingCPCC", "CPC-Prolif", "Runaway-Cancer", "body_org"]
    leaked_tokens = [tok for tok in forbidden_tokens if occursin(tok, bed_src)]
    bed_species_free = isempty(leaked_tokens)

    # AUE-A (OneLife L2): 300 steps through bed.jl vs direct LabCore.body_org_run
    seed_a = 1
    steps_a = 300
    ad_a = AUEAAdapter()
    in_a = make_aue_a_inputs(steps_a)
    res_a1 = run_species!(ad_a, "aue-a-seam-1", make_aue_a_initial_state(seed_a), in_a)
    res_a2 = run_species!(ad_a, "aue-a-seam-1", make_aue_a_initial_state(seed_a), in_a)
    rep_a = replay_from_audit(ad_a, make_aue_a_initial_state(seed_a), res_a1.audit)

    ref_a = LabCore.body_org_run("ORG", seed_a, (U = 0.02, MCOST = 0.004, KC = 0.004, STEPS = steps_a,
                                                 CONTRAST = "bin3", IDLE = true, GATE = true))
    aue_a_det = (res_a1.final_digest == res_a2.final_digest) && (rep_a.final_digest == res_a1.final_digest) &&
                verify_audit_chain(res_a1.audit)
    aue_a_ref_match = (LabCore.nconstituents(res_a1.state.w) == ref_a["final"]) &&
                      (res_a1.state.nActs == ref_a["nActs"]) &&
                      isapprox(res_a1.state.moved, ref_a["moved"]; atol = 1e-12) &&
                      isapprox(res_a1.state.upkeep, ref_a["upkeep"]; atol = 1e-12) &&
                      isapprox(res_a1.state.spent, ref_a["spent"]; atol = 1e-12)

    # AUE-B (S61c CPC pruning): BOTH :CPC (survives with pruning) and :Runaway (dies metabolically)
    seed_b_cpc = 962       # known S61c eval seed (read-only seam check; does not alter S61c)
    ad_b_cpc = AUEBAdapter(; organ_type = "cpc_local_link_pruning")
    st_b1, in_b, tape_b, thetas_b = make_aue_b_initial_state(:CPC, seed_b_cpc)
    res_b1 = run_species!(ad_b_cpc, "aue-b-cpc-1", st_b1, in_b)
    st_b2, _, _, _ = make_aue_b_initial_state(:CPC, seed_b_cpc)
    res_b2 = run_species!(ad_b_cpc, "aue-b-cpc-1", st_b2, in_b)
    st_b3, _, _, _ = make_aue_b_initial_state(:CPC, seed_b_cpc)
    rep_b = replay_from_audit(ad_b_cpc, st_b3, res_b1.audit)

    sys_ref_b = NestingCPCC.run_config(:CPC, seed_b_cpc).sys
    aue_b_det = (res_b1.final_digest == res_b2.final_digest) && (rep_b.final_digest == res_b1.final_digest) &&
                verify_audit_chain(res_b1.audit)
    aue_b_ref_match = (res_b1.state.sys.alive == sys_ref_b.alive) &&
                      (length(res_b1.state.sys.mods) == length(sys_ref_b.mods)) &&
                      (res_b1.state.sys.next_id == sys_ref_b.next_id) &&
                      isapprox(res_b1.state.sys.R, sys_ref_b.R; atol = 1e-12) &&
                      isapprox(res_b1.state.sys.D, sys_ref_b.D; atol = 1e-12) &&
                      isapprox(res_b1.state.sys.h_ema, sys_ref_b.h_ema; atol = 1e-12)

    # Audit header stamps both species_spec SHA & mapping_spec_hash
    header_a_ok = occursin(ad_a.spec.spec_sha256, res_a1.audit.rows[1].payload) &&
                  occursin(ad_a.spec.mapping_spec_hash, res_a1.audit.rows[1].payload) &&
                  occursin("phenomenal_claim=not_certified", res_a1.audit.rows[1].payload)
    header_b_ok = occursin(ad_b_cpc.spec.spec_sha256, res_b1.audit.rows[1].payload) &&
                  occursin(ad_b_cpc.spec.mapping_spec_hash, res_b1.audit.rows[1].payload) &&
                  occursin("phenomenal_claim=not_certified", res_b1.audit.rows[1].payload)

    gs1_ok = bed_species_free && aue_a_det && aue_a_ref_match && aue_b_det && aue_b_ref_match && header_a_ok && header_b_ok
    record!("GS1_two_species_bed_invariance", gs1_ok, Dict{String,Any}(
        "bed_species_free" => bed_species_free,
        "leaked_tokens" => leaked_tokens,
        "aue_a_det_and_replay" => aue_a_det,
        "aue_a_ref_match" => aue_a_ref_match,
        "aue_a_final_digest" => res_a1.final_digest,
        "aue_a_final_constituents" => LabCore.nconstituents(res_a1.state.w),
        "aue_b_det_and_replay" => aue_b_det,
        "aue_b_ref_match" => aue_b_ref_match,
        "aue_b_final_digest" => res_b1.final_digest,
        "aue_b_alive" => res_b1.state.sys.alive,
        "aue_b_n_mods" => length(res_b1.state.sys.mods),
        "header_stamps_ok" => header_a_ok && header_b_ok,
    ))

    # ------------------------------------------------------------------
    # GS2: Port, Species-Boundary (Organ-Type), Budget (Step + Wall-Clock), & Free-Dormancy Guards
    # ------------------------------------------------------------------
    in_short = make_aue_a_inputs(5)
    # 2a. Undeclared output port caught
    ok_out_port, msg_out_port = check_expect_throw(PortViolation, () ->
        run_species!(AUEAAdapter(; inject_undeclared_port = true), "neg-port-out",
                     make_aue_a_initial_state(1), in_short))
    # 2b. Undeclared input port caught
    bad_in = [StampedInput(0, Dict{String,Any}("g1" => 1.0, "g2" => 1.0, "hidden_cheat" => 99.0))]
    ok_in_port, msg_in_port = check_expect_throw(PortViolation, () ->
        run_species!(ad_a, "neg-port-in", make_aue_a_initial_state(1), bad_in))
    # 2c. Organ type outside allowed_organ_types caught (Type vs Variant enforcement)
    ok_organ, msg_organ = check_expect_throw(SpeciesBoundaryViolation, () ->
        run_species!(AUEAAdapter(; organ_type = "unauthorized_llm_controller"), "neg-organ",
                     make_aue_a_initial_state(1), in_short))
    # 2d. Variant inside allowed_organ_types permitted
    res_var = run_species!(AUEAAdapter(; organ_type = "L2_circuit_bin3_trm_c1"), "pos-organ-variant",
                           make_aue_a_initial_state(1), in_short)
    ok_organ_pos = verify_audit_chain(res_var.audit) && res_var.ledger.steps_completed == 5
    # 2e. Per-step budget overflow caught
    ok_budget_step, msg_budget_step = check_expect_throw(BudgetViolation, () ->
        run_species!(AUEAAdapter(; inject_ops_override = 10001), "neg-budget-step",
                     make_aue_a_initial_state(1), in_short))
    # 2f. Wall-clock budget overflow caught (Counterexample 2: fine step granularity hiding high ops/hour)
    tight_wall_spec = SpeciesSpec(
        "Neg-FineStep-TightWall", "0.1.0", "test", "test",
        Set(["L2_circuit_bin3"]), Set(["g1", "g2"]), Set(["act_patch_1", "act_patch_2", "alive", "constituents"]),
        0.01,   # 10 ms granularity => 360,000 steps/hour
        1000,   # per-step cap looks small
        100000, # hourly cap: 128 ops/step * 360,000 steps/hr = 46,080,000 > 100,000 -> MUST CATCH
        0.001, 4, ad_a.spec.mapping_spec_hash, "not_certified", "0"^64,
    )
    ad_tight_wall = AUEAAdapter(tight_wall_spec, 0.02, 0.004, 0.004, "L2_circuit_bin3", false, nothing, false)
    ok_budget_wall, msg_budget_wall = check_expect_throw(BudgetViolation, () ->
        run_species!(ad_tight_wall, "neg-budget-wall", make_aue_a_initial_state(1), in_short))
    # 2g. Free dormancy / seed-bank memory caught (Counterexample 1)
    ok_free_dorm, msg_free_dorm = check_expect_throw(DormancyAccountingViolation, () ->
        run_species!(AUEAAdapter(; inject_free_dormancy = true), "neg-free-dorm",
                     make_aue_a_initial_state(1; emit_spore_at = 2), in_short))

    gs2_ok = ok_out_port && ok_in_port && ok_organ && ok_organ_pos && ok_budget_step && ok_budget_wall && ok_free_dorm
    record!("GS2_port_species_budget_dormancy_guards", gs2_ok, Dict{String,Any}(
        "undeclared_out_port_caught" => ok_out_port,
        "undeclared_in_port_caught" => ok_in_port,
        "disallowed_organ_caught" => ok_organ,
        "allowed_organ_variant_passed" => ok_organ_pos,
        "step_budget_overflow_caught" => ok_budget_step,
        "wall_clock_budget_overflow_caught" => ok_budget_wall,
        "free_dormancy_caught" => ok_free_dorm,
        "messages" => Dict(
            "out_port" => msg_out_port, "in_port" => msg_in_port, "organ" => msg_organ,
            "step_budget" => msg_budget_step, "wall_budget" => msg_budget_wall, "free_dorm" => msg_free_dorm,
        ),
    ))

    # ------------------------------------------------------------------
    # GS3: 3-Way Termination Separation & Pre-Death Endogenous Spore Lineage Guard
    # ------------------------------------------------------------------
    # 3a. Metabolic death on real AUE-B Runaway-Cancer + pre-death endogenous spore -> valid lineage child
    ad_b_run = AUEBAdapter(; organ_type = "cpc_runaway_control")
    st_run, in_run, _, _ = make_aue_b_initial_state(:Runaway, 962; emit_spore_at = 5, spore_id = "spore-endo-5")
    res_meta = run_species!(ad_b_run, "aue-b-runaway-dead", st_run, in_run)
    ok_meta_death = (res_meta.ledger.termination == METABOLIC_OR_ORG_DEATH) &&
                    (res_meta.ledger.death_step !== nothing) &&
                    (res_meta.ledger.death_step > 5) &&
                    (res_meta.ledger.cumulative_dormancy_upkeep > 0.0)
    child = germinate_lineage_child(res_meta.ledger, res_meta.audit, "spore-endo-5", "aue-b-child-1")
    ok_child = (!child.same_individual) && child.lineage_child && child.verified_pre_death

    # 3b. Post-death spore creation rejected as ProhibitedRescueError
    st_run2, in_run2, _, _ = make_aue_b_initial_state(:Runaway, 962)
    ok_post_spore, msg_post_spore = check_expect_throw(ProhibitedRescueError, () ->
        run_species!(ad_b_run, "aue-b-post-spore", st_run2, in_run2; post_death_spore_attempt = "illegal-rescue-spore"))
    # Also test spore requested during a step after death_step inside the run loop
    death_s = res_meta.ledger.death_step
    st_run3, in_run3, _, _ = make_aue_b_initial_state(:Runaway, 962; emit_spore_at = min(length(in_run), death_s + 2), spore_id = "late-spore")
    ok_late_spore, msg_late_spore = check_expect_throw(ProhibitedRescueError, () ->
        run_species!(ad_b_run, "aue-b-late-spore", st_run3, in_run3))

    # 3c. Non-metabolic termination verified (with external OS evidence) != metabolic death
    res_hw = run_species!(ad_a, "aue-a-powerloss", make_aue_a_initial_state(1), in_short;
                          external_termination = (NON_METABOLIC_TERMINATION_VERIFIED, "boot_id=851197f9;dmesg=power_loss"))
    ok_hw = (res_hw.ledger.termination == NON_METABOLIC_TERMINATION_VERIFIED) && (res_hw.ledger.death_step === nothing)
    # Missing OS evidence for NON_METABOLIC_TERMINATION_VERIFIED must fail
    ok_hw_no_ev, _ = check_expect_throw(ChainIntegrityError, () ->
        run_species!(ad_a, "aue-a-powerloss-noev", make_aue_a_initial_state(1), in_short;
                     external_termination = (NON_METABOLIC_TERMINATION_VERIFIED, "   ")))

    # 3d. Unexplained truncation != metabolic death && != verified hardware death
    res_trunc = run_species!(ad_a, "aue-a-trunc", make_aue_a_initial_state(1), in_short;
                             external_termination = (UNEXPLAINED_TRUNCATION, ""))
    ok_trunc = (res_trunc.ledger.termination == UNEXPLAINED_TRUNCATION) && (res_trunc.ledger.death_step === nothing)
    ok_3way_distinct = length(unique([res_meta.ledger.termination, res_hw.ledger.termination, res_trunc.ledger.termination])) == 3

    gs3_ok = ok_meta_death && ok_child && ok_post_spore && ok_late_spore && ok_hw && ok_hw_no_ev && ok_trunc && ok_3way_distinct
    record!("GS3_termination_3way_and_predeath_spore", gs3_ok, Dict{String,Any}(
        "metabolic_death_confirmed" => ok_meta_death,
        "metabolic_death_step" => res_meta.ledger.death_step,
        "pre_death_spore_lineage_child" => ok_child,
        "post_death_spore_rejected" => ok_post_spore,
        "late_inloop_spore_rejected" => ok_late_spore,
        "non_metabolic_verified_ok" => ok_hw,
        "non_metabolic_empty_evidence_rejected" => ok_hw_no_ev,
        "unexplained_truncation_ok" => ok_trunc,
        "three_way_distinct" => ok_3way_distinct,
        "messages" => Dict("post_spore" => msg_post_spore, "late_spore" => msg_late_spore),
    ))

    # ------------------------------------------------------------------
    # GS4: Shared-Medium Double-Chain & event_ref Double-Spend Guard (Counterexample 3)
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

    # Negative control: both individuals claim 3.0 against a single 5.0 medium decrement (total 6.0 > 5.0)
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

    gs4_ok = ok_shared_pass && ok_ds_caught
    record!("GS4_shared_medium_event_ref_doublespend", gs4_ok, Dict{String,Any}(
        "valid_split_passed" => ok_shared_pass,
        "double_spend_caught" => ok_ds_caught,
        "double_spend_msg" => msg_ds,
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

    println("\nOVERALL: ", all_pass ? "ALL GATES PASS (GS1-GS4)" : "FAIL")
    all_pass || exit(1)
end

run_all_gates()
