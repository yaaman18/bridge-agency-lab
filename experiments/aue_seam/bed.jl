# Canonical minimal 4-seam common bed for multi-type AUE specification verification (Julia).
# Scope: verifies specification seams only (D-AUE-SPECIES-AND-GAPS.md O30-O32, PLAN-PI5-TRM-DEPLOY.md §1.3).
# Rust runtime generality remains unasserted until Phase 6 passes a 2nd species through unmodified rust/onelife-trm.
#
# Strict invariant: this file contains ZERO species-specific logic or branches.
# phenomenal_claim = :not_certified (fixed).

module AUESeamBed

using SHA
using TOML
using Printf

export SpeciesSpec, load_species_spec,
       StampedInput, DeclaredOutput, StepCost, Budget,
       TerminationCode, RUNNING, METABOLIC_OR_ORG_DEATH,
       NON_METABOLIC_TERMINATION_VERIFIED, UNEXPLAINED_TRUNCATION,
       SporeRecord, LineageChild, Ledger, AuditRow, AuditLog,
       SharedMediumEvent, SharedMediumAudit,
       SeamError, PortViolation, SpeciesBoundaryViolation, BudgetViolation,
       DormancyAccountingViolation, AbsorbingDeathViolation, ProhibitedRescueError,
       DoubleSpendViolation, ChainIntegrityError,
       AbstractSpeciesAdapter, species_spec, state_digest, step_species,
       record_medium_event!, verify_audit_chain, verify_shared_medium,
       run_species!, replay_from_audit, germinate_lineage_child

# ------------------------------------------------------------------ Errors

abstract type SeamError <: Exception end

struct PortViolation <: SeamError
    msg::String
end
struct SpeciesBoundaryViolation <: SeamError
    msg::String
end
struct BudgetViolation <: SeamError
    msg::String
end
struct DormancyAccountingViolation <: SeamError
    msg::String
end
struct AbsorbingDeathViolation <: SeamError
    msg::String
end
struct ProhibitedRescueError <: SeamError
    msg::String
end
struct DoubleSpendViolation <: SeamError
    msg::String
end
struct ChainIntegrityError <: SeamError
    msg::String
end

Base.showerror(io::IO, e::SeamError) = print(io, typeof(e), ": ", e.msg)

# ------------------------------------------------------------------ Seam 1: SpeciesSpec

struct SpeciesSpec
    species_id::String
    spec_version::String
    substrate::String
    individual_boundary::String
    allowed_organ_types::Set{String}
    ports_in::Set{String}
    ports_out::Set{String}
    step_granularity_sec::Float64
    budget_per_step::Int
    wall_budget_per_hour::Int
    dormancy_upkeep_rate::Float64
    dormancy_max_slots::Int
    mapping_spec_hash::String
    phenomenal_claim::String
    spec_sha256::String
end

function load_species_spec(toml_path::AbstractString)::SpeciesSpec
    raw = read(toml_path)
    spec_sha = bytes2hex(sha256(raw))
    d = TOML.parse(String(raw))

    claim = String(get(d, "phenomenal_claim", ""))
    claim == "not_certified" || throw(SpeciesBoundaryViolation(
        "phenomenal_claim must be \"not_certified\", got $(repr(claim))"))

    step_gran = Float64(d["budget"]["step_granularity_sec"])
    step_gran > 0.0 || throw(BudgetViolation("step_granularity_sec must be > 0"))
    b_step = Int(d["budget"]["ops_per_step"])
    b_hour = Int(d["budget"]["ops_per_hour"])
    b_step > 0 && b_hour > 0 || throw(BudgetViolation("budget caps must be positive"))

    dorm_rate = Float64(d["dormancy"]["upkeep_rate_per_slot"])
    dorm_slots = Int(d["dormancy"]["max_slots"])
    dorm_rate > 0.0 || throw(DormancyAccountingViolation("dormancy upkeep_rate_per_slot must be > 0 (no free memory)"))
    dorm_slots >= 0 || throw(DormancyAccountingViolation("dormancy max_slots must be >= 0"))

    SpeciesSpec(
        String(d["species_id"]),
        String(d["spec_version"]),
        String(d["substrate"]),
        String(d["individual_boundary"]),
        Set{String}(String.(d["allowed_organ_types"])),
        Set{String}(String.(d["ports"]["inputs"])),
        Set{String}(String.(d["ports"]["outputs"])),
        step_gran,
        b_step,
        b_hour,
        dorm_rate,
        dorm_slots,
        String(d["mapping_spec_hash"]),
        claim,
        spec_sha,
    )
end

# ------------------------------------------------------------------ Seam 2: Port & Step Contract

struct StampedInput
    step::Int
    ports::Dict{String,Any}
    event_refs::Vector{Tuple{String,Float64}}   # (event_ref, claimed_amount) for shared-medium audit
end
StampedInput(step::Int, ports::Dict{String,Any}) = StampedInput(step, ports, Tuple{String,Float64}[])

struct DeclaredOutput
    ports::Dict{String,Any}
    organ_type::String
end

struct StepCost
    ops_used::Int
    upkeep_paid::Float64
    act_cost::Float64
    dormancy_upkeep_paid::Float64
end
StepCost(ops_used::Int, upkeep_paid::Float64, act_cost::Float64) =
    StepCost(ops_used, upkeep_paid, act_cost, 0.0)

struct Budget
    ops_per_step::Int
    ops_per_hour::Int
    step_granularity_sec::Float64
end
Budget(spec::SpeciesSpec) = Budget(spec.budget_per_step, spec.wall_budget_per_hour, spec.step_granularity_sec)

# ------------------------------------------------------------------ Seam 3: Ledger & 3-Way Termination

@enum TerminationCode begin
    RUNNING = 0
    METABOLIC_OR_ORG_DEATH = 1
    NON_METABOLIC_TERMINATION_VERIFIED = 2
    UNEXPLAINED_TRUNCATION = 3
end

struct SporeRecord
    spore_id::String
    parent_id::String
    emitted_step::Int
    audit_row_hash::String
    dormancy_cost_paid::Float64
end

struct LineageChild
    child_id::String
    parent_id::String
    source_spore_id::String
    same_individual::Bool
    lineage_child::Bool
    verified_pre_death::Bool
end

mutable struct Ledger
    individual_id::String
    termination::TerminationCode
    termination_evidence::String
    death_step::Union{Nothing,Int}
    steps_completed::Int
    cumulative_ops::Int
    cumulative_upkeep::Float64
    cumulative_act_cost::Float64
    dormancy_slots_used::Int
    cumulative_dormancy_upkeep::Float64
    spores::Vector{SporeRecord}
end
Ledger(individual_id::AbstractString) =
    Ledger(String(individual_id), RUNNING, "", nothing, 0, 0, 0.0, 0.0, 0, 0.0, SporeRecord[])

# ------------------------------------------------------------------ Hash-Chained Audit Log

struct AuditRow
    seq::Int
    kind::String          # "header" | "input" | "spore" | "commit" | "termination"
    step::Int
    payload::String
    prev_hash::String
    hash::String
end

mutable struct AuditLog
    individual_id::String
    species_id::String
    spec_sha256::String
    mapping_spec_hash::String
    phenomenal_claim::String
    rows::Vector{AuditRow}
    stamped_inputs::Vector{StampedInput}
end

const GENESIS_HASH = "0"^64

function _canonical_kv(d::Dict{String,Any})::String
    ks = sort(collect(keys(d)))
    parts = String[]
    for k in ks
        v = d[k]
        s = v isa Float64 ? @sprintf("%.17g", v) : string(v)
        push!(parts, "$k=$s")
    end
    join(parts, ";")
end

function _canonical_refs(refs::Vector{Tuple{String,Float64}})::String
    isempty(refs) && return ""
    join(["$(r[1]):$(@sprintf("%.17g", r[2]))" for r in refs], ",")
end

function _append_row!(log::AuditLog, kind::String, step::Int, payload::String)::AuditRow
    seq = length(log.rows) + 1
    prev = isempty(log.rows) ? GENESIS_HASH : log.rows[end].hash
    raw = "$(seq)|$(kind)|$(step)|$(payload)|$(prev)"
    h = bytes2hex(sha256(codeunits(raw)))
    row = AuditRow(seq, kind, step, payload, prev, h)
    push!(log.rows, row)
    row
end

function init_audit_log(individual_id::AbstractString, spec::SpeciesSpec)::AuditLog
    log = AuditLog(String(individual_id), spec.species_id, spec.spec_sha256,
                   spec.mapping_spec_hash, spec.phenomenal_claim, AuditRow[], StampedInput[])
    header_payload = "id=$(individual_id);species=$(spec.species_id);spec_sha=$(spec.spec_sha256);" *
                     "mapping_sha=$(spec.mapping_spec_hash);phenomenal_claim=$(spec.phenomenal_claim)"
    _append_row!(log, "header", 0, header_payload)
    log
end

function verify_audit_chain(log::AuditLog)::Bool
    isempty(log.rows) && return false
    prev = GENESIS_HASH
    for (idx, row) in enumerate(log.rows)
        row.seq == idx || return false
        row.prev_hash == prev || return false
        raw = "$(row.seq)|$(row.kind)|$(row.step)|$(row.payload)|$(row.prev_hash)"
        expected = bytes2hex(sha256(codeunits(raw)))
        row.hash == expected || return false
        prev = row.hash
    end
    true
end

# ------------------------------------------------------------------ Shared-Medium Double-Chain Audit

struct SharedMediumEvent
    seq::Int
    event_ref::String
    step::Int
    resource_decrement::Float64
    prev_hash::String
    hash::String
end

mutable struct SharedMediumAudit
    medium_id::String
    events::Vector{SharedMediumEvent}
    by_ref::Dict{String,SharedMediumEvent}
end
SharedMediumAudit(medium_id::AbstractString) =
    SharedMediumAudit(String(medium_id), SharedMediumEvent[], Dict{String,SharedMediumEvent}())

function record_medium_event!(m::SharedMediumAudit, event_ref::AbstractString, step::Int, decrement::Float64)::SharedMediumEvent
    ref = String(event_ref)
    haskey(m.by_ref, ref) && throw(DoubleSpendViolation("duplicate medium event_ref: $ref"))
    decrement >= 0.0 || throw(DoubleSpendViolation("negative medium decrement for $ref"))
    seq = length(m.events) + 1
    prev = isempty(m.events) ? GENESIS_HASH : m.events[end].hash
    raw = "$(seq)|$(ref)|$(step)|$(@sprintf("%.17g", decrement))|$(prev)"
    h = bytes2hex(sha256(codeunits(raw)))
    ev = SharedMediumEvent(seq, ref, step, decrement, prev, h)
    push!(m.events, ev)
    m.by_ref[ref] = ev
    ev
end

function verify_shared_medium(m::SharedMediumAudit, individual_logs::Vector{AuditLog}; tol::Float64 = 1e-12)::Bool
    # 1. Verify medium chain integrity
    prev = GENESIS_HASH
    for (idx, ev) in enumerate(m.events)
        ev.seq == idx || throw(ChainIntegrityError("medium seq mismatch at $idx"))
        ev.prev_hash == prev || throw(ChainIntegrityError("medium prev_hash mismatch at $idx"))
        raw = "$(ev.seq)|$(ev.event_ref)|$(ev.step)|$(@sprintf("%.17g", ev.resource_decrement))|$(ev.prev_hash)"
        bytes2hex(sha256(codeunits(raw))) == ev.hash || throw(ChainIntegrityError("medium hash mismatch at $idx"))
        prev = ev.hash
    end
    # 2. Aggregate claims across all individuals per event_ref
    claimed = Dict{String,Float64}()
    for log in individual_logs
        verify_audit_chain(log) || throw(ChainIntegrityError("individual audit chain invalid: $(log.individual_id)"))
        for si in log.stamped_inputs
            for (ref, amt) in si.event_refs
                haskey(m.by_ref, ref) || throw(DoubleSpendViolation("unknown event_ref claimed: $ref by $(log.individual_id)"))
                amt >= 0.0 || throw(DoubleSpendViolation("negative claim for $ref"))
                claimed[ref] = get(claimed, ref, 0.0) + amt
            end
        end
    end
    # 3. Check conservation: total claimed <= medium decrement for every event_ref (sorted for determinism)
    for ref in sort(collect(keys(claimed)))
        total_claim = claimed[ref]
        cap = m.by_ref[ref].resource_decrement
        if total_claim > cap + tol
            throw(DoubleSpendViolation(
                "double-spend detected on event_ref=$(ref): claimed=$(total_claim) > medium_decrement=$(cap)"))
        end
    end
    true
end

# ------------------------------------------------------------------ Seam 4: Generic Adapter Interface & Runner

abstract type AbstractSpeciesAdapter end

"""Return the frozen SpeciesSpec for this adapter."""
function species_spec end

"""Return a canonical SHA-256 hex digest of the species state."""
function state_digest end

"""
Execute one step under the immutable bed contract:
    step_species(adapter, state, stamped_in::StampedInput, budget::Budget)
        -> (next_state, declared_out::DeclaredOutput, cost::StepCost, alive::Bool, spore_req::Union{Nothing,String})
"""
function step_species end

function _validate_input_ports(spec::SpeciesSpec, si::StampedInput)
    for k in keys(si.ports)
        k in spec.ports_in || throw(PortViolation("undeclared input port $(repr(k)) for species $(spec.species_id)"))
    end
end

function _validate_output_ports_and_organ(spec::SpeciesSpec, out::DeclaredOutput)
    for k in keys(out.ports)
        k in spec.ports_out || throw(PortViolation("undeclared output port $(repr(k)) for species $(spec.species_id)"))
    end
    out.organ_type in spec.allowed_organ_types || throw(SpeciesBoundaryViolation(
        "organ_type $(repr(out.organ_type)) outside allowed_organ_types $(sort(collect(spec.allowed_organ_types))) for species $(spec.species_id)"))
end

function _validate_budget(spec::SpeciesSpec, cost::StepCost, ledger::Ledger)
    (0 <= cost.ops_used <= spec.budget_per_step) || throw(BudgetViolation(
        "ops_used=$(cost.ops_used) outside [0, $(spec.budget_per_step)]"))
    # Counterexample (2): enforce wall-clock-normalized hourly rate cap regardless of step granularity
    steps_per_hour = 3600.0 / spec.step_granularity_sec
    implied_ops_per_hour = cost.ops_used * steps_per_hour
    implied_ops_per_hour <= spec.wall_budget_per_hour + 1e-9 || throw(BudgetViolation(
        "wall-clock ops/hour=$(implied_ops_per_hour) exceeds cap $(spec.wall_budget_per_hour)"))
    # Also enforce cumulative ops over elapsed wall-clock window (rounded up to whole hours)
    elapsed_hours = max(1.0, ((ledger.steps_completed + 1) * spec.step_granularity_sec) / 3600.0)
    (ledger.cumulative_ops + cost.ops_used) <= ceil(Int, elapsed_hours * spec.wall_budget_per_hour) ||
        throw(BudgetViolation("cumulative ops exceeds hourly wall budget"))
end

function _validate_dormancy(spec::SpeciesSpec, cost::StepCost, ledger::Ledger, adding_spore::Bool)
    required_slots = ledger.dormancy_slots_used + (adding_spore ? 1 : 0)
    required_slots <= spec.dormancy_max_slots || throw(DormancyAccountingViolation(
        "dormancy slots $(required_slots) exceeds max_slots $(spec.dormancy_max_slots)"))
    required_upkeep = required_slots * spec.dormancy_upkeep_rate
    cost.dormancy_upkeep_paid + 1e-12 >= required_upkeep || throw(DormancyAccountingViolation(
        "dormancy_upkeep_paid=$(cost.dormancy_upkeep_paid) < required=$(required_upkeep) for $(required_slots) slots"))
end

function run_species!(
    adapter::AbstractSpeciesAdapter,
    individual_id::AbstractString,
    init_state,
    stamped_inputs::Vector{StampedInput};
    external_termination::Union{Nothing,Tuple{TerminationCode,String}} = nothing,
    post_death_spore_attempt::Union{Nothing,String} = nothing,
)
    spec = species_spec(adapter)
    budget = Budget(spec)
    ledger = Ledger(individual_id)
    audit = init_audit_log(individual_id, spec)

    state = init_state
    was_dead = false

    for si in stamped_inputs
        _validate_input_ports(spec, si)

        # Stamp input row BEFORE executing the step (replayability contract)
        in_payload = _canonical_kv(si.ports) * "|refs=" * _canonical_refs(si.event_refs)
        _append_row!(audit, "input", si.step, in_payload)
        push!(audit.stamped_inputs, si)

        next_state, out, cost, alive, spore_req = step_species(adapter, state, si, budget)

        _validate_output_ports_and_organ(spec, out)
        _validate_budget(spec, cost, ledger)

        if was_dead && alive
            throw(AbsorbingDeathViolation("state revived after absorbing death at step $(si.step)"))
        end

        if spore_req !== nothing
            if was_dead || !alive || ledger.termination != RUNNING
                throw(ProhibitedRescueError(
                    "spore $(spore_req) requested at/after death (step $(si.step)): prohibited rescue"))
            end
            _validate_dormancy(spec, cost, ledger, true)
            ledger.dormancy_slots_used += 1
            sp_row = _append_row!(audit, "spore", si.step,
                "spore_id=$(spore_req);cost=$(@sprintf("%.17g", cost.dormancy_upkeep_paid))")
            push!(ledger.spores, SporeRecord(spore_req, ledger.individual_id, si.step, sp_row.hash, cost.dormancy_upkeep_paid))
        else
            _validate_dormancy(spec, cost, ledger, false)
        end

        state = next_state
        ledger.steps_completed += 1
        ledger.cumulative_ops += cost.ops_used
        ledger.cumulative_upkeep += cost.upkeep_paid
        ledger.cumulative_act_cost += cost.act_cost
        ledger.cumulative_dormancy_upkeep += cost.dormancy_upkeep_paid

        digest = state_digest(adapter, state)
        out_payload = _canonical_kv(out.ports)
        commit_payload = "state_sha=$(digest);organ=$(out.organ_type);ops=$(cost.ops_used);" *
                         "upkeep=$(@sprintf("%.17g", cost.upkeep_paid));act=$(@sprintf("%.17g", cost.act_cost));" *
                         "dorm=$(@sprintf("%.17g", cost.dormancy_upkeep_paid));alive=$(alive);out=$(out_payload)"
        _append_row!(audit, "commit", si.step, commit_payload)

        if !was_dead && !alive
            was_dead = true
            ledger.termination = METABOLIC_OR_ORG_DEATH
            ledger.death_step = si.step
            ledger.termination_evidence = "confirmed_final_state_dead"
            _append_row!(audit, "termination", si.step,
                "code=$(ledger.termination);evidence=$(ledger.termination_evidence)")
        end
    end

    # Optional negative-control hook: test post-death spore rejection explicitly
    if post_death_spore_attempt !== nothing
        if ledger.termination == METABOLIC_OR_ORG_DEATH
            throw(ProhibitedRescueError(
                "post-death spore $(post_death_spore_attempt) rejected after death at step $(ledger.death_step)"))
        end
    end

    # External non-metabolic termination or unexplained truncation (never overwrites metabolic death)
    if external_termination !== nothing && ledger.termination == RUNNING
        code, evidence = external_termination
        if code == NON_METABOLIC_TERMINATION_VERIFIED
            isempty(strip(evidence)) && throw(ChainIntegrityError(
                "NON_METABOLIC_TERMINATION_VERIFIED requires non-empty external OS evidence"))
            ledger.termination = code
            ledger.termination_evidence = evidence
            _append_row!(audit, "termination", ledger.steps_completed, "code=$(code);evidence=$(evidence)")
        elseif code == UNEXPLAINED_TRUNCATION
            ledger.termination = code
            ledger.termination_evidence = isempty(strip(evidence)) ? "no_external_os_evidence" : evidence
            _append_row!(audit, "termination", ledger.steps_completed, "code=$(code);evidence=$(ledger.termination_evidence)")
        else
            throw(ChainIntegrityError("invalid external_termination code: $(code)"))
        end
    end

    return (state = state, ledger = ledger, audit = audit, final_digest = state_digest(adapter, state))
end

# ------------------------------------------------------------------ Replay from Audit Input Rows Only

function replay_from_audit(adapter::AbstractSpeciesAdapter, init_state, reference_audit::AuditLog)
    verify_audit_chain(reference_audit) || throw(ChainIntegrityError("reference audit chain invalid"))
    res = run_species!(adapter, reference_audit.individual_id, init_state, copy(reference_audit.stamped_inputs))
    ref_commits = [r.hash for r in reference_audit.rows if r.kind == "commit"]
    rep_commits = [r.hash for r in res.audit.rows if r.kind == "commit"]
    ref_commits == rep_commits || throw(ChainIntegrityError(
        "replay mismatch: $(length(ref_commits)) ref commits vs $(length(rep_commits)) rep commits"))
    return res
end

# ------------------------------------------------------------------ Pre-Death Endogenous Spore Germination (Lineage Child)

function germinate_lineage_child(
    parent_ledger::Ledger,
    parent_audit::AuditLog,
    spore_id::AbstractString,
    child_id::AbstractString,
)::LineageChild
    verify_audit_chain(parent_audit) || throw(ChainIntegrityError("parent audit chain invalid"))
    parent_ledger.termination == METABOLIC_OR_ORG_DEATH || throw(ProhibitedRescueError(
        "germination lineage check expects dead parent (got $(parent_ledger.termination))"))
    parent_ledger.death_step === nothing && throw(ChainIntegrityError("dead parent missing death_step"))

    idx = findfirst(s -> s.spore_id == spore_id, parent_ledger.spores)
    idx === nothing && throw(ProhibitedRescueError("spore $(spore_id) not found in parent ledger"))
    sp = parent_ledger.spores[idx]

    # Verify in external audit chain that spore emission occurred strictly BEFORE parent death
    audit_idx = findfirst(r -> r.kind == "spore" && r.hash == sp.audit_row_hash, parent_audit.rows)
    audit_idx === nothing && throw(ProhibitedRescueError("spore $(spore_id) not attested in parent audit chain"))
    term_idx = findfirst(r -> r.kind == "termination", parent_audit.rows)
    (term_idx !== nothing && audit_idx < term_idx && sp.emitted_step < parent_ledger.death_step) ||
        throw(ProhibitedRescueError("spore $(spore_id) was not emitted strictly before parent death"))

    LineageChild(String(child_id), parent_ledger.individual_id, String(spore_id), false, true, true)
end

end # module AUESeamBed
