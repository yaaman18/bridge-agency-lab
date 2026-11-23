//! S67 r2: 97-parameter C2 online head learning (`w8[32]`, `w7[32]`, `we[32]`, `be`).
//! Strict IEEE 754 `binary32` evaluation order, zero FMA, left-associative sums,
//! zero-`exp` closed-form `stablemax` gradient for `lm_head`, S60 `exp_det` for `e_head`.

// ---------------- S60 exp_det (verbatim from rust/trm-det/src/main.rs) ----------------

const LOG2E: u32 = 0x3fb8aa3b;
const LN2_HI: u32 = 0x3f317200;
const LN2_LO: u32 = 0x35bfbe8e;
const C0: u32 = 0x3f800000;
const C1: u32 = 0x3f800000;
const C2: u32 = 0x3f000000;
const C3: u32 = 0x3e2aaaab;
const C4: u32 = 0x3d2aaaab;
const C5: u32 = 0x3c088889;
const C6: u32 = 0x3ab60b61;
const C7: u32 = 0x39500d01;

#[inline(always)]
fn fb(b: u32) -> f32 {
    f32::from_bits(b)
}

pub fn exp_det(x: f32) -> f32 {
    if x.is_nan() {
        return x;
    }
    if x > 88.0f32 {
        return f32::INFINITY;
    }
    if x < -87.0f32 {
        return 0.0f32;
    }
    let t = x * fb(LOG2E);
    let y = t + 0.5f32;
    let mut i = y as i32;
    if (i as f32) > y {
        i -= 1;
    }
    let k = i as f32;
    let r = (x - k * fb(LN2_HI)) - k * fb(LN2_LO);
    let mut p = fb(C7);
    p = p * r;
    p = p + fb(C6);
    p = p * r;
    p = p + fb(C5);
    p = p * r;
    p = p + fb(C4);
    p = p * r;
    p = p + fb(C3);
    p = p * r;
    p = p + fb(C2);
    p = p * r;
    p = p + fb(C1);
    p = p * r;
    p = p + fb(C0);
    let scale = f32::from_bits(((i + 127) as u32) << 23);
    p * scale
}

pub const HIDDEN: usize = 32;
pub const FADE_KEEP: f32 = 0.875f32; // 1 - 1/8 (exact binary32)
pub const WEIGHT_BOUND: f32 = 16.0f32;
pub const GRAD_CLIP: f32 = 1.0f32;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NonFiniteWeightError(pub String);

#[derive(Debug, Clone, PartialEq)]
pub struct HeadWeights {
    pub w8: [f32; HIDDEN],
    pub w7: [f32; HIDDEN],
    pub we: [f32; HIDDEN],
    pub be: f32,
}

impl HeadWeights {
    pub fn check_finite(&self) -> Result<(), NonFiniteWeightError> {
        for (i, &v) in self.w8.iter().enumerate() {
            if !v.is_finite() {
                return Err(NonFiniteWeightError(format!("w8[{i}] non-finite: {v}")));
            }
        }
        for (i, &v) in self.w7.iter().enumerate() {
            if !v.is_finite() {
                return Err(NonFiniteWeightError(format!("w7[{i}] non-finite: {v}")));
            }
        }
        for (i, &v) in self.we.iter().enumerate() {
            if !v.is_finite() {
                return Err(NonFiniteWeightError(format!("we[{i}] non-finite: {v}")));
            }
        }
        if !self.be.is_finite() {
            return Err(NonFiniteWeightError(format!("be non-finite: {}", self.be)));
        }
        Ok(())
    }

    pub fn to_le_bytes(&self) -> [u8; 97 * 4] {
        let mut out = [0u8; 97 * 4];
        let mut off = 0;
        for &v in &self.w8 {
            out[off..off + 4].copy_from_slice(&v.to_le_bytes());
            off += 4;
        }
        for &v in &self.w7 {
            out[off..off + 4].copy_from_slice(&v.to_le_bytes());
            off += 4;
        }
        for &v in &self.we {
            out[off..off + 4].copy_from_slice(&v.to_le_bytes());
            off += 4;
        }
        out[off..off + 4].copy_from_slice(&self.be.to_le_bytes());
        out
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct HeadPrediction {
    pub l8: f32,
    pub l7: f32,
    pub p: f32,
    pub e: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HeadStepAction {
    FrozenOnDeath,
    FadedOnUpkeepShortfall,
    SkippedOnBudget,
    Updated,
}

#[inline(always)]
fn dot32_left(w: &[f32; HIDDEN], h: &[f32; HIDDEN]) -> f32 {
    let mut acc = 0.0f32;
    for k in 0..HIDDEN {
        acc = acc + (w[k] * h[k]);
    }
    acc
}

#[inline(always)]
pub fn stablemax_s(x: f32) -> f32 {
    if x >= 0.0f32 {
        x + 1.0f32
    } else {
        1.0f32 / (1.0f32 - x)
    }
}

#[inline(always)]
fn clamp_f32(x: f32, lo: f32, hi: f32) -> f32 {
    if x.is_nan() {
        return x; // never mask NaN
    }
    if x < lo {
        lo
    } else if x > hi {
        hi
    } else {
        x
    }
}

#[derive(Debug, Clone)]
pub struct HeadC2 {
    pub w: HeadWeights,
    pub w0: HeadWeights,
    pub eta_head: f32,
}

impl HeadC2 {
    pub fn new(w0: HeadWeights, eta_head: f32) -> Result<Self, NonFiniteWeightError> {
        w0.check_finite()?;
        Ok(Self {
            w: w0.clone(),
            w0,
            eta_head,
        })
    }

    pub fn predict(&self, h: &[f32; HIDDEN]) -> HeadPrediction {
        let l8 = dot32_left(&self.w.w8, h);
        let l7 = dot32_left(&self.w.w7, h);
        let s8 = stablemax_s(l8);
        let s7 = stablemax_s(l7);
        let p = s8 / (s8 + s7);
        let ze = dot32_left(&self.w.we, h) + self.w.be;
        let e = 1.0f32 / (1.0f32 + exp_det(-ze));
        HeadPrediction { l8, l7, p, e }
    }

    /// Exact S67 r2 §2 post-step update accounting:
    /// - `!alive_post` => freeze 97 weights (no fade, no update).
    /// - `!upkeep_paid_full` => skip gradient update AND fade toward `w0` by `0.875f32`.
    /// - `!has_budget_for_update` => skip gradient update WITHOUT fade.
    /// - Otherwise => exact closed-form `stablemax` + `e_head` binary32 SGD update.
    pub fn post_step_update(
        &mut self,
        alive_post: bool,
        upkeep_paid_full: bool,
        has_budget_for_update: bool,
        h: &[f32; HIDDEN],
        pred: HeadPrediction,
        y_obs: bool,
    ) -> Result<HeadStepAction, NonFiniteWeightError> {
        if !alive_post {
            return Ok(HeadStepAction::FrozenOnDeath);
        }
        if !upkeep_paid_full {
            for k in 0..HIDDEN {
                self.w.w8[k] = clamp_f32(
                    self.w0.w8[k] + FADE_KEEP * (self.w.w8[k] - self.w0.w8[k]),
                    -WEIGHT_BOUND,
                    WEIGHT_BOUND,
                );
                self.w.w7[k] = clamp_f32(
                    self.w0.w7[k] + FADE_KEEP * (self.w.w7[k] - self.w0.w7[k]),
                    -WEIGHT_BOUND,
                    WEIGHT_BOUND,
                );
                self.w.we[k] = clamp_f32(
                    self.w0.we[k] + FADE_KEEP * (self.w.we[k] - self.w0.we[k]),
                    -WEIGHT_BOUND,
                    WEIGHT_BOUND,
                );
            }
            self.w.be = clamp_f32(
                self.w0.be + FADE_KEEP * (self.w.be - self.w0.be),
                -WEIGHT_BOUND,
                WEIGHT_BOUND,
            );
            self.w.check_finite()?;
            return Ok(HeadStepAction::FadedOnUpkeepShortfall);
        }
        if !has_budget_for_update {
            return Ok(HeadStepAction::SkippedOnBudget);
        }

        let yf = if y_obs { 1.0f32 } else { 0.0f32 };
        let gl8 = (pred.p - yf) / (1.0f32 + pred.l8.abs());
        let gl7 = (yf - pred.p) / (1.0f32 + pred.l7.abs());
        let ye_bool = (pred.p >= 0.5f32) != y_obs;
        let yef = if ye_bool { 1.0f32 } else { 0.0f32 };
        let gbe = pred.e - yef;

        for k in 0..HIDDEN {
            let gc8 = clamp_f32(gl8 * h[k], -GRAD_CLIP, GRAD_CLIP);
            self.w.w8[k] = clamp_f32(self.w.w8[k] - (self.eta_head * gc8), -WEIGHT_BOUND, WEIGHT_BOUND);

            let gc7 = clamp_f32(gl7 * h[k], -GRAD_CLIP, GRAD_CLIP);
            self.w.w7[k] = clamp_f32(self.w.w7[k] - (self.eta_head * gc7), -WEIGHT_BOUND, WEIGHT_BOUND);

            let gce = clamp_f32(gbe * h[k], -GRAD_CLIP, GRAD_CLIP);
            self.w.we[k] = clamp_f32(self.w.we[k] - (self.eta_head * gce), -WEIGHT_BOUND, WEIGHT_BOUND);
        }
        let gcb = clamp_f32(gbe, -GRAD_CLIP, GRAD_CLIP);
        self.w.be = clamp_f32(self.w.be - (self.eta_head * gcb), -WEIGHT_BOUND, WEIGHT_BOUND);

        self.w.check_finite()?;
        Ok(HeadStepAction::Updated)
    }
}
