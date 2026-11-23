//! Seams 2-4: Species-agnostic immutable common bed (Rust mirror of `experiments/aue_seam/bed.jl` r2).
//!
//! Strict invariant: ZERO species-specific logic or branches in this module.
//! All replay and shared-medium audits parse strictly from hash-chained `AuditLog` row text.
//! phenomenal_claim = :not_certified (fixed).

use std::collections::BTreeMap;

use crate::sha256::sha256_hex;
use crate::spec::SpeciesSpec;

pub const GENESIS_HASH: &str = "0000000000000000000000000000000000000000000000000000000000000000";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SeamError {
    PortViolation(String),
    SpeciesBoundaryViolation(String),
    BudgetViolation(String),
    DormancyAccountingViolation(String),
    ProhibitedRescueError(String),
    DoubleSpendViolation(String),
    ChainIntegrityError(String),
}

impl std::fmt::Display for SeamError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum PortVal {
    Bool(bool),
    I64(i64),
    U64(u64),
    F64(f64),
    Str(String),
}

impl PortVal {
    fn encode_typed(&self) -> String {
        match self {
            PortVal::Bool(b) => format!("b:{}", if *b { "true" } else { "false" }),
            PortVal::I64(v) => format!("i64:{v}"),
            PortVal::U64(v) => format!("u64:{v}"),
            PortVal::F64(v) => format!("f64:{v:.17}"),
            PortVal::Str(s) => format!("s:{s}"),
        }
    }

    fn encode_plain(&self) -> String {
        match self {
            PortVal::Bool(b) => (if *b { "true" } else { "false" }).to_string(),
            PortVal::I64(v) => v.to_string(),
            PortVal::U64(v) => v.to_string(),
            PortVal::F64(v) => format!("{v:.17}"),
            PortVal::Str(s) => s.clone(),
        }
    }

    fn decode_typed(s: &str) -> Result<Self, SeamError> {
        if let Some(rest) = s.strip_prefix("b:") {
            return match rest {
                "true" => Ok(PortVal::Bool(true)),
                "false" => Ok(PortVal::Bool(false)),
                _ => Err(SeamError::ChainIntegrityError(format!("bad bool: {s}"))),
            };
        }
        if let Some(rest) = s.strip_prefix("u64:") {
            return rest
                .parse::<u64>()
                .map(PortVal::U64)
                .map_err(|e| SeamError::ChainIntegrityError(format!("bad u64 {s}: {e}")));
        }
        if let Some(rest) = s.strip_prefix("i64:") {
            return rest
                .parse::<i64>()
                .map(PortVal::I64)
                .map_err(|e| SeamError::ChainIntegrityError(format!("bad i64 {s}: {e}")));
        }
        if let Some(rest) = s.strip_prefix("f64:") {
            return rest
                .parse::<f64>()
                .map(PortVal::F64)
                .map_err(|e| SeamError::ChainIntegrityError(format!("bad f64 {s}: {e}")));
        }
        if let Some(rest) = s.strip_prefix("s:") {
            return Ok(PortVal::Str(rest.to_string()));
        }
        Err(SeamError::ChainIntegrityError(format!("malformed typed value: {s}")))
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct StampedInput {
    pub step: u64,
    pub ports: BTreeMap<String, PortVal>,
    pub event_refs: Vec<(String, f64)>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DeclaredOutput {
    pub ports: BTreeMap<String, PortVal>,
    pub organ_type: String,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct StepCost {
    pub ops_used: u64,
    pub upkeep_paid: f64,
    pub act_cost: f64,
    pub dormancy_upkeep_paid: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Budget {
    pub ops_per_step: u64,
    pub ops_per_hour: u64,
    pub step_granularity_sec: f64,
}

impl Budget {
    pub fn from_spec(spec: &SpeciesSpec) -> Self {
        Self {
            ops_per_step: spec.budget_per_step,
            ops_per_hour: spec.wall_budget_per_hour,
            step_granularity_sec: spec.step_granularity_sec,
        }
    }
}

/// 3-way termination separation (D-AUE-SPECIES-AND-GAPS.md O30 / PLAN-PI5-TRM-DEPLOY.md §1.2).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminationCode {
    Running,
    MetabolicOrOrgDeath,
    NonMetabolicTerminationVerified,
    UnexplainedTruncation,
}

impl TerminationCode {
    pub fn as_str(&self) -> &'static str {
        match self {
            TerminationCode::Running => "RUNNING",
            TerminationCode::MetabolicOrOrgDeath => "METABOLIC_OR_ORG_DEATH",
            TerminationCode::NonMetabolicTerminationVerified => "NON_METABOLIC_TERMINATION_VERIFIED",
            TerminationCode::UnexplainedTruncation => "UNEXPLAINED_TRUNCATION",
        }
    }

    pub fn from_str(s: &str) -> Result<Self, SeamError> {
        match s {
            "RUNNING" => Ok(TerminationCode::Running),
            "METABOLIC_OR_ORG_DEATH" => Ok(TerminationCode::MetabolicOrOrgDeath),
            "NON_METABOLIC_TERMINATION_VERIFIED" => Ok(TerminationCode::NonMetabolicTerminationVerified),
            "UNEXPLAINED_TRUNCATION" => Ok(TerminationCode::UnexplainedTruncation),
            _ => Err(SeamError::ChainIntegrityError(format!("unknown TerminationCode: {s}"))),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct SporeRecord {
    pub spore_id: String,
    pub parent_id: String,
    pub emitted_step: u64,
    pub audit_row_hash: String,
    pub dormancy_cost_paid: f64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LineageChild {
    pub child_id: String,
    pub parent_id: String,
    pub source_spore_id: String,
    pub same_individual: bool,
    pub lineage_child: bool,
    pub verified_pre_death: bool,
}

#[derive(Debug, Clone)]
pub struct Ledger {
    pub individual_id: String,
    pub termination: TerminationCode,
    pub termination_evidence: String,
    pub death_step: Option<u64>,
    pub steps_completed: u64,
    pub cumulative_ops: u64,
    pub window_ops_history: Vec<(f64, u64)>,
    pub cumulative_upkeep: f64,
    pub cumulative_act_cost: f64,
    pub dormancy_slots_used: usize,
    pub cumulative_dormancy_upkeep: f64,
    pub spores: Vec<SporeRecord>,
}

impl Ledger {
    pub fn new(individual_id: &str) -> Self {
        Self {
            individual_id: individual_id.to_string(),
            termination: TerminationCode::Running,
            termination_evidence: String::new(),
            death_step: None,
            steps_completed: 0,
            cumulative_ops: 0,
            window_ops_history: Vec::new(),
            cumulative_upkeep: 0.0,
            cumulative_act_cost: 0.0,
            dormancy_slots_used: 0,
            cumulative_dormancy_upkeep: 0.0,
            spores: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuditRow {
    pub seq: usize,
    pub kind: String,
    pub step: u64,
    pub payload: String,
    pub prev_hash: String,
    pub hash: String,
}

#[derive(Debug, Clone)]
pub struct AuditLog {
    pub individual_id: String,
    pub species_id: String,
    pub spec_sha256: String,
    pub mapping_spec_hash: String,
    pub phenomenal_claim: String,
    pub rows: Vec<AuditRow>,
}

fn canonical_kv_typed(m: &BTreeMap<String, PortVal>) -> String {
    m.iter()
        .map(|(k, v)| format!("{k}={}", v.encode_typed()))
        .collect::<Vec<_>>()
        .join(";")
}

fn canonical_kv_plain(m: &BTreeMap<String, PortVal>) -> String {
    m.iter()
        .map(|(k, v)| format!("{k}={}", v.encode_plain()))
        .collect::<Vec<_>>()
        .join(";")
}

fn canonical_refs(refs: &[(String, f64)]) -> String {
    refs.iter()
        .map(|(r, a)| format!("{r}:{a:.17}"))
        .collect::<Vec<_>>()
        .join(",")
}

impl AuditLog {
    pub fn init(individual_id: &str, spec: &SpeciesSpec) -> Self {
        let mut log = Self {
            individual_id: individual_id.to_string(),
            species_id: spec.species_id.clone(),
            spec_sha256: spec.spec_sha256.clone(),
            mapping_spec_hash: spec.mapping_spec_hash.clone(),
            phenomenal_claim: spec.phenomenal_claim.clone(),
            rows: Vec::new(),
        };
        let header_payload = format!(
            "id={};species={};spec_sha={};mapping_sha={};phenomenal_claim={}",
            individual_id, spec.species_id, spec.spec_sha256, spec.mapping_spec_hash, spec.phenomenal_claim
        );
        log.append_row("header", 0, header_payload);
        log
    }

    fn append_row(&mut self, kind: &str, step: u64, payload: String) -> AuditRow {
        let seq = self.rows.len() + 1;
        let prev = self
            .rows
            .last()
            .map(|r| r.hash.clone())
            .unwrap_or_else(|| GENESIS_HASH.to_string());
        let raw = format!("{seq}|{kind}|{step}|{payload}|{prev}");
        let hash = sha256_hex(raw.as_bytes());
        let row = AuditRow {
            seq,
            kind: kind.to_string(),
            step,
            payload,
            prev_hash: prev,
            hash,
        };
        self.rows.push(row.clone());
        row
    }

    pub fn verify_chain(&self) -> bool {
        if self.rows.is_empty() {
            return false;
        }
        let mut prev = GENESIS_HASH;
        for (idx, row) in self.rows.iter().enumerate() {
            if row.seq != idx + 1 || row.prev_hash != prev {
                return false;
            }
            let raw = format!("{}|{}|{}|{}|{}", row.seq, row.kind, row.step, row.payload, row.prev_hash);
            if sha256_hex(raw.as_bytes()) != row.hash {
                return false;
            }
            prev = &row.hash;
        }
        true
    }
}

pub fn parse_input_row(row: &AuditRow) -> Result<StampedInput, SeamError> {
    if row.kind != "input" {
        return Err(SeamError::ChainIntegrityError(format!(
            "expected input row, got {}",
            row.kind
        )));
    }
    let (kv_str, refs_str) = row
        .payload
        .split_once("|refs=")
        .ok_or_else(|| SeamError::ChainIntegrityError(format!("malformed input payload: {}", row.payload)))?;

    let mut ports = BTreeMap::new();
    if !kv_str.is_empty() {
        for item in kv_str.split(';') {
            let (k, v) = item
                .split_once('=')
                .ok_or_else(|| SeamError::ChainIntegrityError(format!("malformed kv item: {item}")))?;
            ports.insert(k.to_string(), PortVal::decode_typed(v)?);
        }
    }

    let mut event_refs = Vec::new();
    if !refs_str.is_empty() {
        for item in refs_str.split(',') {
            let (r, a_str) = item
                .rsplit_once(':')
                .ok_or_else(|| SeamError::ChainIntegrityError(format!("malformed ref item: {item}")))?;
            let amt = a_str
                .parse::<f64>()
                .map_err(|e| SeamError::ChainIntegrityError(format!("bad ref amount {a_str}: {e}")))?;
            event_refs.push((r.to_string(), amt));
        }
    }

    Ok(StampedInput {
        step: row.step,
        ports,
        event_refs,
    })
}

pub fn parse_termination_row(row: &AuditRow) -> Result<(TerminationCode, String), SeamError> {
    if row.kind != "termination" {
        return Err(SeamError::ChainIntegrityError(format!(
            "expected termination row, got {}",
            row.kind
        )));
    }
    let rest = row
        .payload
        .strip_prefix("code=")
        .ok_or_else(|| SeamError::ChainIntegrityError(format!("malformed termination: {}", row.payload)))?;
    let (code_s, ev_s) = rest
        .split_once(";evidence=")
        .ok_or_else(|| SeamError::ChainIntegrityError(format!("missing evidence: {}", row.payload)))?;
    Ok((TerminationCode::from_str(code_s)?, ev_s.to_string()))
}

// ------------------------------------------------------------------ Shared-Medium Double-Chain Audit

#[derive(Debug, Clone)]
pub struct SharedMediumEvent {
    pub seq: usize,
    pub event_ref: String,
    pub step: u64,
    pub resource_decrement: f64,
    pub prev_hash: String,
    pub hash: String,
}

#[derive(Debug, Clone)]
pub struct SharedMediumAudit {
    pub medium_id: String,
    pub events: Vec<SharedMediumEvent>,
    pub by_ref: BTreeMap<String, usize>,
}

impl SharedMediumAudit {
    pub fn new(medium_id: &str) -> Self {
        Self {
            medium_id: medium_id.to_string(),
            events: Vec::new(),
            by_ref: BTreeMap::new(),
        }
    }

    pub fn record_event(&mut self, event_ref: &str, step: u64, decrement: f64) -> Result<(), SeamError> {
        if self.by_ref.contains_key(event_ref) {
            return Err(SeamError::DoubleSpendViolation(format!(
                "duplicate medium event_ref: {event_ref}"
            )));
        }
        if !(decrement.is_finite() && decrement >= 0.0) {
            return Err(SeamError::DoubleSpendViolation(format!(
                "invalid medium decrement for {event_ref}"
            )));
        }
        let seq = self.events.len() + 1;
        let prev = self
            .events
            .last()
            .map(|e| e.hash.clone())
            .unwrap_or_else(|| GENESIS_HASH.to_string());
        let raw = format!("{seq}|{event_ref}|{step}|{decrement:.17}|{prev}");
        let hash = sha256_hex(raw.as_bytes());
        let idx = self.events.len();
        self.events.push(SharedMediumEvent {
            seq,
            event_ref: event_ref.to_string(),
            step,
            resource_decrement: decrement,
            prev_hash: prev,
            hash,
        });
        self.by_ref.insert(event_ref.to_string(), idx);
        Ok(())
    }

    pub fn verify(&self, individual_logs: &[&AuditLog], tol: f64) -> Result<(), SeamError> {
        let mut prev = GENESIS_HASH;
        for (idx, ev) in self.events.iter().enumerate() {
            if ev.seq != idx + 1 || ev.prev_hash != prev {
                return Err(SeamError::ChainIntegrityError(format!("medium chain broken at {idx}")));
            }
            let raw = format!(
                "{}|{}|{}|{:.17}|{}",
                ev.seq, ev.event_ref, ev.step, ev.resource_decrement, ev.prev_hash
            );
            if sha256_hex(raw.as_bytes()) != ev.hash {
                return Err(SeamError::ChainIntegrityError(format!("medium hash mismatch at {idx}")));
            }
            prev = &ev.hash;
        }

        // Parse claims STRICTLY from hash-chained `input` rows (no shadow array)
        let mut claimed: BTreeMap<String, f64> = BTreeMap::new();
        for log in individual_logs {
            if !log.verify_chain() {
                return Err(SeamError::ChainIntegrityError(format!(
                    "individual audit chain invalid: {}",
                    log.individual_id
                )));
            }
            for row in &log.rows {
                if row.kind != "input" {
                    continue;
                }
                let si = parse_input_row(row)?;
                for (r, amt) in si.event_refs {
                    if !self.by_ref.contains_key(&r) {
                        return Err(SeamError::DoubleSpendViolation(format!(
                            "unknown event_ref claimed: {r}"
                        )));
                    }
                    if !(amt.is_finite() && amt >= 0.0) {
                        return Err(SeamError::DoubleSpendViolation(format!("negative claim for {r}")));
                    }
                    *claimed.entry(r).or_insert(0.0) += amt;
                }
            }
        }

        for (ref_id, total_claim) in claimed {
            let cap = self.events[self.by_ref[&ref_id]].resource_decrement;
            if total_claim > cap + tol {
                return Err(SeamError::DoubleSpendViolation(format!(
                    "double-spend detected on event_ref={ref_id}: claimed={total_claim} > medium_decrement={cap}"
                )));
            }
        }
        Ok(())
    }
}

// ------------------------------------------------------------------ Seam 4: Generic Adapter Trait & Runner

pub struct StepOutcome<S> {
    pub next_state: S,
    pub output: DeclaredOutput,
    pub cost: StepCost,
    pub alive: bool,
    pub spore_req: Option<String>,
}

pub trait SpeciesAdapter {
    type State;

    fn spec(&self) -> &SpeciesSpec;
    fn state_digest(&self, state: &Self::State) -> String;
    fn step_species(
        &self,
        state: Self::State,
        stamped_in: &StampedInput,
        budget: Budget,
    ) -> StepOutcome<Self::State>;
}

pub struct RunResult<S> {
    pub state: S,
    pub ledger: Ledger,
    pub audit: AuditLog,
    pub final_digest: String,
}

fn validate_input_ports(spec: &SpeciesSpec, si: &StampedInput) -> Result<(), SeamError> {
    for k in si.ports.keys() {
        if !spec.ports_in.contains(k) {
            return Err(SeamError::PortViolation(format!(
                "undeclared input port {k:?} for species {}",
                spec.species_id
            )));
        }
    }
    Ok(())
}

fn validate_output_and_organ(spec: &SpeciesSpec, out: &DeclaredOutput) -> Result<(), SeamError> {
    for k in out.ports.keys() {
        if !spec.ports_out.contains(k) {
            return Err(SeamError::PortViolation(format!(
                "undeclared output port {k:?} for species {}",
                spec.species_id
            )));
        }
    }
    if !spec.allowed_organ_types.contains(&out.organ_type) {
        return Err(SeamError::SpeciesBoundaryViolation(format!(
            "organ_type {:?} outside allowed_organ_types for species {}",
            out.organ_type, spec.species_id
        )));
    }
    Ok(())
}

fn validate_budget(spec: &SpeciesSpec, cost: StepCost, ledger: &mut Ledger) -> Result<(), SeamError> {
    if cost.ops_used > spec.budget_per_step {
        return Err(SeamError::BudgetViolation(format!(
            "ops_used={} exceeds budget_per_step={}",
            cost.ops_used, spec.budget_per_step
        )));
    }
    let steps_per_hour = 3600.0 / spec.step_granularity_sec;
    let implied = (cost.ops_used as f64) * steps_per_hour;
    if implied > (spec.wall_budget_per_hour as f64) + 1e-9 {
        return Err(SeamError::BudgetViolation(format!(
            "wall-clock ops/hour={implied} exceeds cap {}",
            spec.wall_budget_per_hour
        )));
    }
    let now_sec = ((ledger.steps_completed + 1) as f64) * spec.step_granularity_sec;
    let win_start = now_sec - 3600.0;
    ledger.window_ops_history.retain(|(t, _)| *t > win_start + 1e-12);
    let win_sum: u64 = ledger
        .window_ops_history
        .iter()
        .map(|(_, o)| *o)
        .sum::<u64>()
        .saturating_add(cost.ops_used);
    if win_sum > spec.wall_budget_per_hour {
        return Err(SeamError::BudgetViolation(format!(
            "rolling 3600s window ops={win_sum} exceeds cap {} at t={now_sec}s",
            spec.wall_budget_per_hour
        )));
    }
    ledger.window_ops_history.push((now_sec, cost.ops_used));
    Ok(())
}

fn validate_dormancy(
    spec: &SpeciesSpec,
    cost: StepCost,
    ledger: &Ledger,
    adding_spore: bool,
) -> Result<(), SeamError> {
    let required_slots = ledger.dormancy_slots_used + if adding_spore { 1 } else { 0 };
    if required_slots > spec.dormancy_max_slots {
        return Err(SeamError::DormancyAccountingViolation(format!(
            "dormancy slots {required_slots} exceeds max_slots {}",
            spec.dormancy_max_slots
        )));
    }
    let required_upkeep = (required_slots as f64) * spec.dormancy_upkeep_rate;
    if cost.dormancy_upkeep_paid + 1e-12 < required_upkeep {
        return Err(SeamError::DormancyAccountingViolation(format!(
            "dormancy_upkeep_paid={} < required={required_upkeep} for {required_slots} slots",
            cost.dormancy_upkeep_paid
        )));
    }
    Ok(())
}

pub fn run_species<A: SpeciesAdapter>(
    adapter: &A,
    individual_id: &str,
    init_state: A::State,
    stamped_inputs: &[StampedInput],
    external_termination: Option<(TerminationCode, &str)>,
) -> Result<RunResult<A::State>, SeamError> {
    let spec = adapter.spec();
    let budget = Budget::from_spec(spec);
    let mut ledger = Ledger::new(individual_id);
    let mut audit = AuditLog::init(individual_id, spec);
    let mut state = init_state;

    for si in stamped_inputs {
        if ledger.termination == TerminationCode::MetabolicOrOrgDeath {
            break;
        }
        validate_input_ports(spec, si)?;

        let in_payload = format!(
            "{}|refs={}",
            canonical_kv_typed(&si.ports),
            canonical_refs(&si.event_refs)
        );
        audit.append_row("input", si.step, in_payload);

        let outcome = adapter.step_species(state, si, budget);
        validate_output_and_organ(spec, &outcome.output)?;

        if let Some(ref sp_id) = outcome.spore_req {
            if !outcome.alive || ledger.termination != TerminationCode::Running {
                return Err(SeamError::ProhibitedRescueError(format!(
                    "spore {sp_id} requested at/after death (step {}): prohibited rescue",
                    si.step
                )));
            }
            validate_dormancy(spec, outcome.cost, &ledger, true)?;
            validate_budget(spec, outcome.cost, &mut ledger)?;
            ledger.dormancy_slots_used += 1;
            let sp_row = audit.append_row(
                "spore",
                si.step,
                format!("spore_id={sp_id};cost={:.17}", outcome.cost.dormancy_upkeep_paid),
            );
            ledger.spores.push(SporeRecord {
                spore_id: sp_id.clone(),
                parent_id: ledger.individual_id.clone(),
                emitted_step: si.step,
                audit_row_hash: sp_row.hash,
                dormancy_cost_paid: outcome.cost.dormancy_upkeep_paid,
            });
        } else {
            validate_dormancy(spec, outcome.cost, &ledger, false)?;
            validate_budget(spec, outcome.cost, &mut ledger)?;
        }

        state = outcome.next_state;
        ledger.steps_completed += 1;
        ledger.cumulative_ops += outcome.cost.ops_used;
        ledger.cumulative_upkeep += outcome.cost.upkeep_paid;
        ledger.cumulative_act_cost += outcome.cost.act_cost;
        ledger.cumulative_dormancy_upkeep += outcome.cost.dormancy_upkeep_paid;

        let digest = adapter.state_digest(&state);
        let commit_payload = format!(
            "state_sha={};organ={};ops={};upkeep={:.17};act={:.17};dorm={:.17};alive={};out={}",
            digest,
            outcome.output.organ_type,
            outcome.cost.ops_used,
            outcome.cost.upkeep_paid,
            outcome.cost.act_cost,
            outcome.cost.dormancy_upkeep_paid,
            outcome.alive,
            canonical_kv_plain(&outcome.output.ports)
        );
        audit.append_row("commit", si.step, commit_payload);

        if !outcome.alive {
            ledger.termination = TerminationCode::MetabolicOrOrgDeath;
            ledger.death_step = Some(si.step);
            ledger.termination_evidence = "confirmed_final_state_dead".to_string();
            audit.append_row(
                "termination",
                si.step,
                format!(
                    "code={};evidence={}",
                    ledger.termination.as_str(),
                    ledger.termination_evidence
                ),
            );
            break;
        }
    }

    if let Some((code, ev)) = external_termination {
        if ledger.termination == TerminationCode::Running {
            match code {
                TerminationCode::NonMetabolicTerminationVerified => {
                    if ev.trim().is_empty() {
                        return Err(SeamError::ChainIntegrityError(
                            "NON_METABOLIC_TERMINATION_VERIFIED requires non-empty OS evidence".into(),
                        ));
                    }
                    ledger.termination = code;
                    ledger.termination_evidence = ev.to_string();
                    audit.append_row(
                        "termination",
                        ledger.steps_completed,
                        format!("code={};evidence={}", code.as_str(), ledger.termination_evidence),
                    );
                }
                TerminationCode::UnexplainedTruncation => {
                    ledger.termination = code;
                    ledger.termination_evidence = if ev.trim().is_empty() {
                        "no_external_os_evidence".to_string()
                    } else {
                        ev.to_string()
                    };
                    audit.append_row(
                        "termination",
                        ledger.steps_completed,
                        format!("code={};evidence={}", code.as_str(), ledger.termination_evidence),
                    );
                }
                _ => {
                    return Err(SeamError::ChainIntegrityError(format!(
                        "invalid external_termination code: {}",
                        code.as_str()
                    )));
                }
            }
        }
    }

    let final_digest = adapter.state_digest(&state);
    Ok(RunResult {
        state,
        ledger,
        audit,
        final_digest,
    })
}

pub fn attempt_post_death_spore(
    ledger: &Ledger,
    audit: &AuditLog,
    spore_id: &str,
) -> Result<(), SeamError> {
    if !audit.verify_chain() {
        return Err(SeamError::ChainIntegrityError("audit chain invalid".into()));
    }
    if ledger.termination != TerminationCode::Running {
        return Err(SeamError::ProhibitedRescueError(format!(
            "external post-termination spore {spore_id} rejected (termination={}, death_step={:?})",
            ledger.termination.as_str(),
            ledger.death_step
        )));
    }
    Err(SeamError::ProhibitedRescueError(format!(
        "external spore injection outside step_species is forbidden ({spore_id})"
    )))
}

pub fn replay_from_audit<A: SpeciesAdapter>(
    adapter: &A,
    init_state: A::State,
    reference_audit: &AuditLog,
) -> Result<RunResult<A::State>, SeamError> {
    if !reference_audit.verify_chain() {
        return Err(SeamError::ChainIntegrityError("reference audit chain invalid".into()));
    }
    let mut parsed_inputs = Vec::new();
    let mut term_rows = Vec::new();
    for row in &reference_audit.rows {
        if row.kind == "input" {
            parsed_inputs.push(parse_input_row(row)?);
        } else if row.kind == "termination" {
            term_rows.push(row);
        }
    }
    if term_rows.len() > 1 {
        return Err(SeamError::ChainIntegrityError("multiple termination rows".into()));
    }
    let parsed_term = if let Some(tr) = term_rows.first() {
        Some(parse_termination_row(tr)?)
    } else {
        None
    };
    let ext_term = match parsed_term {
        Some((
            code @ (TerminationCode::NonMetabolicTerminationVerified
            | TerminationCode::UnexplainedTruncation),
            ref ev,
        )) => Some((code, ev.as_str())),
        _ => None,
    };

    let res = run_species(
        adapter,
        &reference_audit.individual_id,
        init_state,
        &parsed_inputs,
        ext_term,
    )?;

    if res.audit.rows.len() != reference_audit.rows.len() {
        return Err(SeamError::ChainIntegrityError("replay row count mismatch".into()));
    }
    for (r_ref, r_rep) in reference_audit.rows.iter().zip(res.audit.rows.iter()) {
        if r_ref != r_rep {
            return Err(SeamError::ChainIntegrityError(format!(
                "replay row mismatch at seq {}",
                r_ref.seq
            )));
        }
    }
    Ok(res)
}

pub fn germinate_lineage_child(
    parent_ledger: &Ledger,
    parent_audit: &AuditLog,
    spore_id: &str,
    child_id: &str,
) -> Result<LineageChild, SeamError> {
    if !parent_audit.verify_chain() {
        return Err(SeamError::ChainIntegrityError("parent audit chain invalid".into()));
    }
    if parent_ledger.termination != TerminationCode::MetabolicOrOrgDeath {
        return Err(SeamError::ProhibitedRescueError(format!(
            "germination expects dead parent, got {}",
            parent_ledger.termination.as_str()
        )));
    }
    let death_step = parent_ledger
        .death_step
        .ok_or_else(|| SeamError::ChainIntegrityError("missing death_step".into()))?;
    let sp = parent_ledger
        .spores
        .iter()
        .find(|s| s.spore_id == spore_id)
        .ok_or_else(|| SeamError::ProhibitedRescueError(format!("spore {spore_id} not in parent ledger")))?;
    let sp_idx = parent_audit
        .rows
        .iter()
        .position(|r| r.kind == "spore" && r.hash == sp.audit_row_hash)
        .ok_or_else(|| SeamError::ProhibitedRescueError(format!("spore {spore_id} not attested in audit")))?;
    let term_idx = parent_audit
        .rows
        .iter()
        .position(|r| r.kind == "termination")
        .ok_or_else(|| SeamError::ChainIntegrityError("missing termination row".into()))?;
    if !(sp_idx < term_idx && sp.emitted_step < death_step) {
        return Err(SeamError::ProhibitedRescueError(format!(
            "spore {spore_id} not emitted strictly before death"
        )));
    }
    Ok(LineageChild {
        child_id: child_id.to_string(),
        parent_id: parent_ledger.individual_id.clone(),
        source_spore_id: spore_id.to_string(),
        same_individual: false,
        lineage_child: true,
        verified_pre_death: true,
    })
}
