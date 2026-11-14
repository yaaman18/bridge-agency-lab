//! The material layer on the OneLife path (S49). Copy of the canonical core/matter.jl (make_world, seed!, step! with no
//! sources and no control); same arithmetic in the same order. The fields are those of the Julia World, with the
//! Julia values (site and table indices are 1-based, as saved), so that the save bytes are those of onelife_encode.

use crate::fdexp::{exp, hypot, jmax, jmin};
use alloc::vec;
use alloc::vec::Vec;

/// MATTER_DEF (W, H, RING are Int; the rest Float64).
#[derive(Clone, Debug, PartialEq)]
pub struct Params {
    pub w: i64,
    pub h: i64,
    pub ring: i64,
    pub mu: f64,
    pub sigma: f64,
    pub adv: f64,
    pub diff: f64,
    pub erosion: f64,
    pub bind: f64,
    pub cap: f64,
    pub turnover: f64,
    pub metab: f64,
    pub theta_exist: f64,
    pub theta_div: f64,
    pub src: f64,
}
pub const MATTER_DEF: Params = Params {
    w: 24,
    h: 24,
    ring: 3,
    mu: 0.35,
    sigma: 0.12,
    adv: 0.6,
    diff: 0.08,
    erosion: 0.002,
    bind: 0.25,
    cap: 1.0,
    turnover: 0.02,
    metab: 0.004,
    theta_exist: 0.2,
    theta_div: 0.8,
    src: 0.06,
};

#[derive(Clone, Debug, PartialEq)]
pub struct Port {
    pub reservoir: f64,
    pub scale: f64,
    pub unit: Vec<u8>,
    pub inflow: f64,
    pub outflow: f64,
}
impl Port {
    pub fn new(reservoir: f64) -> Port {
        Port { reservoir, scale: 1.0, unit: b"mu".to_vec(), inflow: 0.0, outflow: 0.0 }
    }
    pub fn take(&mut self, x: f64) -> f64 {
        let t = jmax(0.0, jmin(x, self.reservoir));
        self.reservoir -= t;
        self.inflow += t;
        t
    }
    pub fn give(&mut self, x: f64) {
        self.reservoir += x;
        self.outflow += x;
    }
}

/// A Julia Matrix{Int}: rows, columns, column-major data.
#[derive(Clone, Debug, PartialEq)]
pub struct IMat {
    pub r: i64,
    pub c: i64,
    pub v: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct World {
    pub p: Params,
    pub a: Vec<f64>,
    pub b: Vec<f64>,
    pub c: Vec<u8>,
    pub k: Vec<(i64, i64, f64)>,
    pub port: Port,
    pub t: i64,
    pub born: i64,
    pub died: i64,
    pub spontaneous: bool,
    pub k_idx: IMat,
    pub k_w: Vec<f64>,
    pub nb4: IMat,
    pub pp: Vec<f64>,
    pub out: Vec<f64>,
    pub scl: Vec<f64>,
    pub pi: Vec<i64>,
    pub pj: Vec<i64>,
    pub pf: Vec<f64>,
}

pub fn kernel(r: i64) -> Vec<(i64, i64, f64)> {
    let mut k = Vec::new();
    let mut s = 0.0f64;
    let rf = r as f64;
    for dy in -r..=r {
        for dx in -r..=r {
            let rr = hypot(dx as f64, dy as f64) / rf;
            if rr == 0.0 || rr > 1.0 {
                continue;
            }
            let w = exp(4.0 - 1.0 / (rr * (1.0 - rr) + 1e-9));
            if w > 1e-6 {
                k.push((dx, dy, w));
                s += w;
            }
        }
    }
    k.into_iter().map(|(dx, dy, w)| (dx, dy, w / s)).collect()
}

/// make_world(; reservoir) with MATTER_DEF and spontaneous = false.
pub fn make_world(reservoir: f64) -> World {
    let p = MATTER_DEF;
    let (wd, ht) = (p.w, p.h);
    let n = (wd * ht) as usize;
    let k = kernel(p.ring);
    let nk = k.len();
    let site = |x: i64, y: i64| y.rem_euclid(ht) * wd + x.rem_euclid(wd) + 1;
    let mut k_idx = vec![0i64; nk * n];
    let mut nb4 = vec![0i64; 4 * n];
    for y in 0..ht {
        for x in 0..wd {
            let i = (y * wd + x) as usize;
            for (m, &(dx, dy, _)) in k.iter().enumerate() {
                k_idx[i * nk + m] = site(x + dx, y + dy);
            }
            for (m, (dx, dy)) in [(1i64, 0i64), (-1, 0), (0, 1), (0, -1)].iter().enumerate() {
                nb4[i * 4 + m] = site(x + dx, y + dy);
            }
        }
    }
    let k_w = k.iter().map(|e| e.2).collect();
    World {
        p,
        a: vec![0.0; n],
        b: vec![0.0; n],
        c: vec![0; n],
        k,
        port: Port::new(reservoir),
        t: 0,
        born: 0,
        died: 0,
        spontaneous: false,
        k_idx: IMat { r: nk as i64, c: n as i64, v: k_idx },
        k_w,
        nb4: IMat { r: 4, c: n as i64, v: nb4 },
        pp: vec![0.0; n],
        out: vec![0.0; n],
        scl: vec![0.0; n],
        pi: vec![0; 4 * n],
        pj: vec![0; 4 * n],
        pf: vec![0.0; 4 * n],
    }
}

/// seed!(w, cx, cy, r): the founder group, 0.6 mu each.
pub fn seed(w: &mut World, cx: i64, cy: i64, r: i64) {
    let wd = w.p.w;
    for y in cy - r..=cy + r {
        for x in cx - r..=cx + r {
            let i = (y * wd + x) as usize;
            w.b[i] = w.port.take(0.6);
            w.c[i] = 1;
        }
    }
}

/// The checks that make step() safe to index (a save that fails them is refused, not repaired).
pub fn shape_ok(w: &World) -> bool {
    let n = w.a.len();
    let nk = w.k_w.len();
    let in_n = |v: &Vec<i64>| v.iter().all(|&j| j >= 1 && j as u64 <= n as u64);
    w.b.len() == n
        && w.c.len() == n
        && w.pp.len() == n
        && w.out.len() == n
        && w.scl.len() == n
        && w.pi.len() == 4 * n
        && w.pj.len() == 4 * n
        && w.pf.len() == 4 * n
        && w.k_idx.r == nk as i64
        && w.k_idx.c == n as i64
        && w.k_idx.v.len() == nk * n
        && in_n(&w.k_idx.v)
        && w.nb4.r == 4
        && w.nb4.c == n as i64
        && w.nb4.v.len() == 4 * n
        && in_n(&w.nb4.v)
}

#[inline]
fn bell(u: f64, mu: f64, s: f64) -> f64 {
    2.0 * exp(-((u - mu) * (u - mu)) / (2.0 * s * s)) - 1.0
}

/// The field at site i (0-based) before the update, as step! computes it.
#[inline]
fn field_u(w: &World, i: usize) -> f64 {
    let nk = w.k_w.len();
    let mut u = 0.0f64;
    for m in 0..nk {
        let j = (w.k_idx.v[i * nk + m] - 1) as usize;
        u += w.k_w[m] * (w.a[j] + w.b[j]);
    }
    u
}

/// Read-only: the exp arguments the next step! would use (for the exp check, Q1).
pub fn exp_args(w: &World) -> Vec<f64> {
    let (mu, s) = (w.p.mu, w.p.sigma);
    (0..w.a.len())
        .map(|i| {
            let u = field_u(w, i);
            -((u - mu) * (u - mu)) / (2.0 * s * s)
        })
        .collect()
}

/// step!(w, ()) with NOCTL. The world must pass shape_ok.
pub fn step(w: &mut World) {
    let n = w.a.len();
    for i in 0..n {
        let u = field_u(w, i);
        w.pp[i] = bell(u, w.p.mu, w.p.sigma);
    }
    for x in w.out.iter_mut() {
        *x = 0.0;
    }
    let mut np = 0usize;
    let (adv, diff) = (w.p.adv, w.p.diff);
    for i in 0..n {
        for m in 0..4 {
            let j = (w.nb4.v[i * 4 + m] - 1) as usize;
            let f = adv * w.a[i] * jmax(0.0, w.pp[j] - w.pp[i]) / 4.0 + diff * jmax(0.0, w.a[i] - w.a[j]) / 4.0;
            if f > 0.0 {
                w.pi[np] = i as i64 + 1;
                w.pj[np] = j as i64 + 1;
                w.pf[np] = f;
                np += 1;
                w.out[i] += f;
            }
        }
    }
    for i in 0..n {
        w.scl[i] = if w.out[i] > w.a[i] { w.a[i] / w.out[i] } else { 1.0 };
    }
    for q in 0..np {
        let i = (w.pi[q] - 1) as usize;
        let j = (w.pj[q] - 1) as usize;
        let g = w.pf[q] * w.scl[i];
        w.a[i] -= g;
        w.a[j] += g;
    }
    for i in 0..n {
        let e = w.a[i] * w.p.erosion;
        w.a[i] -= e;
        w.port.give(e);
    }
    for i in 0..n {
        if w.c[i] == 0 {
            continue;
        }
        let a = 1.0f64;
        let m = jmin(w.b[i], w.p.metab * a);
        w.b[i] -= m;
        w.port.give(m);
        let r = w.b[i] * w.p.turnover;
        w.b[i] -= r;
        w.a[i] += r;
        let ba = a;
        let bb = jmin(w.p.cap - w.b[i], w.p.bind * ba * w.a[i]);
        w.b[i] += bb;
        w.a[i] -= bb;
        if w.b[i] < w.p.theta_exist {
            w.c[i] = 0;
            w.a[i] += w.b[i];
            w.b[i] = 0.0;
            w.died = w.died.wrapping_add(1);
        }
    }
    let order: Vec<usize> = (0..n).filter(|&i| w.c[i] != 0 && w.b[i] >= w.p.theta_div).collect();
    for i in order {
        let mut j: Option<usize> = None;
        for m in 0..4 {
            let c = (w.nb4.v[i * 4 + m] - 1) as usize;
            if w.c[c] != 0 {
                continue;
            }
            if j.map_or(true, |jj| w.a[c] > w.a[jj]) {
                j = Some(c);
            }
        }
        let j = match j {
            None => continue,
            Some(j) => j,
        };
        let half = w.b[i] / 2.0;
        w.b[i] -= half;
        w.b[j] += half;
        w.c[j] = 1;
        w.born = w.born.wrapping_add(1);
    }
    if w.spontaneous {
        for i in 0..n {
            if w.c[i] == 0 && w.a[i] >= w.p.theta_exist * 2.0 {
                let bb = w.a[i] / 2.0;
                w.a[i] -= bb;
                w.b[i] += bb;
                w.c[i] = 1;
                w.born = w.born.wrapping_add(1);
            }
        }
    }
    w.t = w.t.wrapping_add(1);
}
