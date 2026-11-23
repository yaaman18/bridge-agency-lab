//! S68 r2 §3 S49d-aligned deterministic power-loss recovery state machine (Cases A, B, C, D).
//! Guarantees zero duplicate steps, zero skipped steps, and continuous phase `n` across abrupt power loss.

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuditTail {
    Empty,
    Header,
    CompleteInput { step: u64, raw_line: String },
    CompleteCommit { step: u64 },
    PartialFragment { raw_fragment: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RecoveryAction {
    /// Case A: `input(n)` fsynced, `run` still at `n` -> execute step `n` ONCE with stamped input, rename `run`, append `commit(n)`.
    ExecuteStampedInputOnce { step: u64, raw_line: String },
    /// Case B: `run` already renamed to `n+1`, `commit(n)` missing -> append `commit(n)` from `run`, then proceed to `n+1`.
    EmitMissingCommitFromRun { step: u64, next_step: u64 },
    /// Case C: `commit(n)` fsynced and `run` at `n+1` -> resume cleanly at `n+1`.
    ResumeClean { next_step: u64 },
    /// Case D: trailing incomplete non-LF fragment -> record `break` boundary, discard incomplete fragment, acquire step `run_step`.
    TruncatePartialAndAcquire { next_step: u64, fragment_len: usize },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecoveryError(pub String);

/// Inspect raw audit bytes (preserving whether the last byte is `\n`) and determine the tail state.
pub fn inspect_audit_tail(audit_bytes: &[u8]) -> AuditTail {
    if audit_bytes.is_empty() {
        return AuditTail::Empty;
    }
    if !audit_bytes.ends_with(b"\n") {
        let frag_start = audit_bytes
            .iter()
            .rposition(|&b| b == b'\n')
            .map(|i| i + 1)
            .unwrap_or(0);
        let frag = String::from_utf8_lossy(&audit_bytes[frag_start..]).to_string();
        return AuditTail::PartialFragment { raw_fragment: frag };
    }
    let without_last_nl = &audit_bytes[..audit_bytes.len() - 1];
    let last_line_start = without_last_nl
        .iter()
        .rposition(|&b| b == b'\n')
        .map(|i| i + 1)
        .unwrap_or(0);
    let line = String::from_utf8_lossy(&without_last_nl[last_line_start..]).to_string();
    let parts: Vec<&str> = line.split('|').collect();
    if parts.len() >= 3 {
        match parts[1] {
            "header" => return AuditTail::Header,
            "input" => {
                if let Ok(step) = parts[2].parse::<u64>() {
                    return AuditTail::CompleteInput {
                        step,
                        raw_line: line,
                    };
                }
            }
            "commit" => {
                if let Ok(step) = parts[2].parse::<u64>() {
                    return AuditTail::CompleteCommit { step };
                }
            }
            _ => {}
        }
    }
    AuditTail::PartialFragment { raw_fragment: line }
}

/// Decide the exact deterministic recovery action given persisted `run.step` and `run.audit` bytes.
pub fn plan_recovery(run_step: u64, audit_bytes: &[u8]) -> Result<RecoveryAction, RecoveryError> {
    match inspect_audit_tail(audit_bytes) {
        AuditTail::Empty | AuditTail::Header => {
            if run_step == 0 {
                Ok(RecoveryAction::ResumeClean { next_step: 0 })
            } else {
                Err(RecoveryError(format!(
                    "audit empty/header-only but run_step={run_step} > 0"
                )))
            }
        }
        AuditTail::CompleteInput { step, raw_line } => {
            if run_step == step {
                // Case A: input(n) fsynced, run still at n
                Ok(RecoveryAction::ExecuteStampedInputOnce { step, raw_line })
            } else if run_step == step + 1 {
                // Case B: run already atomic-renamed to n+1 before commit(n) fsync
                Ok(RecoveryAction::EmitMissingCommitFromRun {
                    step,
                    next_step: step + 1,
                })
            } else {
                Err(RecoveryError(format!(
                    "inconsistent input({step}) vs run_step={run_step}"
                )))
            }
        }
        AuditTail::CompleteCommit { step } => {
            if run_step == step + 1 {
                // Case C: commit(n) fsynced cleanly
                Ok(RecoveryAction::ResumeClean {
                    next_step: step + 1,
                })
            } else {
                Err(RecoveryError(format!(
                    "inconsistent commit({step}) vs run_step={run_step}"
                )))
            }
        }
        AuditTail::PartialFragment { raw_fragment } => {
            // Case D: non-LF partial fragment -> mark break, discard fragment, resume at run_step
            Ok(RecoveryAction::TruncatePartialAndAcquire {
                next_step: run_step,
                fragment_len: raw_fragment.len(),
            })
        }
    }
}
