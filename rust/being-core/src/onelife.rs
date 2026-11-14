//! One life with death as an absorbing state (S49; copy of the canonical core/one_life.jl, S48 r2). The state is the
//! Julia OneLife with the Julia values (1-based indices, Int as i64, Char as its UInt32 bits), so that the save bytes
//! are those of onelife_encode / onelife_save. The circuit here is the path of the OneLife laws only (contrast bin3,
//! idle_first, core_gate, seen_both off, sed_fade per law; explore, fail, memory, orient on; no sil, no y_offer, no
//! rest_off, no body_flag; the gesture is always 0), written apart from circuit.rs (the app's rule is not touched).
//! Same rules, constants and order of operations as core/circuit.jl step!, core/matter.jl step! and
//! core/one_life.jl _live. No fused multiply-add; exp is fdlibm (fdexp.rs).

use crate::fdexp::{floor, jmin};
use crate::matter::{self, IMat, Params, Port, World};
use crate::sha256::sha256;
use alloc::vec;
use alloc::vec::Vec;

const P_SMAX: i64 = 4;
const P_DECAY: i64 = 8;
const P_CAPACITY: f64 = 5.0;
const P_W: i64 = 10;
const P_FRESH: i64 = 20;
const P_KINDS: usize = 4;
const ALPHA: f64 = 0.05;
const FORGET: i64 = 100;
const THETA_B: f64 = 0.1;
const NFEATURES: i64 = 17;

/// Julia Char bits (reinterpret(UInt32, c)) of the unit kinds.
pub const CH_R: u32 = 0x5200_0000;
pub const CH_C: u32 = 0x4300_0000;
pub const CH_M: u32 = 0x4D00_0000;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Law {
    L2,
    L2SF,
}
pub const LAW_L2: &str = "L2 U=0.02 MCOST=0.004 KC=0.002 CONTRAST=bin3 IDLE=true GATE=true SEENBOTH=false SEDFADE=false";
pub const LAW_L2SF: &str = "L2+SF U=0.02 MCOST=0.004 KC=0.002 CONTRAST=bin3 IDLE=true GATE=true SEENBOTH=false SEDFADE=true";
impl Law {
    pub fn id(self) -> [u8; 32] {
        match self {
            Law::L2 => sha256(LAW_L2.as_bytes()),
            Law::L2SF => sha256(LAW_L2SF.as_bytes()),
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            Law::L2 => "L2",
            Law::L2SF => "L2+SF",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Pend {
    pub t: i64,
    pub e: Vec<i64>,
    pub r: Vec<i64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CState {
    pub active: Vec<bool>,
    pub q: Vec<i64>,
    pub sg: Vec<i64>,
    pub h: Vec<i64>,
    pub off: Vec<i64>,
    pub t: i64,
    pub pend: Vec<Pend>,
    pub fresh: Vec<i64>,
    pub prev: Option<Vec<bool>>,
    pub c_on: Option<Vec<f64>>,
    pub c_off: Option<Vec<f64>>,
    pub last_m: Option<Vec<i64>>,
    pub last_c: Option<Vec<i64>>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Circuit {
    pub names: Vec<Vec<u8>>,
    pub kind: Vec<u32>,
    pub feat: Vec<i64>,
    pub theta: Vec<i64>,
    pub patch: Vec<i64>,
    pub edges: Vec<(i64, i64, i64)>,
    pub q0: Vec<i64>,
    pub initial: Vec<bool>,
    pub perm: Vec<i64>,
    pub ins: Vec<Vec<i64>>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct OneLife {
    pub law: Law,
    pub circuit: CState,
    pub b: Circuit,
    pub perm: Vec<i64>,
    pub noise: i64,
    pub w: World,
    pub pool: Vec<f64>,
    pub t: i64,
    pub dead: bool,
    pub death: Option<i64>,
}

/// mulberry32 (core/jsmath.jl Mulberry).
pub struct Mulberry {
    pub s: u32,
}
impl Mulberry {
    pub fn new(seed: i64) -> Mulberry {
        Mulberry { s: seed as u32 }
    }
    pub fn next(&mut self) -> f64 {
        self.s = self.s.wrapping_add(0x6D2B79F5);
        let s = self.s;
        let mut t = (s ^ (s >> 15)).wrapping_mul(s | 1);
        t = (t.wrapping_add((t ^ (t >> 7)).wrapping_mul(t | 61))) ^ t;
        (t ^ (t >> 14)) as f64 / 4294967296.0
    }
    pub fn state_int32(&self) -> i64 {
        self.s as i32 as i64
    }
}

// --- birth (core/one_life.jl onelife_birth; core/circuit.jl newborn(false), init) ---

fn newborn(perm: Vec<i64>) -> Circuit {
    let mut names: Vec<Vec<u8>> = Vec::new();
    let mut kind = Vec::new();
    let mut feat = Vec::new();
    let mut theta = Vec::new();
    let mut patch = Vec::new();
    let nr = 8i64;
    for i in 1..=nr {
        let mut nm = vec![b'r'];
        nm.push(b'0' + i as u8);
        names.push(nm);
        kind.push(CH_R);
        feat.push(i);
        theta.push(0);
        patch.push(0);
    }
    for nm in [&b"c1"[..], &b"c2"[..]] {
        names.push(nm.to_vec());
        kind.push(CH_C);
        feat.push(0);
        theta.push(1);
        patch.push(0);
    }
    for (i, nm) in [&b"m1"[..], &b"m2"[..]].iter().enumerate() {
        names.push(nm.to_vec());
        kind.push(CH_M);
        feat.push(0);
        theta.push(2);
        patch.push(i as i64 + 1);
    }
    let id = |n: &[u8], names: &Vec<Vec<u8>>| names.iter().position(|x| x.as_slice() == n).unwrap() as i64 + 1;
    let mut edges = Vec::new();
    let mut q0 = Vec::new();
    for (a, c) in [(&b"c1"[..], &b"c1"[..]), (b"c2", b"c2"), (b"c1", b"c2"), (b"c2", b"c1")] {
        edges.push((id(a, &names), id(c, &names), 1));
        q0.push(4);
    }
    for (c, m) in [(&b"c1"[..], &b"m1"[..]), (b"c2", b"m2")] {
        edges.push((id(c, &names), id(m, &names), 1));
        q0.push(0);
        for i in 1..=nr {
            let rn = [b'r', b'0' + i as u8];
            edges.push((id(&rn, &names), id(m, &names), 1));
            q0.push(0);
        }
    }
    let initial = names.iter().map(|n| n[0] == b'c').collect();
    let mut ins = vec![Vec::new(); names.len()];
    for (k, e) in edges.iter().enumerate() {
        ins[(e.1 - 1) as usize].push(k as i64 + 1);
    }
    Circuit { names, kind, feat, theta, patch, edges, q0, initial, perm, ins }
}

fn init(b: &Circuit) -> CState {
    let ne = b.q0.len();
    CState {
        active: b.initial.clone(),
        q: b.q0.clone(),
        sg: vec![0; ne],
        h: vec![0; ne],
        off: vec![0; b.names.len()],
        t: 0,
        pend: Vec::new(),
        fresh: vec![5; P_KINDS],
        prev: None,
        c_on: None,
        c_off: None,
        last_m: None,
        last_c: None,
    }
}

/// onelife_birth(seed, law). For the checks only (S49: the birth of a life is the user's).
pub fn birth(seed: i64, law: Law) -> OneLife {
    let mut w = matter::make_world(300.0);
    matter::seed(&mut w, 12, 12, 1);
    let perm: Vec<i64> = (1..=NFEATURES).collect();
    let b = newborn(perm.clone());
    let circuit = init(&b);
    let noise = Mulberry::new(seed);
    OneLife { law, circuit, b, perm, noise: noise.state_int32(), w, pool: vec![0.0, 0.0], t: 0, dead: false, death: None }
}

// --- the circuit step of the OneLife path ---

fn feature(f: i64, ys: &[f64; 4], t: i64, noise: &mut Mulberry) -> bool {
    match f {
        1 => ys[0] >= 3.0,
        2 => ys[1] >= 3.0,
        3 => ys[0] == 0.0,
        4 => ys[1] == 0.0,
        5 => noise.next() < 0.5,
        6 => t % 3 == 0,
        7 => ys[0] > ys[1],
        8 => ys[1] > ys[0],
        9 => ys[2] > 0.0,
        10 => ys[3] > 0.0,
        11 => ys[3] == 0.0,
        12 => ys[0] >= 1.0,
        13 => ys[1] >= 1.0,
        14 => ys[0] >= 4.0,
        15 => ys[1] >= 4.0,
        16 => ys[0] >= ys[1] + 2.0,
        _ => ys[1] >= ys[0] + 2.0,
    }
}

fn allocate(offer: [f64; 2]) -> [f64; 2] {
    let mut d = [0.0, 0.0];
    let mut left = P_CAPACITY;
    let mut idx: Vec<usize> = [0usize, 1].iter().copied().filter(|&i| offer[i] > 0.0).collect();
    if idx.len() == 2 && offer[1] > offer[0] {
        idx.swap(0, 1);
    }
    for i in idx {
        d[i] = jmin(offer[i], left);
        left -= d[i];
    }
    d
}

/// core/circuit.jl step!(st, b, y; noise, contrast = :bin3, idle_first = true, core_gate = true, seen_both = false,
/// sed_fade) with the other options at their defaults and y[3] = 0. Returns (out.acting as 0-based units, out.d).
fn circuit_step(st: &mut CState, b: &Circuit, y: [f64; 3], noise: &mut Mulberry, sed_fade: bool) -> (Vec<usize>, [f64; 2]) {
    let n = b.names.len();
    let ne = b.edges.len();
    let old = st.active.clone();
    let ys = [y[0], y[1], y[2], if st.pend.is_empty() { 0.0 } else { 1.0 }];
    let now = st.t.wrapping_add(1);
    let prev = st.prev.clone().unwrap_or_else(|| old.clone());
    let ea: Vec<usize> = b.edges.iter().map(|e| (e.0 - 1) as usize).collect();
    let ec: Vec<usize> = b.edges.iter().map(|e| (e.1 - 1) as usize).collect();
    let ew: Vec<i64> = b.edges.iter().map(|e| e.2).collect();
    let ins: Vec<Vec<usize>> = b.ins.iter().map(|v| v.iter().map(|&k| (k - 1) as usize).collect()).collect();
    let is_r = |u: usize| b.kind[u] == CH_R;
    let is_m = |u: usize| b.kind[u] == CH_M;
    let is_c = |u: usize| b.kind[u] == CH_C;
    let onset: Vec<bool> = (0..n).map(|u| is_r(u) && old[u] && !prev[u]).collect();
    let stale: Vec<bool> = (0..n)
        .map(|u| {
            let idle = is_m(u)
                && b.patch[u] <= 2
                && st.last_m.as_ref().map_or(false, |lm| now.wrapping_sub(lm[u]) > FORGET);
            !is_r(u) && !ins[u].is_empty() && (idle || ins[u].iter().all(|&k| st.q[k] == 0 && st.sg[k] == 0))
        })
        .collect();
    let mut total = vec![0i64; n];
    let mut conf = vec![0i64; n];
    let mut habit = vec![0i64; n];
    let mut drove = vec![false; ne];
    for k in 0..ne {
        let (a, c, w) = (ea[k], ec[k], ew[k]);
        if (st.q[k] >= 1 || st.sg[k] >= 1 || stale[c] || (onset[a] && st.q[k] == 0 && st.sg[k] == 0 && st.h[k] == 0))
            && old[a]
        {
            total[c] = total[c].wrapping_add(w);
            if st.q[k] >= 1 {
                conf[c] = conf[c].wrapping_add(w);
            } else if st.sg[k] >= 1 {
                habit[c] = habit[c].wrapping_add(w);
            }
            drove[k] = true;
        }
    }
    let mut nw = vec![false; n];
    for u in 0..n {
        nw[u] = if is_r(u) {
            if b.feat[u] == -1 {
                false
            } else {
                feature(b.perm[(b.feat[u] - 1) as usize], &ys, now, noise)
            }
        } else {
            total[u] >= b.theta[u]
        };
    }
    // core_gate
    for u in 0..n {
        if !(is_m(u) && (b.patch[u] <= 2 || b.patch[u] == 4) && nw[u]) {
            continue;
        }
        if !ins[u].iter().any(|&k| drove[k] && is_c(ea[k])) {
            nw[u] = false;
        }
    }
    let motors: Vec<usize> = (0..n).filter(|&u| is_m(u)).collect();
    let cand: Vec<usize> = motors.iter().copied().filter(|&m| nw[m] && (b.patch[m] <= 2 || b.patch[m] == 4)).collect();
    if st.last_m.is_none() {
        st.last_m = Some(vec![0; n]);
    }
    if cand.len() > 1 {
        let key = |m: usize| {
            conf[m].wrapping_mul(1_000_000).wrapping_add(habit[m].wrapping_mul(1_000)).wrapping_add(total[m])
        };
        let rank = |cs: &[usize]| -> usize {
            let best = cs.iter().map(|&m| key(m)).max().unwrap();
            let tied: Vec<usize> = cs.iter().copied().filter(|&m| key(m) == best).collect();
            let pv: Vec<usize> = tied.iter().copied().filter(|&m| old[m]).collect();
            let pool = if pv.is_empty() { &tied } else { &pv };
            let mut bi = 0;
            for i in 1..pool.len() {
                if b.patch[pool[i]] < b.patch[pool[bi]] {
                    bi = i;
                }
            }
            pool[bi]
        };
        let mut win = rank(&cand);
        let lm = st.last_m.as_ref().unwrap();
        let idl: Vec<usize> = cand.iter().copied().filter(|&m| now.wrapping_sub(lm[m]) > FORGET).collect();
        if !idl.is_empty() {
            win = rank(&idl);
        }
        for &m in &cand {
            if m != win {
                nw[m] = false;
            }
        }
    }
    let acting: Vec<usize> = motors.iter().copied().filter(|&m| nw[m]).collect();
    let on_patch: Vec<usize> = acting.iter().copied().filter(|&m| b.patch[m] <= 2).collect();
    let call = acting.iter().copied().find(|&m| b.patch[m] == 3);
    let mut offer = [0.0, 0.0];
    for &m in &on_patch {
        let p = (b.patch[m] - 1) as usize;
        offer[p] = y[p];
    }
    let d = allocate(offer);
    let answered: Vec<(usize, bool)> = on_patch.iter().map(|&m| (m, d[(b.patch[m] - 1) as usize] > 0.0)).collect();
    let ans_of = |u: usize| answered.iter().find(|x| x.0 == u).map(|x| x.1);
    let gate = d[0] + d[1] > 0.0 && answered.iter().all(|x| x.1);
    let ok = |u: usize| !is_m(u) || ans_of(u) == Some(true);
    let mut confirmed: Vec<bool> = (0..ne).map(|k| drove[k] && nw[ec[k]] && gate && ok(ea[k]) && ok(ec[k])).collect();
    let rm = |k: usize| is_r(ea[k]) && is_m(ec[k]) && b.patch[ec[k]] <= 2;
    // STATS (bin3)
    if st.c_on.is_none() {
        st.c_on = Some(vec![f64::NAN; ne]);
        st.c_off = Some(vec![f64::NAN; ne]);
    }
    for &m in &on_patch {
        let dm = d[(b.patch[m] - 1) as usize];
        for k in 0..ne {
            let (a, c) = (ea[k], ec[k]);
            if c != m || !is_r(a) {
                continue;
            }
            let arr = if old[a] { st.c_on.as_mut().unwrap() } else { st.c_off.as_mut().unwrap() };
            let v = if dm > 0.0 { 1.0 } else { 0.0 };
            arr[k] = if arr[k].is_nan() { v } else { arr[k] + ALPHA * (v - arr[k]) };
        }
    }
    // L2 (bin3): last acts, and the statistics forgotten FORGET steps after the last act
    for &m in &motors {
        if b.patch[m] == 4 && acting.contains(&m) {
            st.last_m.as_mut().unwrap()[m] = now;
        }
        if b.patch[m] > 2 {
            continue;
        }
        if on_patch.contains(&m) {
            st.last_m.as_mut().unwrap()[m] = now;
        } else if now.wrapping_sub(st.last_m.as_ref().unwrap()[m]) == FORGET {
            for k in 0..ne {
                if ec[k] == m && is_r(ea[k]) {
                    st.c_on.as_mut().unwrap()[k] = f64::NAN;
                    st.c_off.as_mut().unwrap()[k] = f64::NAN;
                }
            }
        }
    }
    let passes = |k: usize, st: &CState| -> bool {
        if !rm(k) {
            return true;
        }
        let cc = st.c_on.as_ref().unwrap()[k] - st.c_off.as_ref().unwrap()[k];
        if cc.is_nan() {
            true
        } else {
            cc > THETA_B
        }
    };
    for k in 0..ne {
        if confirmed[k] && !passes(k, st) {
            confirmed[k] = false;
        }
    }
    let grow = |k: usize, st: &mut CState| {
        if !passes(k, st) {
            return;
        }
        if st.q[k] < P_SMAX {
            st.q[k] = P_SMAX.min(st.q[k].wrapping_add(1).wrapping_add(st.sg[k]));
            if st.q[k] == P_SMAX {
                st.sg[k] = P_SMAX.min(st.sg[k].wrapping_add(1));
            }
        }
    };
    let weaken = |k: usize, st: &mut CState| {
        if st.q[k] == 0 && st.sg[k] == 0 {
            st.h[k] = P_SMAX.min(st.h[k].wrapping_add(1));
        }
        if st.q[k] > 0 {
            st.q[k] = st.q[k].wrapping_sub(1).max(0);
        } else {
            st.sg[k] = st.sg[k].wrapping_sub(1).max(0);
        }
    };
    for k in 0..ne {
        if confirmed[k] {
            grow(k, st);
        }
    }
    for &m in &on_patch {
        if ans_of(m) == Some(true) {
            continue;
        }
        for k in 0..ne {
            if ec[k] == m && is_r(ea[k]) && drove[k] && !confirmed[k] {
                weaken(k, st);
            }
        }
    }
    // the partner's answer: the gesture is 0 on this path, so no pending call is answered
    let pend = core::mem::take(&mut st.pend);
    let mut keep = Vec::new();
    for p in pend {
        if now.wrapping_sub(p.t) >= P_W {
            for &k in &p.r {
                let k = (k - 1) as usize;
                if !confirmed[k] {
                    weaken(k, st);
                }
            }
        } else {
            keep.push(p);
        }
    }
    st.pend = keep;
    if let Some(cm) = call {
        let okc = |u: usize| !is_m(u) || u == cm;
        let e = (0..ne).filter(|&k| drove[k] && nw[ec[k]] && okc(ea[k]) && okc(ec[k])).map(|k| k as i64 + 1).collect();
        let r = (0..ne).filter(|&k| ec[k] == cm && is_r(ea[k]) && drove[k]).map(|k| k as i64 + 1).collect();
        st.pend.push(Pend { t: now, e, r });
    }
    let waiting = [0.0, 0.0, 0.0, if st.pend.is_empty() { 0.0 } else { 1.0 }];
    for u in 0..n {
        if is_r(u) && 10 <= b.feat[u] && b.feat[u] <= 11 {
            nw[u] = feature(b.perm[(b.feat[u] - 1) as usize], &waiting, now, noise);
        }
    }
    if sed_fade {
        if st.last_c.is_none() {
            st.last_c = Some(vec![0; ne]);
        }
        for k in 0..ne {
            if confirmed[k] {
                st.last_c.as_mut().unwrap()[k] = now;
            } else {
                let a = now.wrapping_sub(st.last_c.as_ref().unwrap()[k]);
                if a >= FORGET && a % FORGET == 0 {
                    st.sg[k] = st.sg[k].wrapping_sub(1).max(0);
                }
            }
        }
    }
    if now % P_FRESH == 0 {
        for f in st.fresh.iter_mut() {
            *f = 5i64.min(f.wrapping_add(1));
        }
    }
    if now % P_DECAY == 0 {
        for k in 0..ne {
            if !confirmed[k] && !(b.patch[ec[k]] == 4 && b.q0[k] > 0) {
                st.q[k] = st.q[k].wrapping_sub(1).max(0);
            }
        }
    }
    for u in 0..n {
        if !is_r(u) {
            continue;
        }
        st.off[u] = if nw[u] { 0 } else { st.off[u].wrapping_add(1) };
        if st.off[u] > 0 && st.off[u] % P_DECAY == 0 {
            for k in 0..ne {
                if ea[k] == u && st.h[k] > 0 {
                    st.h[k] -= 1;
                }
            }
        }
    }
    st.prev = Some(old);
    st.active = nw;
    st.t = now;
    (acting, d)
}

// --- the OneLife step (core/one_life.jl) ---

fn empty_body(s: &OneLife) -> bool {
    s.w.c.iter().all(|&c| c == 0)
}
fn detect(s: &OneLife) -> OneLife {
    let mut c = s.clone();
    c.dead = true;
    c.death = Some(c.t);
    c
}
fn drive_ok(g: [i64; 2]) -> bool {
    g.iter().all(|&x| (0..=5).contains(&x))
}

/// _live: the living step of body_org_run (cond "ORG"), on a copy of the input.
fn live(s: &OneLife, g: [i64; 2], u: f64, mcost: f64, kc: f64, sed_fade: bool) -> OneLife {
    let mut c = s.clone();
    let mut noise = Mulberry::new(c.noise);
    let y: Vec<f64> = c.pool.iter().map(|&r| jmin(5.0, floor(r / u + 1e-9))).collect();
    let body: Vec<usize> = (0..c.w.c.len()).filter(|&i| c.w.c[i] != 0).collect();
    let nb = body.len() as f64;
    let (out_acting, d) = circuit_step(&mut c.circuit, &c.b, [y[0], y[1], 0.0], &mut noise, sed_fade);
    let acting: Vec<i64> = out_acting.iter().map(|&m| c.b.patch[m]).filter(|&p| p <= 2).collect();
    let nk = (0..c.circuit.q.len()).filter(|&k| c.circuit.q[k] >= 1 || c.circuit.sg[k] >= 1).count();
    let w = &mut c.w;
    let pool = &mut c.pool;
    let cost = kc * nk as f64;
    let mut paid = 0.0f64;
    for &i in &body {
        let m = jmin(w.b[i], cost / nb);
        w.b[i] -= m;
        paid += m;
    }
    w.port.give(paid);
    if !acting.is_empty() {
        for k in 0..2 {
            if d[k] > 0.0 {
                let take = jmin(pool[k], d[k] * u);
                pool[k] -= take;
                for &i in &body {
                    w.a[i] += take / nb;
                }
            }
        }
        let cost = mcost * acting.len() as f64;
        let mut paid = 0.0f64;
        for &i in &body {
            let m = jmin(w.b[i], cost / nb);
            w.b[i] -= m;
            paid += m;
        }
        w.port.give(paid);
    }
    for k in 0..2 {
        pool[k] += w.port.take(g[k] as f64 * u);
        let over = pool[k] - 50.0 * u;
        if over > 0.0 {
            pool[k] -= over;
            w.port.give(over);
        }
    }
    matter::step(w);
    c.noise = noise.state_int32();
    c.t = c.t.wrapping_add(1);
    c.dead = false;
    c.death = None;
    c
}

/// onelife_step for the law L2: (state, error).
pub fn step_l2(s: &OneLife, g: [i64; 2]) -> (OneLife, bool) {
    if s.dead {
        return (s.clone(), false);
    }
    if empty_body(s) {
        return (detect(s), false);
    }
    if !drive_ok(g) {
        return (s.clone(), true);
    }
    (live(s, g, 0.02, 0.004, 0.002, false), false)
}
/// onelife_step for the law L2+SF: (state, error).
pub fn step_l2sf(s: &OneLife, g: [i64; 2]) -> (OneLife, bool) {
    if s.dead {
        return (s.clone(), false);
    }
    if empty_body(s) {
        return (detect(s), false);
    }
    if !drive_ok(g) {
        return (s.clone(), true);
    }
    (live(s, g, 0.02, 0.004, 0.002, true), false)
}
/// The step of the state's own law.
pub fn step(s: &OneLife, g: [i64; 2]) -> (OneLife, bool) {
    match s.law {
        Law::L2 => step_l2(s, g),
        Law::L2SF => step_l2sf(s, g),
    }
}

// --- serialization (onelife_encode / onelife_decode) ---

struct Enc(Vec<u8>);
impl Enc {
    fn i(&mut self, x: i64) {
        self.0.extend_from_slice(&x.to_le_bytes());
    }
    fn f(&mut self, x: f64) {
        self.0.extend_from_slice(&x.to_bits().to_le_bytes());
    }
    fn bo(&mut self, x: bool) {
        self.0.push(x as u8);
    }
    fn s(&mut self, x: &[u8]) {
        self.i(x.len() as i64);
        self.0.extend_from_slice(x);
    }
    fn vi(&mut self, v: &[i64]) {
        self.i(v.len() as i64);
        for &x in v {
            self.i(x);
        }
    }
    fn vf(&mut self, v: &[f64]) {
        self.i(v.len() as i64);
        for &x in v {
            self.f(x);
        }
    }
    fn vb(&mut self, v: &[bool]) {
        self.i(v.len() as i64);
        for &x in v {
            self.bo(x);
        }
    }
    fn mat(&mut self, m: &IMat) {
        self.i(m.r);
        self.i(m.c);
        for &x in &m.v {
            self.i(x);
        }
    }
    fn tag<T>(&mut self, o: &Option<T>, f: impl FnOnce(&mut Enc, &T)) {
        match o {
            None => self.0.push(0),
            Some(v) => {
                self.0.push(1);
                f(self, v)
            }
        }
    }
}

/// onelife_encode(s).
pub fn encode(s: &OneLife) -> Vec<u8> {
    let mut e = Enc(Vec::new());
    let c = &s.circuit;
    e.vb(&c.active);
    e.vi(&c.q);
    e.vi(&c.sg);
    e.vi(&c.h);
    e.vi(&c.off);
    e.i(c.t);
    e.i(c.pend.len() as i64);
    for p in &c.pend {
        e.i(p.t);
        e.vi(&p.e);
        e.vi(&p.r);
    }
    e.vi(&c.fresh);
    e.tag(&c.prev, |e, v| e.vb(v));
    e.tag(&c.c_on, |e, v| e.vf(v));
    e.tag(&c.c_off, |e, v| e.vf(v));
    e.tag(&c.last_m, |e, v| e.vi(v));
    e.tag(&c.last_c, |e, v| e.vi(v));
    let b = &s.b;
    e.i(b.names.len() as i64);
    for nm in &b.names {
        e.s(nm);
    }
    e.i(b.kind.len() as i64);
    for &k in &b.kind {
        e.0.extend_from_slice(&k.to_le_bytes());
    }
    e.vi(&b.feat);
    e.vi(&b.theta);
    e.vi(&b.patch);
    e.i(b.edges.len() as i64);
    for &(a, c, w) in &b.edges {
        e.i(a);
        e.i(c);
        e.i(w);
    }
    e.vi(&b.q0);
    e.vb(&b.initial);
    e.vi(&b.perm);
    e.i(b.ins.len() as i64);
    for v in &b.ins {
        e.vi(v);
    }
    e.vi(&s.perm);
    e.i(s.noise);
    let w = &s.w;
    let p = &w.p;
    e.i(p.w);
    e.i(p.h);
    e.i(p.ring);
    for x in [p.mu, p.sigma, p.adv, p.diff, p.erosion, p.bind, p.cap, p.turnover, p.metab, p.theta_exist, p.theta_div, p.src] {
        e.f(x);
    }
    e.vf(&w.a);
    e.vf(&w.b);
    e.s(&w.c);
    e.i(w.k.len() as i64);
    for &(dx, dy, kw) in &w.k {
        e.i(dx);
        e.i(dy);
        e.f(kw);
    }
    e.f(w.port.reservoir);
    e.f(w.port.scale);
    e.s(&w.port.unit);
    e.f(w.port.inflow);
    e.f(w.port.outflow);
    e.i(w.t);
    e.i(w.born);
    e.i(w.died);
    e.bo(w.spontaneous);
    e.mat(&w.k_idx);
    e.vf(&w.k_w);
    e.mat(&w.nb4);
    e.vf(&w.pp);
    e.vf(&w.out);
    e.vf(&w.scl);
    e.vi(&w.pi);
    e.vi(&w.pj);
    e.vf(&w.pf);
    e.vf(&s.pool);
    e.i(s.t);
    e.bo(s.dead);
    e.tag(&s.death, |e, &v| e.i(v));
    e.0
}

/// Reading errors (a save is refused, never repaired).
pub type Err = &'static str;

struct Dec<'a> {
    b: &'a [u8],
    p: usize,
}
impl<'a> Dec<'a> {
    fn avail(&self) -> usize {
        self.b.len() - self.p
    }
    fn take(&mut self, n: usize) -> Result<&'a [u8], Err> {
        if n > self.avail() {
            return Err("unexpected end");
        }
        let s = &self.b[self.p..self.p + n];
        self.p += n;
        Ok(s)
    }
    fn i(&mut self) -> Result<i64, Err> {
        Ok(i64::from_le_bytes(self.take(8)?.try_into().unwrap()))
    }
    fn f(&mut self) -> Result<f64, Err> {
        Ok(f64::from_bits(u64::from_le_bytes(self.take(8)?.try_into().unwrap())))
    }
    fn u8(&mut self) -> Result<u8, Err> {
        Ok(self.take(1)?[0])
    }
    fn u32(&mut self) -> Result<u32, Err> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    fn bo(&mut self) -> Result<bool, Err> {
        let v = self.u8()?;
        if v > 1 {
            return Err("bad Bool");
        }
        Ok(v == 1)
    }
    /// _declen: 0 <= n <= bytesavailable
    fn len(&mut self) -> Result<usize, Err> {
        let n = self.i()?;
        if n < 0 || n as u64 > self.avail() as u64 {
            return Err("bad length");
        }
        Ok(n as usize)
    }
    fn blen(&mut self, size: usize) -> Result<usize, Err> {
        let n = self.len()?;
        if n * size > self.avail() {
            return Err("bad length");
        }
        Ok(n)
    }
    fn s(&mut self) -> Result<Vec<u8>, Err> {
        let n = self.len()?;
        Ok(self.take(n)?.to_vec())
    }
    fn vi(&mut self) -> Result<Vec<i64>, Err> {
        let n = self.blen(8)?;
        (0..n).map(|_| self.i()).collect()
    }
    fn vf(&mut self) -> Result<Vec<f64>, Err> {
        let n = self.blen(8)?;
        (0..n).map(|_| self.f()).collect()
    }
    fn vb(&mut self) -> Result<Vec<bool>, Err> {
        let n = self.len()?;
        (0..n).map(|_| self.bo()).collect()
    }
    fn mat(&mut self) -> Result<IMat, Err> {
        let r = self.i()?;
        let c = self.i()?;
        if r < 0 || c < 0 {
            return Err("bad size");
        }
        let cells = (r as u64).checked_mul(c as u64).and_then(|x| x.checked_mul(8)).ok_or("bad size")?;
        if cells > self.avail() as u64 {
            return Err("bad size");
        }
        let v = (0..(cells / 8)).map(|_| self.i()).collect::<Result<Vec<i64>, Err>>()?;
        Ok(IMat { r, c, v })
    }
    fn tag(&mut self) -> Result<bool, Err> {
        let t = self.u8()?;
        if t > 1 {
            return Err("bad tag");
        }
        Ok(t == 1)
    }
}

fn decode_body(law: Law, bytes: &[u8]) -> Result<OneLife, Err> {
    let mut d = Dec { b: bytes, p: 0 };
    let active = d.vb()?;
    let q = d.vi()?;
    let sg = d.vi()?;
    let h = d.vi()?;
    let off = d.vi()?;
    let ct = d.i()?;
    let np = d.len()?;
    let mut pend = Vec::new();
    for _ in 0..np {
        let t = d.i()?;
        let e = d.vi()?;
        let r = d.vi()?;
        pend.push(Pend { t, e, r });
    }
    let fresh = d.vi()?;
    let prev = if d.tag()? { Some(d.vb()?) } else { None };
    let c_on = if d.tag()? { Some(d.vf()?) } else { None };
    let c_off = if d.tag()? { Some(d.vf()?) } else { None };
    let last_m = if d.tag()? { Some(d.vi()?) } else { None };
    let last_c = if d.tag()? { Some(d.vi()?) } else { None };
    let circuit = CState { active, q, sg, h, off, t: ct, pend, fresh, prev, c_on, c_off, last_m, last_c };
    let nn = d.len()?;
    let names = (0..nn).map(|_| d.s()).collect::<Result<Vec<_>, Err>>()?;
    let nkind = d.len()?;
    let kind = (0..nkind).map(|_| d.u32()).collect::<Result<Vec<_>, Err>>()?;
    let feat = d.vi()?;
    let theta = d.vi()?;
    let patch = d.vi()?;
    let ned = d.len()?;
    let mut edges = Vec::new();
    for _ in 0..ned {
        let a = d.i()?;
        let c = d.i()?;
        let w = d.i()?;
        edges.push((a, c, w));
    }
    let q0 = d.vi()?;
    let initial = d.vb()?;
    let bperm = d.vi()?;
    let nins = d.len()?;
    let ins = (0..nins).map(|_| d.vi()).collect::<Result<Vec<_>, Err>>()?;
    let b = Circuit { names, kind, feat, theta, patch, edges, q0, initial, perm: bperm, ins };
    let perm = d.vi()?;
    let noise = d.i()?;
    let (pw, ph, pr) = (d.i()?, d.i()?, d.i()?);
    let mut pf = [0.0f64; 12];
    for x in pf.iter_mut() {
        *x = d.f()?;
    }
    let p = Params {
        w: pw,
        h: ph,
        ring: pr,
        mu: pf[0],
        sigma: pf[1],
        adv: pf[2],
        diff: pf[3],
        erosion: pf[4],
        bind: pf[5],
        cap: pf[6],
        turnover: pf[7],
        metab: pf[8],
        theta_exist: pf[9],
        theta_div: pf[10],
        src: pf[11],
    };
    let a = d.vf()?;
    let bb = d.vf()?;
    let nc = d.blen(1)?;
    let cc = d.take(nc)?.to_vec();
    let nkk = d.len()?;
    let mut k = Vec::new();
    for _ in 0..nkk {
        let dx = d.i()?;
        let dy = d.i()?;
        let kw = d.f()?;
        k.push((dx, dy, kw));
    }
    let port = Port { reservoir: d.f()?, scale: d.f()?, unit: d.s()?, inflow: d.f()?, outflow: d.f()? };
    let wt = d.i()?;
    let born = d.i()?;
    let died = d.i()?;
    let spontaneous = d.bo()?;
    let k_idx = d.mat()?;
    let k_w = d.vf()?;
    let nb4 = d.mat()?;
    let pp = d.vf()?;
    let out = d.vf()?;
    let scl = d.vf()?;
    let pi = d.vi()?;
    let pj = d.vi()?;
    let pfv = d.vf()?;
    let w = World {
        p,
        a,
        b: bb,
        c: cc,
        k,
        port,
        t: wt,
        born,
        died,
        spontaneous,
        k_idx,
        k_w,
        nb4,
        pp,
        out,
        scl,
        pi,
        pj,
        pf: pfv,
    };
    let pool = d.vf()?;
    let t = d.i()?;
    let dead = d.bo()?;
    let death = if d.tag()? { Some(d.i()?) } else { None };
    if d.avail() != 0 {
        return Err("trailing bytes");
    }
    let s = OneLife { law, circuit, b, perm, noise, w, pool, t, dead, death };
    if !shape_ok(&s) {
        return Err("state shape");
    }
    Ok(s)
}

/// The checks that make step() safe to index; stricter than the Julia decoder, which leaves such errors to the step.
pub fn shape_ok(s: &OneLife) -> bool {
    let b = &s.b;
    let c = &s.circuit;
    let n = b.names.len();
    let ne = b.edges.len();
    let unit_ok = |x: i64| x >= 1 && x as u64 <= n as u64;
    let edge_ok = |x: i64| x >= 1 && x as u64 <= ne as u64;
    let per_unit = b.kind.len() == n && b.feat.len() == n && b.theta.len() == n && b.patch.len() == n && b.ins.len() == n;
    let per_edge = b.q0.len() == ne && b.edges.iter().all(|e| unit_ok(e.0) && unit_ok(e.1));
    let ins_ok = b.ins.iter().all(|v| v.iter().all(|&k| edge_ok(k)));
    let recep_ok = (0..n).all(|u| {
        b.kind.get(u) != Some(&CH_R)
            || b.feat[u] == -1
            || (b.feat[u] >= 1
                && b.feat[u] as u64 <= b.perm.len() as u64
                && (1..=NFEATURES).contains(&b.perm[(b.feat[u] - 1) as usize]))
    });
    let motor_ok = (0..n).all(|u| b.kind.get(u) != Some(&CH_M) || b.patch[u] >= 1);
    let stats_ok = match (&c.c_on, &c.c_off) {
        (None, None) => true,
        (Some(x), Some(y)) => x.len() == ne && y.len() == ne,
        _ => false,
    };
    let cs_ok = c.active.len() == n
        && c.q.len() == ne
        && c.sg.len() == ne
        && c.h.len() == ne
        && c.off.len() == n
        && c.prev.as_ref().map_or(true, |v| v.len() == n)
        && c.last_m.as_ref().map_or(true, |v| v.len() == n)
        && c.last_c.as_ref().map_or(true, |v| v.len() == ne)
        && c.pend.iter().all(|p| p.e.iter().all(|&k| edge_ok(k)) && p.r.iter().all(|&k| edge_ok(k)));
    per_unit && per_edge && ins_ok && recep_ok && motor_ok && stats_ok && cs_ok && s.pool.len() == 2 && matter::shape_ok(&s.w)
}

// --- save / load (onelife_save, onelife_load_L2 / onelife_load_L2SF) ---

pub const ONELIFE_FORMAT: u32 = 1;

/// onelife_save(s): "OLIF", version, law identity, body length, body, SHA-256 of everything before it.
pub fn save(s: &OneLife) -> Vec<u8> {
    let body = encode(s);
    let mut head = Vec::with_capacity(body.len() + 80);
    head.extend_from_slice(b"OLIF");
    head.extend_from_slice(&ONELIFE_FORMAT.to_le_bytes());
    head.extend_from_slice(&s.law.id());
    head.extend_from_slice(&(body.len() as i64).to_le_bytes());
    head.extend_from_slice(&body);
    let h = sha256(&head);
    head.extend_from_slice(&h);
    head
}

/// _load with the law taken from the save's law identity (L2 or L2+SF); same checks in the same order as Julia.
pub fn load(bytes: &[u8]) -> Result<OneLife, Err> {
    load_with(bytes, None)
}
/// onelife_load_L2 / onelife_load_L2SF: the save must be of the given law.
pub fn load_as(law: Law, bytes: &[u8]) -> Result<OneLife, Err> {
    load_with(bytes, Some(law))
}
fn load_with(bytes: &[u8], want: Option<Law>) -> Result<OneLife, Err> {
    let n = bytes.len();
    if n < 80 {
        return Err("onelife_load: too short");
    }
    if sha256(&bytes[..n - 32]) != bytes[n - 32..] {
        return Err("onelife_load: check value mismatch");
    }
    if &bytes[0..4] != b"OLIF" {
        return Err("onelife_load: not a OneLife save");
    }
    if u32::from_le_bytes(bytes[4..8].try_into().unwrap()) != ONELIFE_FORMAT {
        return Err("onelife_load: format version");
    }
    let id = &bytes[8..40];
    let law = if id == Law::L2.id() {
        Law::L2
    } else if id == Law::L2SF.id() {
        Law::L2SF
    } else {
        return Err("onelife_load: another law");
    };
    if want.map_or(false, |w| w != law) {
        return Err("onelife_load: another law");
    }
    if i64::from_le_bytes(bytes[40..48].try_into().unwrap()) as i128 != (n - 80) as i128 {
        return Err("onelife_load: body length");
    }
    decode_body(law, &bytes[48..n - 32])
}

// --- the run file of onelife-run (S49 §2) ---

pub const RUN_MAGIC: &[u8; 8] = b"ONELIFE1";
pub const RUN_VERSION: u32 = 1;
pub const RUN_MAX_L: u64 = 16_777_216;

/// The run file's bytes: header (magic, version, reserved, n, L), payload, SHA-256 of all before it.
pub fn run_encode(n: u64, payload: &[u8]) -> Vec<u8> {
    let mut v = Vec::with_capacity(64 + payload.len());
    v.extend_from_slice(RUN_MAGIC);
    v.extend_from_slice(&RUN_VERSION.to_le_bytes());
    v.extend_from_slice(&[0u8; 4]);
    v.extend_from_slice(&n.to_le_bytes());
    v.extend_from_slice(&(payload.len() as u64).to_le_bytes());
    v.extend_from_slice(payload);
    let h = sha256(&v);
    v.extend_from_slice(&h);
    v
}

/// Reads a run file: (n, payload, state). Every mismatch is an error.
pub fn run_decode(bytes: &[u8]) -> Result<(u64, Vec<u8>, OneLife), Err> {
    if bytes.len() < 32 {
        return Err("run file: too short");
    }
    if &bytes[0..8] != RUN_MAGIC {
        return Err("run file: not a run file");
    }
    if u32::from_le_bytes(bytes[8..12].try_into().unwrap()) != RUN_VERSION {
        return Err("run file: format version");
    }
    if bytes[12..16] != [0u8; 4] {
        return Err("run file: reserved bytes");
    }
    let n = u64::from_le_bytes(bytes[16..24].try_into().unwrap());
    let l = u64::from_le_bytes(bytes[24..32].try_into().unwrap());
    if l < 1 || l > RUN_MAX_L {
        return Err("run file: payload length out of range");
    }
    if bytes.len() as u64 != 64 + l {
        return Err("run file: total length");
    }
    let l = l as usize;
    if sha256(&bytes[..32 + l]) != bytes[32 + l..] {
        return Err("run file: check value mismatch");
    }
    let payload = bytes[32..32 + l].to_vec();
    let s = load(&payload)?;
    Ok((n, payload, s))
}
