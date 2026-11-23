//! Seam 1: `species_spec.toml` strict zero-dependency parser & invariant validator.
//! Matches `experiments/aue_seam/bed.jl` `SpeciesSpec` and `load_species_spec`.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;

use crate::sha256::sha256_hex;

#[derive(Debug, Clone, PartialEq)]
pub struct SpeciesSpec {
    pub species_id: String,
    pub spec_version: String,
    pub substrate: String,
    pub individual_boundary: String,
    pub allowed_organ_types: BTreeSet<String>,
    pub ports_in: BTreeSet<String>,
    pub ports_out: BTreeSet<String>,
    pub step_granularity_sec: f64,
    pub budget_per_step: u64,
    pub wall_budget_per_hour: u64,
    pub dormancy_upkeep_rate: f64,
    pub dormancy_max_slots: usize,
    pub mapping_spec_hash: String,
    pub phenomenal_claim: String,
    pub spec_sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SpecError {
    Io(String),
    Parse(String),
    Invariant(String),
}

impl std::fmt::Display for SpecError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SpecError::Io(m) => write!(f, "SpecError::Io: {m}"),
            SpecError::Parse(m) => write!(f, "SpecError::Parse: {m}"),
            SpecError::Invariant(m) => write!(f, "SpecError::Invariant: {m}"),
        }
    }
}

fn strip_comment(line: &str) -> &str {
    let mut in_str = false;
    let mut prev_esc = false;
    for (idx, ch) in line.char_indices() {
        if in_str {
            if prev_esc {
                prev_esc = false;
            } else if ch == '\\' {
                prev_esc = true;
            } else if ch == '"' {
                in_str = false;
            }
        } else if ch == '"' {
            in_str = true;
        } else if ch == '#' {
            return &line[..idx];
        }
    }
    line
}

fn parse_string_literal(raw: &str) -> Result<String, SpecError> {
    let s = raw.trim();
    if !(s.starts_with('"') && s.ends_with('"') && s.len() >= 2) {
        return Err(SpecError::Parse(format!("expected quoted string, got {s:?}")));
    }
    Ok(s[1..s.len() - 1].to_string())
}

fn parse_string_array(raw: &str) -> Result<BTreeSet<String>, SpecError> {
    let s = raw.trim();
    if !(s.starts_with('[') && s.ends_with(']')) {
        return Err(SpecError::Parse(format!("expected array, got {s:?}")));
    }
    let inner = s[1..s.len() - 1].trim();
    let mut set = BTreeSet::new();
    if inner.is_empty() {
        return Ok(set);
    }
    for item in inner.split(',') {
        let t = item.trim();
        if t.is_empty() {
            continue;
        }
        set.insert(parse_string_literal(t)?);
    }
    Ok(set)
}

impl SpeciesSpec {
    pub fn from_toml_file(path: &Path) -> Result<Self, SpecError> {
        let bytes = fs::read(path).map_err(|e| SpecError::Io(format!("{}: {e}", path.display())))?;
        Self::from_toml_bytes(&bytes)
    }

    pub fn from_toml_bytes(raw: &[u8]) -> Result<Self, SpecError> {
        let spec_sha256 = sha256_hex(raw);
        let text = std::str::from_utf8(raw)
            .map_err(|e| SpecError::Parse(format!("non-UTF8 TOML: {e}")))?;

        let mut kv: BTreeMap<String, String> = BTreeMap::new();
        let mut section = String::new();
        for (lineno, line) in text.lines().enumerate() {
            let clean = strip_comment(line).trim();
            if clean.is_empty() {
                continue;
            }
            if clean.starts_with('[') && clean.ends_with(']') {
                section = clean[1..clean.len() - 1].trim().to_string();
                continue;
            }
            let eq = clean.find('=').ok_or_else(|| {
                SpecError::Parse(format!("line {}: expected key = value, got {clean:?}", lineno + 1))
            })?;
            let k = clean[..eq].trim();
            let v = clean[eq + 1..].trim();
            let full_key = if section.is_empty() {
                k.to_string()
            } else {
                format!("{section}.{k}")
            };
            if kv.insert(full_key.clone(), v.to_string()).is_some() {
                return Err(SpecError::Parse(format!("duplicate key {full_key}")));
            }
        }

        let req = |k: &str| -> Result<&str, SpecError> {
            kv.get(k)
                .map(|s| s.as_str())
                .ok_or_else(|| SpecError::Parse(format!("missing required key {k}")))
        };

        let phenomenal_claim = parse_string_literal(req("phenomenal_claim")?)?;
        if phenomenal_claim != "not_certified" {
            return Err(SpecError::Invariant(format!(
                "phenomenal_claim must be \"not_certified\", got {phenomenal_claim:?}"
            )));
        }

        let step_granularity_sec: f64 = req("budget.step_granularity_sec")?
            .parse()
            .map_err(|e| SpecError::Parse(format!("budget.step_granularity_sec: {e}")))?;
        if !(step_granularity_sec.is_finite() && step_granularity_sec > 0.0) {
            return Err(SpecError::Invariant("step_granularity_sec must be > 0".into()));
        }

        let budget_per_step: u64 = req("budget.ops_per_step")?
            .parse()
            .map_err(|e| SpecError::Parse(format!("budget.ops_per_step: {e}")))?;
        let wall_budget_per_hour: u64 = req("budget.ops_per_hour")?
            .parse()
            .map_err(|e| SpecError::Parse(format!("budget.ops_per_hour: {e}")))?;
        if budget_per_step == 0 || wall_budget_per_hour == 0 {
            return Err(SpecError::Invariant("budget caps must be positive".into()));
        }

        let dormancy_upkeep_rate: f64 = req("dormancy.upkeep_rate_per_slot")?
            .parse()
            .map_err(|e| SpecError::Parse(format!("dormancy.upkeep_rate_per_slot: {e}")))?;
        if !(dormancy_upkeep_rate.is_finite() && dormancy_upkeep_rate > 0.0) {
            return Err(SpecError::Invariant(
                "dormancy upkeep_rate_per_slot must be > 0 (no free memory)".into(),
            ));
        }

        let dormancy_max_slots: usize = req("dormancy.max_slots")?
            .parse()
            .map_err(|e| SpecError::Parse(format!("dormancy.max_slots: {e}")))?;

        Ok(SpeciesSpec {
            species_id: parse_string_literal(req("species_id")?)?,
            spec_version: parse_string_literal(req("spec_version")?)?,
            substrate: parse_string_literal(req("substrate")?)?,
            individual_boundary: parse_string_literal(req("individual_boundary")?)?,
            allowed_organ_types: parse_string_array(req("allowed_organ_types")?)?,
            ports_in: parse_string_array(req("ports.inputs")?)?,
            ports_out: parse_string_array(req("ports.outputs")?)?,
            step_granularity_sec,
            budget_per_step,
            wall_budget_per_hour,
            dormancy_upkeep_rate,
            dormancy_max_slots,
            mapping_spec_hash: parse_string_literal(req("mapping_spec_hash")?)?,
            phenomenal_claim,
            spec_sha256,
        })
    }
}
