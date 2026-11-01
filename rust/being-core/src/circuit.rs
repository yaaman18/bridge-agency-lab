//! The circuit of the organization layer. Copy of the canonical core/circuit.jl (itself the specification of
//! memory/turn_sed.js); same rules, constants and order of operations, checked bit for bit (being-tools check).
//! Indices are 0-based, as in the saved record.

use alloc::string::String;
use alloc::vec;
use alloc::vec::Vec;
use alloc::format;

pub const SMAX: i32 = 4;
pub const DECAY: i64 = 8;
pub const WINDOW: usize = 5;
pub const CAPACITY: f64 = 5.0;
pub const CAP: f64 = 50.0;
pub const W: i64 = 10;
pub const FRESH: i64 = 20;
pub const KINDS: usize = 4;
pub const ALPHA: f64 = 0.05;
pub const THETA_C: f64 = 0.5;
pub const FORGET: i64 = 100;
pub const THETA_B: f64 = 0.1;

/// Names of the receptor features (the observer's knowledge; the circuit is not told them).
pub const FEATURE_NAMES: [&str; 11] =
    ["y1>=3", "y2>=3", "y1==0", "y2==0", "noise", "clock3", "y1>y2", "y2>y1", "partner", "waiting", "not waiting"];
/// Pairs of feature slots exchanged by a reversal of the world.
pub const CROSS: [(usize, usize); 3] = [(0, 1), (2, 3), (6, 7)];

/// Feature `f` of the world. ys = [yield1, yield2, gesture, waiting]; `noise` is drawn only by the noise feature.
pub fn feature(f: usize, ys: &[f64; 4], t: i64, noise: &mut dyn FnMut() -> f64) -> bool {
    match f {
        0 => ys[0] >= 3.0,
        1 => ys[1] >= 3.0,
        2 => ys[0] == 0.0,
        3 => ys[1] == 0.0,
        4 => noise() < 0.5,
        5 => t % 3 == 0,
        6 => ys[0] > ys[1],
        7 => ys[1] > ys[0],
        8 => ys[2] > 0.0,
        9 => ys[3] > 0.0,
        _ => ys[3] == 0.0,
    }
}

pub fn cross(perm: &mut [usize; 11]) {
    for (i, j) in CROSS {
        perm.swap(i, j);
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    R,
    C,
    M,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Contrast {
    Sed,
    Learn,
    Learn2,
    Learn3,
    Bin3,
    Donly,
}

impl Contrast {
    pub fn parse(s: &str) -> Option<Contrast> {
        match s {
            "sed" => Some(Contrast::Sed),
            "learn" => Some(Contrast::Learn),
            "learn2" => Some(Contrast::Learn2),
            "learn3" => Some(Contrast::Learn3),
            "bin3" => Some(Contrast::Bin3),
            "donly" => Some(Contrast::Donly),
            _ => None,
        }
    }
}

#[derive(Clone)]
pub struct Circuit {
    pub names: Vec<String>,
    pub kind: Vec<Kind>,
    /// feature slot of a receptor (usize::MAX otherwise)
    pub feat: Vec<usize>,
    pub theta: Vec<i32>,
    /// motors: 1, 2 (patches), 3 (call); 0 otherwise
    pub patch: Vec<u8>,
    pub edges: Vec<(usize, usize, i32)>,
    pub q0: Vec<i32>,
    pub initial: Vec<bool>,
    /// slot s holds feature perm[s]
    pub perm: [usize; 11],
    pub ins: Vec<Vec<usize>>,
}

impl Circuit {
    pub fn newborn(partner: bool, proprio: bool) -> Circuit {
        let nr = if partner { if proprio { 11 } else { 9 } } else { 8 };
        let mut names = Vec::new();
        let mut kind = Vec::new();
        let mut feat = Vec::new();
        let mut theta = Vec::new();
        let mut patch = Vec::new();
        for i in 0..nr {
            names.push(format!("r{}", i + 1));
            kind.push(Kind::R);
            feat.push(i);
            theta.push(0);
            patch.push(0);
        }
        let cores: &[&str] = if partner { &["c1", "c2", "c3"] } else { &["c1", "c2"] };
        for n in cores {
            names.push(String::from(*n));
            kind.push(Kind::C);
            feat.push(usize::MAX);
            theta.push(1);
            patch.push(0);
        }
        let motors: &[&str] = if partner { &["m1", "m2", "m3"] } else { &["m1", "m2"] };
        for (i, n) in motors.iter().enumerate() {
            names.push(String::from(*n));
            kind.push(Kind::M);
            feat.push(usize::MAX);
            theta.push(2);
            patch.push(i as u8 + 1);
        }
        let id = |n: &str, names: &Vec<String>| names.iter().position(|x| x == n).unwrap();
        let mut edges = Vec::new();
        let mut q0 = Vec::new();
        let mut add = |a: &str, c: &str, q: i32, names: &Vec<String>| {
            edges.push((id(a, names), id(c, names), 1));
            q0.push(q);
        };
        for (a, c) in [("c1", "c1"), ("c2", "c2"), ("c1", "c2"), ("c2", "c1")] {
            add(a, c, 4, &names);
        }
        if partner {
            for (a, c) in [("c3", "c3"), ("c1", "c3"), ("c3", "c1"), ("c2", "c3"), ("c3", "c2")] {
                add(a, c, 4, &names);
            }
        }
        let pairs: &[(&str, &str)] =
            if partner { &[("c1", "m1"), ("c2", "m2"), ("c3", "m3")] } else { &[("c1", "m1"), ("c2", "m2")] };
        for (c, m) in pairs {
            add(c, m, 0, &names);
            for i in 0..nr {
                add(&format!("r{}", i + 1), m, 0, &names);
            }
        }
        let initial = names.iter().map(|n| n.starts_with('c')).collect();
        let mut b = Circuit {
            names,
            kind,
            feat,
            theta,
            patch,
            edges,
            q0,
            initial,
            perm: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
            ins: Vec::new(),
        };
        b.reindex();
        b
    }
    pub fn reindex(&mut self) {
        self.ins = vec![Vec::new(); self.names.len()];
        for (k, e) in self.edges.iter().enumerate() {
            self.ins[e.1].push(k);
        }
    }
    pub fn unit(&self, n: &str) -> Option<usize> {
        self.names.iter().position(|x| x == n)
    }
    pub fn edge(&self, a: &str, c: &str) -> Option<usize> {
        let (a, c) = (self.unit(a)?, self.unit(c)?);
        self.edges.iter().position(|e| e.0 == a && e.1 == c)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Pend {
    pub t: i64,
    pub e: Vec<usize>,
    pub r: Vec<usize>,
}

#[derive(Clone, Debug)]
pub struct CState {
    pub active: Vec<bool>,
    pub q: Vec<i32>,
    pub sg: Vec<i32>,
    pub h: Vec<i32>,
    pub off: Vec<i64>,
    pub t: i64,
    pub pend: Vec<Pend>,
    pub fresh: [i32; KINDS],
    pub prev: Option<Vec<bool>>,
    pub c_on: Option<Vec<f64>>,
    pub c_off: Option<Vec<f64>>,
    pub last_m: Option<Vec<i64>>,
}

impl CState {
    pub fn init(b: &Circuit) -> CState {
        let ne = b.q0.len();
        CState {
            active: b.initial.clone(),
            q: b.q0.clone(),
            sg: vec![0; ne],
            h: vec![0; ne],
            off: vec![0; b.names.len()],
            t: 0,
            pend: Vec::new(),
            fresh: [5; KINDS],
            prev: None,
            c_on: None,
            c_off: None,
            last_m: None,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Opts {
    pub contrast: Option<Contrast>,
    pub explore: bool,
    pub fail: bool,
    pub memory: bool,
    pub orient: bool,
    pub sil: Vec<usize>,
    /// the idle-first choice (item 72; core/circuit.jl idle_first, formal/LabCircuit.lean IdleFirst)
    pub idle_first: bool,
}

impl Default for Opts {
    fn default() -> Opts {
        Opts { contrast: None, explore: true, fail: true, memory: true, orient: true, sil: Vec::new(), idle_first: false }
    }
}

#[derive(Clone, Debug)]
pub struct StepOut {
    pub acting: Vec<usize>,
    pub d: [f64; 2],
    pub gate: bool,
    /// (motor, answered) for the acting patch motors, in acting order
    pub answered: Vec<(usize, bool)>,
    pub call: bool,
    pub call_while_waiting: bool,
    pub call_answered: bool,
    pub call_failed: i64,
}

impl StepOut {
    pub fn answered_of(&self, m: usize) -> Option<bool> {
        self.answered.iter().find(|x| x.0 == m).map(|x| x.1)
    }
}

pub fn allocate(offer: [f64; 2]) -> [f64; 2] {
    let mut d = [0.0, 0.0];
    let mut left = CAPACITY;
    let mut idx: Vec<usize> = [0usize, 1].iter().copied().filter(|&i| offer[i] > 0.0).collect();
    idx.sort_by(|&i, &j| {
        if offer[i] != offer[j] {
            offer[j].partial_cmp(&offer[i]).unwrap()
        } else {
            i.cmp(&j)
        }
    });
    for i in idx {
        d[i] = offer[i].min(left);
        left -= d[i];
    }
    d
}

/// One step of the circuit. y = [yield1, yield2, gesture]; `noise` is the world's noise.
pub fn step(st: &mut CState, b: &Circuit, y: &[f64], opts: &Opts, noise: &mut dyn FnMut() -> f64) -> StepOut {
    let n = b.names.len();
    let ne = b.edges.len();
    let old = st.active.clone();
    let g = if y.len() >= 3 { y[2] } else { 0.0 };
    let ys = [y[0], y[1], g, if st.pend.is_empty() { 0.0 } else { 1.0 }];
    let mem = opts.memory;
    let now = st.t + 1;
    let prev = st.prev.clone().unwrap_or_else(|| old.clone());
    let ct = opts.contrast;
    let sil = |u: usize| opts.sil.contains(&u);
    let onset: Vec<bool> = (0..n).map(|u| opts.orient && b.kind[u] == Kind::R && old[u] && !prev[u]).collect();
    let idle = |u: usize, st: &CState| {
        matches!(ct, Some(Contrast::Learn3) | Some(Contrast::Bin3) | Some(Contrast::Donly))
            && b.kind[u] == Kind::M
            && b.patch[u] <= 2
            && st.last_m.as_ref().map_or(false, |lm| now - lm[u] > FORGET)
    };
    let stale: Vec<bool> = (0..n)
        .map(|u| {
            opts.explore
                && b.kind[u] != Kind::R
                && !b.ins[u].is_empty()
                && (idle(u, st) || b.ins[u].iter().all(|&k| st.q[k] == 0 && (!mem || st.sg[k] == 0)))
        })
        .collect();
    let mut total = vec![0i32; n];
    let mut conf = vec![0i32; n];
    let mut habit = vec![0i32; n];
    let mut drove = vec![false; ne];
    for (k, &(a, c, w)) in b.edges.iter().enumerate() {
        if (st.q[k] >= 1
            || (mem && st.sg[k] >= 1)
            || stale[c]
            || (onset[a] && st.q[k] == 0 && st.sg[k] == 0 && st.h[k] == 0))
            && old[a]
            && !sil(a)
        {
            total[c] += w;
            if st.q[k] >= 1 {
                conf[c] += w;
            } else if mem && st.sg[k] >= 1 {
                habit[c] += w;
            }
            drove[k] = true;
        }
    }
    let mut nw = vec![false; n];
    for u in 0..n {
        nw[u] = if b.kind[u] == Kind::R { feature(b.perm[b.feat[u]], &ys, now, noise) } else { total[u] >= b.theta[u] };
    }
    let motors: Vec<usize> = (0..n).filter(|&u| b.kind[u] == Kind::M).collect();
    let cand: Vec<usize> = motors.iter().copied().filter(|&m| nw[m] && b.patch[m] <= 2).collect();
    // idle_first: among the candidates, a motor that has not acted for longer than FORGET steps is preferred; the old
    // ranking decides among the preferred ones (or all, if none is idle)
    if opts.idle_first && st.last_m.is_none() {
        st.last_m = Some(vec![0; n]);
    }
    if cand.len() > 1 {
        let key = |m: usize| conf[m] as i64 * 1_000_000 + habit[m] as i64 * 1_000 + total[m] as i64;
        let rank = |cs: &[usize]| -> usize {
            let best = cs.iter().map(|&m| key(m)).max().unwrap();
            let tied: Vec<usize> = cs.iter().copied().filter(|&m| key(m) == best).collect();
            let pv: Vec<usize> = tied.iter().copied().filter(|&m| old[m]).collect();
            let pool = if pv.is_empty() { &tied } else { &pv };
            *pool.iter().min_by_key(|&&m| b.patch[m]).unwrap()
        };
        let mut win = rank(&cand);
        if opts.idle_first {
            let lm = st.last_m.as_ref().unwrap();
            let idl: Vec<usize> = cand.iter().copied().filter(|&m| now - lm[m] > FORGET).collect();
            if !idl.is_empty() {
                win = rank(&idl);
            }
        }
        for &m in &cand {
            if m != win {
                nw[m] = false;
            }
        }
    }
    let acting: Vec<usize> = motors.iter().copied().filter(|&m| nw[m] && !sil(m)).collect();
    let on_patch: Vec<usize> = acting.iter().copied().filter(|&m| b.patch[m] <= 2).collect();
    let call = acting.iter().copied().find(|&m| b.patch[m] == 3);
    let mut offer = [0.0, 0.0];
    for &m in &on_patch {
        let p = b.patch[m] as usize - 1;
        offer[p] = y[p];
    }
    let d = allocate(offer);
    let answered: Vec<(usize, bool)> = on_patch.iter().map(|&m| (m, d[b.patch[m] as usize - 1] > 0.0)).collect();
    let gate = d[0] + d[1] > 0.0 && answered.iter().all(|x| x.1);
    let ok = |u: usize| b.kind[u] != Kind::M || answered.iter().any(|x| x.0 == u && x.1);
    let mut confirmed: Vec<bool> =
        b.edges.iter().enumerate().map(|(k, &(a, c, _))| drove[k] && nw[c] && gate && ok(a) && ok(c)).collect();
    let rm = |k: usize| {
        let (a, c, _) = b.edges[k];
        b.kind[a] == Kind::R && b.kind[c] == Kind::M && b.patch[c] <= 2
    };
    let stats = ct.is_some() && ct != Some(Contrast::Donly);
    if stats {
        if st.c_on.is_none() {
            st.c_on = Some(vec![f64::NAN; ne]);
            st.c_off = Some(vec![f64::NAN; ne]);
        }
        for &m in &on_patch {
            let dm = d[b.patch[m] as usize - 1];
            for (k, &(a, c, _)) in b.edges.iter().enumerate() {
                if c != m || b.kind[a] != Kind::R {
                    continue;
                }
                let arr = if old[a] { st.c_on.as_mut().unwrap() } else { st.c_off.as_mut().unwrap() };
                let v = if ct == Some(Contrast::Bin3) { if dm > 0.0 { 1.0 } else { 0.0 } } else { dm };
                arr[k] = if arr[k].is_nan() { v } else { arr[k] + ALPHA * (v - arr[k]) };
            }
        }
    }
    let l2 = matches!(ct, Some(Contrast::Learn2) | Some(Contrast::Learn3) | Some(Contrast::Bin3));
    if opts.idle_first && !(l2 || ct == Some(Contrast::Donly)) {
        for &m in &on_patch {
            st.last_m.as_mut().unwrap()[m] = now;
        }
    }
    if l2 || ct == Some(Contrast::Donly) {
        if st.last_m.is_none() {
            st.last_m = Some(vec![0; n]);
        }
        for &m in &motors {
            if b.patch[m] > 2 {
                continue;
            }
            if on_patch.contains(&m) {
                st.last_m.as_mut().unwrap()[m] = now;
            } else if l2 && now - st.last_m.as_ref().unwrap()[m] == FORGET {
                for (k, &(a, c, _)) in b.edges.iter().enumerate() {
                    if c == m && b.kind[a] == Kind::R {
                        st.c_on.as_mut().unwrap()[k] = f64::NAN;
                        st.c_off.as_mut().unwrap()[k] = f64::NAN;
                    }
                }
            }
        }
    }
    let passes = |k: usize, st: &CState| -> bool {
        if !stats || !rm(k) {
            return true;
        }
        let cc = st.c_on.as_ref().unwrap()[k] - st.c_off.as_ref().unwrap()[k];
        if l2 && cc.is_nan() {
            true
        } else {
            cc > if ct == Some(Contrast::Bin3) { THETA_B } else { THETA_C }
        }
    };
    if l2 {
        for k in 0..ne {
            if confirmed[k] && !passes(k, st) {
                confirmed[k] = false;
            }
        }
    }
    let grow = |k: usize, st: &mut CState| {
        if (ct == Some(Contrast::Learn) || l2) && !passes(k, st) {
            return;
        }
        if st.q[k] < SMAX {
            st.q[k] = SMAX.min(st.q[k] + 1 + if mem { st.sg[k] } else { 0 });
            if mem && st.q[k] == SMAX && (ct != Some(Contrast::Sed) || passes(k, st)) {
                st.sg[k] = SMAX.min(st.sg[k] + 1);
            }
        }
    };
    let weaken = |k: usize, st: &mut CState| {
        if st.q[k] == 0 && st.sg[k] == 0 {
            st.h[k] = SMAX.min(st.h[k] + 1);
        }
        if st.q[k] > 0 || !mem {
            st.q[k] = (st.q[k] - 1).max(0);
        } else {
            st.sg[k] = (st.sg[k] - 1).max(0);
        }
    };
    for k in 0..ne {
        if confirmed[k] {
            grow(k, st);
        }
    }
    if opts.fail {
        for &m in &on_patch {
            if answered.iter().any(|x| x.0 == m && x.1) {
                continue;
            }
            for (k, &(a, c, _)) in b.edges.iter().enumerate() {
                if c == m && b.kind[a] == Kind::R && drove[k] && !confirmed[k] {
                    weaken(k, st);
                }
            }
        }
    }
    // The partner's answer: a fresh gesture answers the oldest call still pending (made at an earlier step, within W).
    let mut call_answered = false;
    let mut call_failed = 0;
    let gi = g as i64;
    if gi > 0 && st.fresh[gi as usize - 1] >= 1 {
        if let Some(i) = st.pend.iter().position(|p| p.t < now && now - p.t <= W) {
            st.fresh[gi as usize - 1] = 0;
            call_answered = true;
            let es = st.pend[i].e.clone();
            for k in es {
                if !confirmed[k] {
                    grow(k, st);
                    confirmed[k] = true;
                }
            }
            st.pend.remove(i);
        }
    }
    let pend = core::mem::take(&mut st.pend);
    let mut keep = Vec::new();
    for p in pend {
        if now - p.t >= W {
            call_failed += 1;
            if opts.fail {
                for &k in &p.r {
                    if !confirmed[k] {
                        weaken(k, st);
                    }
                }
            }
        } else {
            keep.push(p);
        }
    }
    st.pend = keep;
    if let Some(cm) = call {
        let okc = |u: usize| b.kind[u] != Kind::M || u == cm;
        let e = (0..ne).filter(|&k| { let (a, c, _) = b.edges[k]; drove[k] && nw[c] && okc(a) && okc(c) }).collect();
        let r = (0..ne).filter(|&k| { let (a, c, _) = b.edges[k]; c == cm && b.kind[a] == Kind::R && drove[k] }).collect();
        st.pend.push(Pend { t: now, e, r });
    }
    let waiting = [0.0, 0.0, 0.0, if st.pend.is_empty() { 0.0 } else { 1.0 }];
    for u in 0..n {
        if b.kind[u] == Kind::R && b.feat[u] >= 9 {
            nw[u] = feature(b.perm[b.feat[u]], &waiting, now, noise);
        }
    }
    if now % FRESH == 0 {
        for f in st.fresh.iter_mut() {
            *f = 5.min(*f + 1);
        }
    }
    if now % DECAY == 0 {
        for k in 0..ne {
            if !confirmed[k] {
                st.q[k] = (st.q[k] - 1).max(0);
            }
        }
    }
    for u in 0..n {
        if b.kind[u] != Kind::R {
            continue;
        }
        st.off[u] = if nw[u] { 0 } else { st.off[u] + 1 };
        if st.off[u] > 0 && st.off[u] % DECAY == 0 {
            for (k, &(a, _, _)) in b.edges.iter().enumerate() {
                if a == u && st.h[k] > 0 {
                    st.h[k] -= 1;
                }
            }
        }
    }
    st.prev = Some(old);
    st.active = nw;
    st.t = now;
    StepOut {
        acting,
        d,
        gate,
        answered,
        call: call.is_some(),
        call_while_waiting: call.is_some() && ys[3] > 0.0,
        call_answered,
        call_failed,
    }
}

/// Form: a directed cycle of confident contingencies among the non-receptor units active within the window.
pub fn form(win: &[(Vec<bool>, Vec<i32>)], b: &Circuit) -> bool {
    let n = b.names.len();
    let mut uu = vec![false; n];
    for (act, _) in win {
        for u in 0..n {
            if act[u] && b.kind[u] != Kind::R {
                uu[u] = true;
            }
        }
    }
    let q = &win[win.len() - 1].1;
    let mut adj = vec![Vec::new(); n];
    for (k, &(a, c, _)) in b.edges.iter().enumerate() {
        if uu[a] && uu[c] && q[k] >= 1 {
            adj[a].push(c);
        }
    }
    let mut col = vec![0u8; n];
    fn dfs(u: usize, adj: &Vec<Vec<usize>>, col: &mut Vec<u8>) -> bool {
        col[u] = 1;
        for &v in &adj[u] {
            if col[v] == 1 {
                return true;
            }
            if col[v] == 0 && dfs(v, adj, col) {
                return true;
            }
        }
        col[u] = 2;
        false
    }
    for u in 0..n {
        if uu[u] && col[u] == 0 && dfs(u, &adj, &mut col) {
            return true;
        }
    }
    false
}
