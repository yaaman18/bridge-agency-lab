//! S68 r2 §3 S49d-aligned deterministic power-loss recovery state machine (Cases A, B, C, D).
//! Guarantees zero duplicate steps, zero skipped steps, and continuous phase `n` across abrupt power loss.
//!
//! Planning is pure: it reads `run.step` and the raw `run.audit` bytes and never changes them.
//! A complete (LF-terminated) line that cannot be read as header/input/commit is an error, never a fragment:
//! only the bytes after the last LF (an unterminated tail) may be discarded (Case D).

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuditTail {
    Empty,
    Header,
    CompleteInput { step: u64, raw_line: String },
    CompleteCommit { step: u64 },
    /// An LF-terminated last line that is not a header, input or commit line (corruption; recovery must stop).
    Malformed { raw_line: String },
    /// Unterminated bytes after the last LF. `fragment_len` counts raw bytes (not UTF-8 characters).
    PartialFragment { fragment_len: usize },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RecoveryAction {
    /// Case A: `input(n)` fsynced, `run` still at `n` -> execute step `n` ONCE with stamped input, rename `run`, append `commit(n)`.
    ExecuteStampedInputOnce { step: u64, raw_line: String },
    /// Case B: `run` already renamed to `n+1`, `commit(n)` missing -> append `commit(n)` from `run`, then proceed to `n+1`.
    EmitMissingCommitFromRun { step: u64, next_step: u64 },
    /// Case C: `commit(n)` fsynced and `run` at `n+1` -> resume cleanly at `n+1`.
    ResumeClean { next_step: u64 },
    /// Case D: an unterminated `input(n)` fragment after `commit(n-1)` -> record the `break` boundary, discard the fragment
    /// (`fragment_len` raw bytes), acquire step `next_step` again.
    TruncatePartialAndAcquire { next_step: u64, fragment_len: usize },
    /// Case D followed by A or B: an unterminated fragment (e.g. a partial `commit(n)`) after a complete `input(n)` ->
    /// record the `break` boundary, discard the fragment, then do `then` (never acquire a second `input(n)`).
    TruncatePartialThen { fragment_len: usize, then: Box<RecoveryAction> },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecoveryError(pub String);

/// The byte index just after the last LF (0 if there is none).
fn after_last_lf(bytes: &[u8]) -> usize {
    bytes.iter().rposition(|&b| b == b'\n').map(|i| i + 1).unwrap_or(0)
}

/// Read one complete line (without its LF).
fn classify_line(raw: &[u8]) -> AuditTail {
    let line = String::from_utf8_lossy(raw).to_string();
    let parts: Vec<&str> = line.split('|').collect();
    if parts.len() >= 3 {
        match parts[1] {
            "header" => return AuditTail::Header,
            "input" => {
                if let Ok(step) = parts[2].parse::<u64>() {
                    return AuditTail::CompleteInput { step, raw_line: line };
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
    AuditTail::Malformed { raw_line: line }
}

/// Inspect raw audit bytes (preserving whether the last byte is `\n`) and determine the tail state.
pub fn inspect_audit_tail(audit_bytes: &[u8]) -> AuditTail {
    if audit_bytes.is_empty() {
        return AuditTail::Empty;
    }
    if !audit_bytes.ends_with(b"\n") {
        return AuditTail::PartialFragment {
            fragment_len: audit_bytes.len() - after_last_lf(audit_bytes),
        };
    }
    let body = &audit_bytes[..audit_bytes.len() - 1];
    classify_line(&body[after_last_lf(body)..])
}

/// Plan for an audit whose bytes end at a line boundary (empty or LF-terminated).
fn plan_complete(run_step: u64, audit_bytes: &[u8]) -> Result<RecoveryAction, RecoveryError> {
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
            } else if step.checked_add(1) == Some(run_step) {
                // Case B: run already atomic-renamed to n+1 before commit(n) fsync (checked: no wrap at u64::MAX)
                Ok(RecoveryAction::EmitMissingCommitFromRun {
                    step,
                    next_step: run_step,
                })
            } else {
                Err(RecoveryError(format!(
                    "inconsistent input({step}) vs run_step={run_step}"
                )))
            }
        }
        AuditTail::CompleteCommit { step } => {
            if step.checked_add(1) == Some(run_step) {
                // Case C: commit(n) fsynced cleanly (checked: no wrap at u64::MAX)
                Ok(RecoveryAction::ResumeClean {
                    next_step: run_step,
                })
            } else {
                Err(RecoveryError(format!(
                    "inconsistent commit({step}) vs run_step={run_step}"
                )))
            }
        }
        AuditTail::Malformed { raw_line } => Err(RecoveryError(format!(
            "malformed complete audit line (not header/input/commit): {raw_line:?}"
        ))),
        AuditTail::PartialFragment { .. } => {
            Err(RecoveryError("internal: plan_complete given an unterminated tail".into()))
        }
    }
}

/// Decide the exact deterministic recovery action given persisted `run.step` and `run.audit` bytes.
pub fn plan_recovery(run_step: u64, audit_bytes: &[u8]) -> Result<RecoveryAction, RecoveryError> {
    let cut = after_last_lf(audit_bytes);
    if cut == audit_bytes.len() {
        return plan_complete(run_step, audit_bytes);
    }
    // Case D: plan on the complete prefix first; the fragment is discarded either way.
    let fragment_len = audit_bytes.len() - cut;
    match plan_complete(run_step, &audit_bytes[..cut])? {
        RecoveryAction::ResumeClean { next_step } => Ok(RecoveryAction::TruncatePartialAndAcquire {
            next_step,
            fragment_len,
        }),
        then => Ok(RecoveryAction::TruncatePartialThen {
            fragment_len,
            then: Box::new(then),
        }),
    }
}
