# S91a bed_mem (discussion/specs/S91a-draft-aue-memory.md r3 §3): the canonical 4-seam common bed (experiments/aue_seam/bed.jl r2,
# copied; that file is not changed) plus a [memory] schema and an independent two-phase snapshot audit of memory settlement.
# Every export, type, error type and signature of bed.jl r2 is kept, so an unmodified adapter written for bed.jl runs here
# through the old single-phase path (no [memory] table: C_spec = 0, 4-field StepCost). The module keeps the name AUESeamBed
# (spec §1 names it AUESeamBedMem): an unmodified bed.jl adapter defines methods on `AUESeamBed.<hook>`, which an alias binding
# does not provide, so the old name is the only way to include such an adapter unchanged. Do not load bed.jl in the same session.
#
# Two-phase path (species declaring [memory]): Phase 1 step_species_pre_settle (no memory write), bed-owned copies of the
# pre-settlement snapshot, Phase 2 settle_species_memory! on a deep copy, bed-owned post snapshot, exact BigFloat (2400-bit)
# conservation checks, commit row with mem_kept / mem_paid / mem_port_delta / mem_ops. Replay re-runs every check from text rows.
# BigFloat precision: in Julia 1.11 the do-block form of the precision setter changes the process-global default (it is not
# task-local; measured in GB-M2), so a do-block exit on one thread lowers the precision of a computation on another. This file
# sets the global default to BIGPREC once, at load (single-threaded), never changes it again, builds every value with an explicit
# precision and checks the precision of every intermediate result (MemoryAccountingViolation otherwise).
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
       parse_input_row, parse_termination_row,
       run_species!, replay_from_audit, germinate_lineage_child,
       attempt_post_death_spore!,
       MemoryAccountingViolation, RunInvalidError, SettleCost,
       parse_species_spec, load_species_spec_text,
       uses_two_phase_memory, step_species_pre_settle, settle_species_memory!, is_run_invalid_exception,
       is_alive, body_cell_ids, body_balances, port_balance, total_matter, memory_bytes, digest_excl_settle,
       memory_rounding_bound, verify_memory_settlement, check_memory_layout, mem_mandatory_ops,
       port_outflow, verify_port_outflow, BIGPREC, bigprec_ok

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
struct MemoryAccountingViolation <: SeamError
    msg::String
end
# A run stopped by a resource-range exception of the species' settlement (not an organism death). mid_intact: the state
# before Phase 2 (never passed to the adapter) is bit-identical to its pre-Phase-2 snapshot. ledger / audit: the run so far.
struct RunInvalidError <: SeamError
    msg::String
    step::Int
    mid_intact::Bool
    ledger::Any
    audit::Any
end

Base.showerror(io::IO, e::SeamError) = print(io, typeof(e), ": ", e.msg)
Base.showerror(io::IO, e::RunInvalidError) = print(io, "RunInvalidError: step ", e.step, " (mid_intact=", e.mid_intact, "): ", e.msg)

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
    # [memory] (S91a r3 §2-§3; defaults when the table is absent: B = 8, C_spec = 0, single-phase path)
    has_memory::Bool
    memory_reserved_bytes::Int
    memory_header_bytes::Int
    memory_slot_bytes::Int
    memory_c_spec::Int
    memory_upkeep_rate::Float64
    memory_max_body_cells::Int
    memory_max_read_ops::Int
end

# Operation bounds of the [memory] contract (r7 §1.1.4), restated here so the bed depends on no species code.
const _OPS_KEY = 16
_ops_read_worst(C::Integer) = C == 0 ? 0 : 8 * C + 8
_ops_settle_worst(C::Integer, N::Integer) = C == 0 ? 0 : 4 * N + 45 + C * (66 * N + 31)
mem_mandatory_ops(C::Integer, N::Integer) = C == 0 ? 0 : _OPS_KEY + _ops_read_worst(C) + _ops_settle_worst(C, N)
const MEM_HEADER_BYTES = 8
const MEM_SLOT_BYTES = 16
const MEM_MIN_FREE_OPS = 64          # B_max - mandatory memory ops must leave at least this (spec §3 load-time check)

function _parse_memory_table(m, b_step::Int)
    B = Int(m["reserved_bytes"]); H = Int(m["header_bytes"]); S = Int(m["slot_bytes"])
    H == MEM_HEADER_BYTES || throw(MemoryAccountingViolation("[memory] header_bytes must be $(MEM_HEADER_BYTES) (got $H)"))
    S == MEM_SLOT_BYTES || throw(MemoryAccountingViolation("[memory] slot_bytes must be $(MEM_SLOT_BYTES) (got $S)"))
    B >= H || throw(MemoryAccountingViolation("[memory] reserved_bytes < header_bytes ($B < $H)"))
    C = fld(B - H, S)
    C <= typemax(UInt32) || throw(MemoryAccountingViolation("[memory] C_spec > typemax(UInt32) ($C)"))
    K = Float64(m["upkeep_rate_per_slot"])
    (isfinite(K) && ldexp(1.0, -40) <= K <= ldexp(1.0, 40)) ||
        throw(MemoryAccountingViolation("[memory] upkeep_rate_per_slot outside [2^-40, 2^40] ($K)"))
    N = Int(m["max_body_cells"])
    1 <= N <= 65536 || throw(MemoryAccountingViolation("[memory] max_body_cells outside [1, 65536] ($N)"))
    R = Int(m["max_read_ops_per_step"])
    R >= _ops_read_worst(C) || throw(MemoryAccountingViolation(
        "[memory] max_read_ops_per_step < worst read ops ($R < $(_ops_read_worst(C)))"))
    b_step - mem_mandatory_ops(C, N) >= MEM_MIN_FREE_OPS || throw(BudgetViolation(
        "ops_per_step - mandatory memory ops < $(MEM_MIN_FREE_OPS) ($(b_step) - $(mem_mandatory_ops(C, N)))"))
    return (true, B, H, S, C, K, N, R)
end

function parse_species_spec(raw::Vector{UInt8})::SpeciesSpec
    spec_sha = bytes2hex(sha256(raw))
    d = TOML.parse(String(copy(raw)))

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

    mem = haskey(d, "memory") ? _parse_memory_table(d["memory"], b_step) :
          (false, MEM_HEADER_BYTES, MEM_HEADER_BYTES, MEM_SLOT_BYTES, 0, 0.002, 1, 0)

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
        mem...,
    )
end
load_species_spec(toml_path::AbstractString)::SpeciesSpec = parse_species_spec(read(toml_path))
load_species_spec_text(text::AbstractString)::SpeciesSpec = parse_species_spec(Vector{UInt8}(codeunits(String(text))))

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

# Phase 2 report of a two-phase species (spec §3 step 4-5). slot_paid_lo: the prepaid amount of each kept slot, in settlement
# order. info: species-side diagnostics, passed through to on_settle only (never read by the checks, never hashed).
struct SettleCost
    memory_slots_kept::Int
    slot_paid_lo::Vector{Float64}
    memory_upkeep_paid::Float64
    memory_port_delta::Float64
    memory_settle_ops::Int
    memory_write_ops::Int
    info::Dict{String,Any}
end
SettleCost(kept::Int, paid_lo::Vector{Float64}, paid::Float64, port_delta::Float64, settle_ops::Int, write_ops::Int) =
    SettleCost(kept, paid_lo, paid, port_delta, settle_ops, write_ops, Dict{String,Any}())

# ------------------------------------------------------------------ Seam 3: Ledger & 3-Way Termination

@enum TerminationCode begin
    RUNNING = 0
    METABOLIC_OR_ORG_DEATH = 1
    NON_METABOLIC_TERMINATION_VERIFIED = 2
    UNEXPLAINED_TRUNCATION = 3
end

function _parse_termination_code(s::AbstractString)::TerminationCode
    s == "RUNNING" && return RUNNING
    s == "METABOLIC_OR_ORG_DEATH" && return METABOLIC_OR_ORG_DEATH
    s == "NON_METABOLIC_TERMINATION_VERIFIED" && return NON_METABOLIC_TERMINATION_VERIFIED
    s == "UNEXPLAINED_TRUNCATION" && return UNEXPLAINED_TRUNCATION
    throw(ChainIntegrityError("unknown TerminationCode: $(repr(s))"))
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
    window_ops_history::Vector{Tuple{Float64,Int}}   # (elapsed_wall_sec, ops_used) for rolling 3600s window
    cumulative_upkeep::Float64
    cumulative_act_cost::Float64
    dormancy_slots_used::Int
    cumulative_dormancy_upkeep::Float64
    spores::Vector{SporeRecord}
    cumulative_memory_upkeep::Float64     # sum of bed-verified mem_paid (two-phase path only)
    cumulative_memory_ops::Int
end
Ledger(individual_id::AbstractString) =
    Ledger(String(individual_id), RUNNING, "", nothing, 0, 0, Tuple{Float64,Int}[], 0.0, 0.0, 0, 0.0, SporeRecord[], 0.0, 0)

# ------------------------------------------------------------------ Hash-Chained Audit Log (Text Single Source of Truth)

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
end

const GENESIS_HASH = "0"^64

# Canonical typed serialization so audit input rows can be parsed back losslessly with exact types.
function _encode_val(v)::String
    if v isa Bool
        return "b:" * (v ? "true" : "false")
    elseif v isa UInt64
        return "u64:" * string(v)
    elseif v isa Int
        return "i64:" * string(v)
    elseif v isa Float64
        return "f64:" * @sprintf("%.17g", v)
    else
        return "s:" * string(v)
    end
end

function _decode_val(s::AbstractString)
    startswith(s, "b:") && return (s[3:end] == "true")
    startswith(s, "u64:") && return parse(UInt64, s[5:end])
    startswith(s, "i64:") && return parse(Int, s[5:end])
    startswith(s, "f64:") && return parse(Float64, s[5:end])
    startswith(s, "s:") && return String(s[3:end])
    throw(ChainIntegrityError("malformed typed audit value: $(repr(s))"))
end

function _canonical_kv_typed(d::Dict{String,Any})::String
    ks = sort(collect(keys(d)))
    join(["$(k)=$(_encode_val(d[k]))" for k in ks], ";")
end

function _canonical_kv_plain(d::Dict{String,Any})::String
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

function parse_input_row(row::AuditRow)::StampedInput
    row.kind == "input" || throw(ChainIntegrityError("expected input row, got $(row.kind)"))
    parts = split(row.payload, "|refs=")
    length(parts) == 2 || throw(ChainIntegrityError("malformed input row payload: $(row.payload)"))
    kv_str, refs_str = parts[1], parts[2]
    ports = Dict{String,Any}()
    if !isempty(kv_str)
        for item in split(kv_str, ";")
            eq = findfirst('=', item)
            eq === nothing && throw(ChainIntegrityError("malformed kv item: $(item)"))
            k = String(item[1:prevind(item, eq)])
            v = _decode_val(item[nextind(item, eq):end])
            ports[k] = v
        end
    end
    refs = Tuple{String,Float64}[]
    if !isempty(refs_str)
        for item in split(refs_str, ",")
            col = findlast(':', item)
            col === nothing && throw(ChainIntegrityError("malformed event_ref item: $(item)"))
            ref = String(item[1:prevind(item, col)])
            amt = parse(Float64, item[nextind(item, col):end])
            push!(refs, (ref, amt))
        end
    end
    StampedInput(row.step, ports, refs)
end

function parse_termination_row(row::AuditRow)::Tuple{TerminationCode,String}
    row.kind == "termination" || throw(ChainIntegrityError("expected termination row, got $(row.kind)"))
    startswith(row.payload, "code=") || throw(ChainIntegrityError("malformed termination payload: $(row.payload)"))
    ev_pos = findfirst(";evidence=", row.payload)
    ev_pos === nothing && throw(ChainIntegrityError("missing evidence in termination payload: $(row.payload)"))
    code_str = row.payload[6:prevind(row.payload, first(ev_pos))]
    ev_str = row.payload[nextind(row.payload, last(ev_pos)):end]
    (_parse_termination_code(code_str), String(ev_str))
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
                   spec.mapping_spec_hash, spec.phenomenal_claim, AuditRow[])
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
    # 2. Aggregate claims by PARSING directly from the hash-chained `input` rows (no side array!)
    claimed = Dict{String,Float64}()
    for log in individual_logs
        verify_audit_chain(log) || throw(ChainIntegrityError("individual audit chain invalid: $(log.individual_id)"))
        for row in log.rows
            row.kind == "input" || continue
            si = parse_input_row(row)
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

"""Return a canonical little-endian SHA-256 hex digest of the species state."""
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

function _validate_budget!(spec::SpeciesSpec, cost::StepCost, ledger::Ledger)
    (0 <= cost.ops_used <= spec.budget_per_step) || throw(BudgetViolation(
        "ops_used=$(cost.ops_used) outside [0, $(spec.budget_per_step)]"))
    # Counterexample (2a): instantaneous wall-clock rate check (catches fine-step granularity hiding)
    steps_per_hour = 3600.0 / spec.step_granularity_sec
    implied_ops_per_hour = cost.ops_used * steps_per_hour
    implied_ops_per_hour <= spec.wall_budget_per_hour + 1e-9 || throw(BudgetViolation(
        "wall-clock ops/hour=$(implied_ops_per_hour) exceeds cap $(spec.wall_budget_per_hour)"))
    # Counterexample (2b): rolling 3600s sliding window cap
    now_sec = (ledger.steps_completed + 1) * spec.step_granularity_sec
    win_start = now_sec - 3600.0
    filter!(e -> e[1] > win_start + 1e-12, ledger.window_ops_history)
    win_sum = sum((e[2] for e in ledger.window_ops_history); init = 0) + cost.ops_used
    win_sum <= spec.wall_budget_per_hour || throw(BudgetViolation(
        "rolling 3600s window ops=$(win_sum) exceeds cap $(spec.wall_budget_per_hour) at t=$(now_sec)s"))
    push!(ledger.window_ops_history, (now_sec, cost.ops_used))
end

function _validate_dormancy(spec::SpeciesSpec, cost::StepCost, ledger::Ledger, adding_spore::Bool)
    required_slots = ledger.dormancy_slots_used + (adding_spore ? 1 : 0)
    required_slots <= spec.dormancy_max_slots || throw(DormancyAccountingViolation(
        "dormancy slots $(required_slots) exceeds max_slots $(spec.dormancy_max_slots)"))
    required_upkeep = required_slots * spec.dormancy_upkeep_rate
    cost.dormancy_upkeep_paid + 1e-12 >= required_upkeep || throw(DormancyAccountingViolation(
        "dormancy_upkeep_paid=$(cost.dormancy_upkeep_paid) < required=$(required_upkeep) for $(required_slots) slots"))
end

# ------------------------------------------------------------------ Two-Phase Memory Hooks (spec §3; defaults are species-free)

"""True for an adapter whose species declares [memory] and runs the two-phase settlement protocol."""
uses_two_phase_memory(::AbstractSpeciesAdapter) = false

"""
Phase 1 (pre-settlement update; the memory bytes must not change):
    step_species_pre_settle(adapter, state, si, budget) -> (mid_state, declared_out, phase1_cost::StepCost, spore_req)
`mid_state` is a new state independent of `state`.
"""
function step_species_pre_settle end

"""
Phase 2 (settlement only; writes the body balances, the port and the memory, nothing else):
    settle_species_memory!(adapter, mid_copy, alive_post::Bool, budget) -> (next_state, settle_cost::SettleCost)
"""
function settle_species_memory! end

"""True when an exception thrown by Phase 2 is a resource-range rejection that makes the run invalid (default: none)."""
is_run_invalid_exception(::AbstractSpeciesAdapter, e) = false

function is_alive end
function body_cell_ids end
function body_balances end
function port_balance end
"""The port's cumulative outflow ledger (default 0.0: an adapter without one may not move the port in settlement)."""
port_outflow(::AbstractSpeciesAdapter, state) = 0.0
function total_matter end
function memory_bytes end
function digest_excl_settle end

_le_u32(buf::Vector{UInt8}, off::Int) = UInt32(buf[off+1]) | (UInt32(buf[off+2]) << 8) | (UInt32(buf[off+3]) << 16) | (UInt32(buf[off+4]) << 24)

# Fixed-length layout of the memory bytes: length B, header pad zero, count <= C_spec, empty slots and surplus bytes zero.
function check_memory_layout(spec::SpeciesSpec, mem::Vector{UInt8})::Int
    B = spec.memory_reserved_bytes; H = spec.memory_header_bytes; S = spec.memory_slot_bytes; C = spec.memory_c_spec
    length(mem) == B || throw(MemoryAccountingViolation("memory bytes length $(length(mem)) != reserved_bytes $B"))
    _le_u32(mem, 4) == 0 || throw(MemoryAccountingViolation("memory header pad != 0"))
    kept = Int(_le_u32(mem, 0))
    kept <= C || throw(MemoryAccountingViolation("memory count $kept > C_spec $C"))
    all(==(0x00), @view mem[H+kept*S+1:H+C*S]) || throw(MemoryAccountingViolation("memory empty slot bytes not zero"))
    all(==(0x00), @view mem[H+C*S+1:B]) || throw(MemoryAccountingViolation("memory surplus bytes not zero"))
    return kept
end

const BIGPREC = 2400
setprecision(BigFloat, BIGPREC)          # the one global setting (load time); nothing in this file changes it afterwards

bigprec_ok() = precision(BigFloat) == BIGPREC
function _pk(x::BigFloat)
    precision(x) == BIGPREC || throw(MemoryAccountingViolation("BigFloat precision $(precision(x)) != $(BIGPREC) (precision downgraded)"))
    return x
end
function _bf(x)
    bigprec_ok() || throw(MemoryAccountingViolation("default BigFloat precision $(precision(BigFloat)) != $(BIGPREC) (precision downgraded)"))
    return _pk(BigFloat(x; precision = BIGPREC))
end
_add(a::BigFloat, b::BigFloat) = _pk(a + b)
_sub(a::BigFloat, b::BigFloat) = _pk(a - b)
_mul(a::BigFloat, b::BigFloat) = _pk(a * b)
function _bsum(xs)
    s = _bf(0)
    for x in xs; s = _add(s, x); end
    return s
end

# Separated rounding-loss bound (spec §3 step 5-4): kept * ((3N + 4) * eps(max(2K, 2 eps(max(1, B_max)))) + eps(max(port_post, K))).
function memory_rounding_bound(kept::Integer, N::Integer, K_mem::Float64, B_max::Float64, port_post::Float64)::BigFloat
    _mul(_bf(kept), _add(_mul(_bf(3 * N + 4), _bf(eps(max(2.0 * K_mem, 2.0 * eps(max(1.0, B_max)))))),
                         _bf(eps(max(port_post, K_mem)))))
end

"""
Bed-side check of one settlement from bed-owned snapshots (spec §3 step 5). Returns
(verified_paid::Float64, kept::Int, bound::BigFloat, loss::BigFloat) or throws MemoryAccountingViolation.
"""
function verify_memory_settlement(spec::SpeciesSpec, alive_post::Bool, sc::SettleCost,
                                  B_pre::Vector{Float64}, B_post::Vector{Float64}, port_pre::Float64, port_post::Float64,
                                  total_pre::Float64, total_post::Float64, mem_pre::Vector{UInt8}, mem_post::Vector{UInt8})
    V(msg) = throw(MemoryAccountingViolation(msg))
    kept = check_memory_layout(spec, mem_post)
    kept == sc.memory_slots_kept || V("memory count $kept != reported memory_slots_kept $(sc.memory_slots_kept)")
    length(B_post) == length(B_pre) || V("body balance length changed in Phase 2")
    if spec.memory_c_spec == 0 || !alive_post
        what = spec.memory_c_spec == 0 ? "C_spec == 0" : "dead step"
        isempty(sc.slot_paid_lo) || V("$what: slot_paid_lo not empty")
        sc.memory_upkeep_paid === 0.0 || V("$what: memory_upkeep_paid !== 0.0")
        sc.memory_port_delta === 0.0 || V("$what: memory_port_delta !== 0.0")
        sc.memory_settle_ops == 0 || V("$what: memory_settle_ops != 0")
        sc.memory_write_ops == 0 || V("$what: memory_write_ops != 0")
        isequal(B_post, B_pre) || V("$what: body balances changed")
        port_post === port_pre || V("$what: port balance changed")
        mem_post == mem_pre || V("$what: memory bytes changed")
        return (0.0, kept, _bf(0), _bf(0))
    end
    K = spec.memory_upkeep_rate
    length(sc.slot_paid_lo) == kept || V("slot_paid_lo length $(length(sc.slot_paid_lo)) != kept $kept (unpaid holding)")
    for p in sc.slot_paid_lo
        (isfinite(p) && p >= K) || V("slot paid_lo $p < K_mem $K")
    end
    (sc.memory_settle_ops >= 0 && sc.memory_write_ops >= 0) || V("negative memory ops")
    for i in eachindex(B_pre)
        (isfinite(B_post[i]) && 0.0 <= B_post[i] <= B_pre[i]) || V("body cell $i balance rose or left range ($(B_pre[i]) -> $(B_post[i]))")
    end
    exact_E = _bsum(_sub(_bf(B_pre[i]), _bf(B_post[i])) for i in eachindex(B_pre))
    port_delta = _sub(_bf(port_post), _bf(port_pre))
    sum_paid_lo = _bsum(_bf(p) for p in sc.slot_paid_lo)
    req_exact = _mul(_bf(kept), _bf(K))
    verified_paid = Float64(sum_paid_lo)
    sum_paid_lo >= req_exact || V("paid $(sum_paid_lo) < kept * K_mem $(req_exact)")
    sc.memory_upkeep_paid === verified_paid || V("memory_upkeep_paid $(sc.memory_upkeep_paid) !== verified $(verified_paid)")
    _bf(sc.memory_port_delta) == port_delta || V("reported port delta $(sc.memory_port_delta) != measured $(Float64(port_delta))")
    _bf(0) <= port_delta || V("port balance fell in settlement")
    port_delta <= sum_paid_lo || V("port gain $(Float64(port_delta)) > paid $(verified_paid) (matter created)")
    sum_paid_lo <= exact_E || V("paid $(verified_paid) > body decrease $(Float64(exact_E)) (fictitious payment)")
    _bf(total_post) <= _bf(total_pre) || V("total matter rose in settlement")
    bound = memory_rounding_bound(kept, length(B_pre), K, isempty(B_pre) ? 0.0 : maximum(B_pre), port_post)
    loss = _sub(exact_E, port_delta)
    loss <= bound || V("matter loss $(Float64(loss)) > rounding bound $(Float64(bound))")
    return (verified_paid, kept, bound, loss)
end

"""
Bed-side check of the port's outflow ledger over Phase 2 (bed-owned Float64 snapshots). A frozen step (dead step or C_spec == 0)
leaves it bit-identical; a settling step adds exactly the reported port delta, in one Float64 addition.
"""
function verify_port_outflow(spec::SpeciesSpec, alive_post::Bool, sc::SettleCost, outflow_pre::Float64, outflow_post::Float64)
    if spec.memory_c_spec == 0 || !alive_post
        what = spec.memory_c_spec == 0 ? "C_spec == 0" : "dead step"
        outflow_post === outflow_pre || throw(MemoryAccountingViolation(
            "$what: port outflow changed ($(@sprintf("%.17g", outflow_pre)) -> $(@sprintf("%.17g", outflow_post)))"))
    else
        want = outflow_pre + sc.memory_port_delta
        outflow_post === want || throw(MemoryAccountingViolation(
            "port outflow $(@sprintf("%.17g", outflow_post)) !== outflow_pre + memory_port_delta $(@sprintf("%.17g", want))"))
    end
    return true
end

function _validate_step_common!(spec, cost, out, ledger, audit, si, alive, spore_req)
    _validate_output_ports_and_organ(spec, out)
    _validate_budget!(spec, cost, ledger)
    if spore_req !== nothing
        if !alive || ledger.termination != RUNNING
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
end

function _commit_payload(digest, out, cost, alive)
    "state_sha=$(digest);organ=$(out.organ_type);ops=$(cost.ops_used);" *
    "upkeep=$(@sprintf("%.17g", cost.upkeep_paid));act=$(@sprintf("%.17g", cost.act_cost));" *
    "dorm=$(@sprintf("%.17g", cost.dormancy_upkeep_paid));alive=$(alive);out=$(_canonical_kv_plain(out.ports))"
end

# One two-phase step (spec §3 steps 1-5). Returns (next_state, out, cost, alive_post, spore_req, sc, verified_paid, bound, loss).
function _two_phase_step(adapter, spec, state, si, budget, ledger, audit)
    mem_init = copy(memory_bytes(adapter, state))
    mid_state, out, c1, spore_req = step_species_pre_settle(adapter, state, si, budget)
    mid_state === state && throw(MemoryAccountingViolation("Phase 1 returned the input state object (must be a new state)"))
    mem_pre = copy(memory_bytes(adapter, mid_state))
    mem_pre == mem_init || throw(MemoryAccountingViolation("Phase 1 wrote the memory bytes (early write) at step $(si.step)"))
    alive_post = is_alive(adapter, mid_state)::Bool
    ids_pre = copy(body_cell_ids(adapter, mid_state))
    alive_post == !isempty(ids_pre) || throw(MemoryAccountingViolation(
        "alive judgement $(alive_post) disagrees with body cells ($(length(ids_pre))) at step $(si.step)"))
    B_pre = copy(body_balances(adapter, mid_state))
    length(B_pre) == length(ids_pre) || throw(MemoryAccountingViolation("body balances length != body cells length"))
    port_pre = Float64(port_balance(adapter, mid_state))
    outflow_pre = Float64(port_outflow(adapter, mid_state))
    total_pre = Float64(total_matter(adapter, mid_state))
    excl_pre = String(digest_excl_settle(adapter, mid_state))
    mid_ref = deepcopy(mid_state)      # bed-owned reference of the state before Phase 2 (run-invalid intactness check)
    mid_copy = deepcopy(mid_state)
    next_state, sc = try
        settle_species_memory!(adapter, mid_copy, alive_post, budget)
    catch e
        e isa SeamError && rethrow()
        if is_run_invalid_exception(adapter, e)
            intact = state_digest(adapter, mid_state) == state_digest(adapter, mid_ref) && memory_bytes(adapter, mid_state) == mem_pre &&
                     digest_excl_settle(adapter, mid_state) == excl_pre && isequal(body_balances(adapter, mid_state), B_pre) &&
                     port_balance(adapter, mid_state) === port_pre && Float64(port_outflow(adapter, mid_state)) === outflow_pre
            throw(RunInvalidError(sprint(showerror, e), si.step, intact, ledger, audit))
        end
        rethrow()
    end
    ids_post = copy(body_cell_ids(adapter, next_state))
    B_post = copy(body_balances(adapter, next_state))
    port_post = Float64(port_balance(adapter, next_state))
    outflow_post = Float64(port_outflow(adapter, next_state))
    total_post = Float64(total_matter(adapter, next_state))
    mem_post = copy(memory_bytes(adapter, next_state))
    excl_post = String(digest_excl_settle(adapter, next_state))
    excl_post == excl_pre || throw(MemoryAccountingViolation("Phase 2 wrote outside {body balances, port, memory} at step $(si.step)"))
    ids_post == ids_pre || throw(MemoryAccountingViolation("Phase 2 changed the body cells at step $(si.step)"))
    is_alive(adapter, next_state) == alive_post || throw(MemoryAccountingViolation("Phase 2 changed the alive judgement"))
    verified_paid, kept, bound, loss = verify_memory_settlement(spec, alive_post, sc, B_pre, B_post, port_pre, port_post,
                                                                total_pre, total_post, mem_pre, mem_post)
    verify_port_outflow(spec, alive_post, sc, outflow_pre, outflow_post)
    cost = StepCost(c1.ops_used + sc.memory_settle_ops + sc.memory_write_ops, c1.upkeep_paid, c1.act_cost, c1.dormancy_upkeep_paid)
    return (next_state, out, cost, alive_post, spore_req, sc, verified_paid, bound, loss, outflow_pre, outflow_post)
end

function run_species!(
    adapter::AbstractSpeciesAdapter,
    individual_id::AbstractString,
    init_state,
    stamped_inputs::Vector{StampedInput};
    external_termination::Union{Nothing,Tuple{TerminationCode,String}} = nothing,
    on_step::Union{Nothing,Function} = nothing,
    on_settle::Union{Nothing,Function} = nothing,
)
    spec = species_spec(adapter)
    budget = Budget(spec)
    ledger = Ledger(individual_id)
    audit = init_audit_log(individual_id, spec)
    two_phase = uses_two_phase_memory(adapter)
    two_phase == spec.has_memory || throw(MemoryAccountingViolation(
        "two-phase adapter ($(two_phase)) and [memory] declaration ($(spec.has_memory)) disagree"))

    state = init_state

    for si in stamped_inputs
        # Absorbing death invariant: once metabolically dead, execute 0 further steps and write 0 further commits
        if ledger.termination == METABOLIC_OR_ORG_DEATH
            break
        end

        _validate_input_ports(spec, si)

        # Stamp canonical typed input row BEFORE executing the step (text single source of truth)
        in_payload = _canonical_kv_typed(si.ports) * "|refs=" * _canonical_refs(si.event_refs)
        _append_row!(audit, "input", si.step, in_payload)

        if two_phase
            next_state, out, cost, alive, spore_req, sc, vpaid, bound, loss, of_pre, of_post =
                _two_phase_step(adapter, spec, state, si, budget, ledger, audit)
        else
            next_state, out, cost, alive, spore_req = step_species(adapter, state, si, budget)
        end

        _validate_step_common!(spec, cost, out, ledger, audit, si, alive, spore_req)

        state = next_state
        ledger.steps_completed += 1
        ledger.cumulative_ops += cost.ops_used
        ledger.cumulative_upkeep += cost.upkeep_paid
        ledger.cumulative_act_cost += cost.act_cost
        ledger.cumulative_dormancy_upkeep += cost.dormancy_upkeep_paid

        digest = state_digest(adapter, state)
        commit_payload = _commit_payload(digest, out, cost, alive)
        if two_phase
            mem_ops = sc.memory_settle_ops + sc.memory_write_ops
            ledger.cumulative_memory_upkeep += vpaid
            ledger.cumulative_memory_ops += mem_ops
            commit_payload *= ";mem_kept=$(sc.memory_slots_kept);mem_paid=$(@sprintf("%.17g", vpaid));" *
                              "mem_port_delta=$(@sprintf("%.17g", sc.memory_port_delta));mem_ops=$(mem_ops)"
        end
        _append_row!(audit, "commit", si.step, commit_payload)

        on_step === nothing || on_step(si.step, state, digest)
        if two_phase && on_settle !== nothing
            on_settle(si.step, (state = state, alive = alive, settle = sc, verified_paid = vpaid, bound = bound, loss = loss,
                                margin = _sub(bound, loss), ops_used = cost.ops_used, outflow_pre = of_pre, outflow_post = of_post))
        end

        if !alive
            ledger.termination = METABOLIC_OR_ORG_DEATH
            ledger.death_step = si.step
            ledger.termination_evidence = "confirmed_final_state_dead"
            _append_row!(audit, "termination", si.step,
                "code=$(ledger.termination);evidence=$(ledger.termination_evidence)")
            break
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

# ------------------------------------------------------------------ External Post-Death Spore Guard

"""
External operation attempting to register a spore on an existing ledger/audit after run end.
Strictly rejects any attempt on a non-RUNNING (dead/terminated) individual as ProhibitedRescueError.
"""
function attempt_post_death_spore!(ledger::Ledger, audit::AuditLog, spore_id::AbstractString, step::Int)
    verify_audit_chain(audit) || throw(ChainIntegrityError("audit chain invalid"))
    if ledger.termination != RUNNING
        throw(ProhibitedRescueError(
            "external post-termination spore $(spore_id) rejected (termination=$(ledger.termination), death_step=$(ledger.death_step))"))
    end
    throw(ProhibitedRescueError("external spore injection outside step_species is forbidden (spore=$(spore_id), step=$(step))"))
end

# ------------------------------------------------------------------ Replay Directly from Audit Text Rows

function replay_from_audit(adapter::AbstractSpeciesAdapter, init_state, reference_audit::AuditLog)
    verify_audit_chain(reference_audit) || throw(ChainIntegrityError("reference audit chain invalid"))

    # Parse inputs strictly from hash-chained `input` row text
    parsed_inputs = [parse_input_row(r) for r in reference_audit.rows if r.kind == "input"]

    # Parse non-metabolic / truncation termination if present in reference audit
    ext_term = nothing
    term_rows = [r for r in reference_audit.rows if r.kind == "termination"]
    if length(term_rows) > 1
        throw(ChainIntegrityError("multiple termination rows in reference audit"))
    elseif length(term_rows) == 1
        code, ev = parse_termination_row(term_rows[1])
        if code == NON_METABOLIC_TERMINATION_VERIFIED || code == UNEXPLAINED_TRUNCATION
            ext_term = (code, ev)
        end
    end

    res = run_species!(adapter, reference_audit.individual_id, init_state, parsed_inputs;
                       external_termination = ext_term)

    # Full chain equality: every single row (header, input, spore, commit, termination) & tail hash must match
    ref_hashes = [(r.seq, r.kind, r.step, r.hash) for r in reference_audit.rows]
    rep_hashes = [(r.seq, r.kind, r.step, r.hash) for r in res.audit.rows]
    ref_hashes == rep_hashes || throw(ChainIntegrityError(
        "full audit replay mismatch: $(length(ref_hashes)) ref rows vs $(length(rep_hashes)) rep rows"))

    # Two-phase path: the memory fields of the commit rows (text) re-add to the replayed ledger, row by row in order
    if uses_two_phase_memory(adapter)
        acc = 0.0; ops = 0
        for r in reference_audit.rows
            r.kind == "commit" || continue
            f = Dict{String,String}()
            for item in split(r.payload, ";")
                eq = findfirst('=', item); eq === nothing && continue
                k = String(item[1:prevind(item, eq)])
                startswith(k, "mem_") && (f[k] = String(item[nextind(item, eq):end]))
            end
            (haskey(f, "mem_kept") && haskey(f, "mem_paid") && haskey(f, "mem_port_delta") && haskey(f, "mem_ops")) ||
                throw(ChainIntegrityError("commit row $(r.seq) lacks memory fields"))
            acc += parse(Float64, f["mem_paid"]); ops += parse(Int, f["mem_ops"])
        end
        (acc === res.ledger.cumulative_memory_upkeep && ops == res.ledger.cumulative_memory_ops) ||
            throw(ChainIntegrityError("memory ledger mismatch on replay"))
    end

    if !isempty(term_rows)
        ref_code, ref_ev = parse_termination_row(term_rows[1])
        (res.ledger.termination == ref_code && res.ledger.termination_evidence == ref_ev) ||
            throw(ChainIntegrityError("termination state mismatch on replay"))
    end

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
