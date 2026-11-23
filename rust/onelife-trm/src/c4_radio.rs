//! S68 r2 deterministic C4 radio conversion, NTP-immune stale tracker, and `rand_u64` derivation.
//! Uses frozen S65 C4 constants, precomputed 1000-entry `SIN_TABLE_1000`, and IEEE 754 `round_ties_even`.

use crate::sha256::{sha256, sha256_hex};

pub const MU_W: f64 = 297.20108758532916;
pub const SD_W: f64 = 39.79874519579147;
pub const MU_B: f64 = 2.9924794631493694;
pub const SD_B: f64 = 0.8134565410732445;

pub const EMPTY_ROW_SHA: &str = "EMPTY_NO_ROW";

#[derive(Debug, Clone, PartialEq)]
pub struct AmbientObservation {
    pub pi_s: String,
    pub boot: String,
    pub uptime_s: f64,
    pub w_sum: f64,
    pub b_n: f64,
    pub raw_line_sha256: String,
}

/// Extract the last complete (LF-terminated) valid (`fail == 0`, finite `w_sum` & `b_n`) observation.
/// Incomplete trailing fragments without `\n` are ignored cleanly without write races.
pub fn parse_last_valid_ambient(bytes: &[u8]) -> Option<AmbientObservation> {
    let last_nl = bytes.iter().rposition(|&b| b == b'\n')?;
    let complete = &bytes[..last_nl];
    for raw_line in complete.rsplit(|&b| b == b'\n') {
        let trimmed = raw_line.strip_suffix(b"\r").unwrap_or(raw_line);
        let Ok(line) = std::str::from_utf8(trimmed) else {
            continue;
        };
        if line.is_empty() || line.starts_with("pi_s\t") {
            continue;
        }
        let cols: Vec<&str> = line.split('\t').collect();
        // S52 ambient.tsv columns: pi_s, boot, uptime_s, w_n, w_sum, b_n, t_mc, fail
        if cols.len() < 8 {
            continue;
        }
        let Ok(fail) = cols[7].parse::<i64>() else {
            continue;
        };
        if fail != 0 {
            continue;
        }
        if cols[4] == "NA" || cols[5] == "NA" {
            continue;
        }
        let (Ok(uptime_s), Ok(w_sum), Ok(b_n)) = (
            cols[2].parse::<f64>(),
            cols[4].parse::<f64>(),
            cols[5].parse::<f64>(),
        ) else {
            continue;
        };
        if !(uptime_s.is_finite() && w_sum.is_finite() && b_n.is_finite()) {
            continue;
        }
        return Some(AmbientObservation {
            pi_s: cols[0].to_string(),
            boot: cols[1].to_string(),
            uptime_s,
            w_sum,
            b_n,
            raw_line_sha256: sha256_hex(trimmed),
        });
    }
    None
}

/// NTP-immune stale tracker (S68 r2 §2): ignores wall-clock `pi_s` completely.
/// Fires `stale = true` iff:
///   1) no valid row seen yet, OR
///   2) same `(boot, uptime_s)` seen for `same_row_streak >= 14` steps (> 120s at 10s/step), OR
///   3) within same `boot`, `now_mono_s - last_new_mono_s > 120.0`.
#[derive(Debug, Clone, Default)]
pub struct StaleTracker {
    pub last_boot: Option<String>,
    pub last_uptime_s: f64,
    pub same_row_streak: u64,
    pub last_new_mono_s: f64,
}

impl StaleTracker {
    pub fn observe(&mut self, obs: Option<&AmbientObservation>, now_mono_s: f64) -> bool {
        let Some(o) = obs else {
            return true;
        };
        let is_new = match &self.last_boot {
            None => true,
            Some(prev_boot) => prev_boot != &o.boot || o.uptime_s > self.last_uptime_s,
        };
        if is_new {
            self.last_boot = Some(o.boot.clone());
            self.last_uptime_s = o.uptime_s;
            self.same_row_streak = 1;
            self.last_new_mono_s = now_mono_s;
            return false;
        }
        self.same_row_streak = self.same_row_streak.saturating_add(1);
        (self.same_row_streak >= 14) || ((now_mono_s - self.last_new_mono_s) > 120.0)
    }
}

/// S68 r2 §2: IEEE 754 round-half-to-even (`round_ties_even`), clamped to `0..=5`.
#[inline]
pub fn round_yield_s68(x: f64) -> f64 {
    x.round_ties_even().clamp(0.0, 5.0)
}

/// Compute C4 yields `(g1, g2)` from a precomputed 1000-entry sine table.
pub fn compute_c4_yields(
    sin_table_1000: &[f64; 1000],
    step: u64,
    w_sum: f64,
    b_n: f64,
    stale_flag: bool,
) -> (f64, f64) {
    let (z1, z2) = if stale_flag {
        (0.0, 0.0)
    } else {
        ((w_sum - MU_W) / SD_W, (b_n - MU_B) / SD_B)
    };
    let i1 = (step % 1000) as usize;
    let i2 = ((step + 500) % 1000) as usize;
    let x1 = (2.5 + (2.5 * sin_table_1000[i1])) + z1;
    let x2 = (2.5 + (2.5 * sin_table_1000[i2])) + z2;
    (round_yield_s68(x1), round_yield_s68(x2))
}

/// S68 r2 §3: deterministic `rand_u64` derivation re-verifiable on replay.
pub fn derive_rand_u64(
    prev_commit_hash: &str,
    step: u64,
    raw_line_sha256: &str,
    stale_flag: bool,
) -> u64 {
    let flag = if stale_flag { 1u8 } else { 0u8 };
    let msg = format!("AUE-DRAW-V1|{prev_commit_hash}|{step}|{raw_line_sha256}|{flag}");
    let digest = sha256(msg.as_bytes());
    u64::from_le_bytes([
        digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
    ])
}
