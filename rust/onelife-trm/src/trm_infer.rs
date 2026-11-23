//! Phase 3 deterministic TRM inference library inside `rust/onelife-trm`.
//! Mirrors S60 `rust/trm-det/src/main.rs` and Julia `experiments/trm/det/TrmDet.jl` bit-for-bit:
//! zero FMA, left-associative sums, zero libm, sharing S60 `exp_det`.
//! Adds `forward_budgeted` with 0-cycle fallback (`H_init`) for `B_max` budget enforcement.

use std::collections::HashMap;

use crate::head_c2::{exp_det, HIDDEN};

pub const MAGIC_BUNDLE: &[u8; 8] = b"TRMDET1\n";
pub const MAGIC_OUT: &[u8; 8] = b"TRMOUT1\n";
const TAG_F32: u8 = 1;
const TAG_I32: u8 = 2;

pub const OPS_FIXED: u64 = 512;
pub const OPS_PER_H_CYCLE: u64 = 1000;

struct Rec {
    name: String,
    tag: u8,
    dims: Vec<usize>,
    f: Vec<f32>,
    i: Vec<i32>,
}

fn rec_f(name: String, dims: Vec<usize>, f: Vec<f32>) -> Rec {
    Rec { name, tag: TAG_F32, dims, f, i: Vec::new() }
}
fn rec_i(name: String, dims: Vec<usize>, i: Vec<i32>) -> Rec {
    Rec { name, tag: TAG_I32, dims, f: Vec::new(), i }
}

struct Reader<'a> {
    b: &'a [u8],
    p: usize,
}
impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8], String> {
        if self.p + n > self.b.len() {
            return Err("short file".into());
        }
        let s = &self.b[self.p..self.p + n];
        self.p += n;
        Ok(s)
    }
    fn u8(&mut self) -> Result<u8, String> {
        Ok(self.take(1)?[0])
    }
    fn u16(&mut self) -> Result<u16, String> {
        let s = self.take(2)?;
        Ok(u16::from_le_bytes([s[0], s[1]]))
    }
    fn u32(&mut self) -> Result<u32, String> {
        let s = self.take(4)?;
        Ok(u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
    }
}

fn read_recs(bytes: &[u8], magic: &[u8; 8]) -> Result<Vec<Rec>, String> {
    let mut r = Reader { b: bytes, p: 0 };
    if r.take(8)? != magic {
        return Err("bad magic".into());
    }
    let n = r.u32()? as usize;
    let mut recs = Vec::with_capacity(n);
    for _ in 0..n {
        let l = r.u16()? as usize;
        let name = String::from_utf8(r.take(l)?.to_vec()).map_err(|_| "bad name".to_string())?;
        let tag = r.u8()?;
        let d = r.u8()? as usize;
        let mut dims = Vec::with_capacity(d);
        for _ in 0..d {
            dims.push(r.u32()? as usize);
        }
        let cnt: usize = if d == 0 { 0 } else { dims.iter().product() };
        let raw = r.take(4 * cnt)?;
        if tag == TAG_F32 {
            let v = raw
                .chunks_exact(4)
                .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
                .collect();
            recs.push(rec_f(name, dims, v));
        } else if tag == TAG_I32 {
            let v = raw
                .chunks_exact(4)
                .map(|c| i32::from_le_bytes([c[0], c[1], c[2], c[3]]))
                .collect();
            recs.push(rec_i(name, dims, v));
        } else {
            return Err(format!("bad tag {} in {}", tag, name));
        }
    }
    if r.p != bytes.len() {
        return Err("trailing bytes".into());
    }
    Ok(recs)
}

fn write_recs(recs: &[Rec], magic: &[u8; 8]) -> Vec<u8> {
    let mut o = Vec::new();
    o.extend_from_slice(magic);
    o.extend_from_slice(&(recs.len() as u32).to_le_bytes());
    for r in recs {
        o.extend_from_slice(&(r.name.len() as u16).to_le_bytes());
        o.extend_from_slice(r.name.as_bytes());
        o.push(r.tag);
        o.push(r.dims.len() as u8);
        for &d in &r.dims {
            o.extend_from_slice(&(d as u32).to_le_bytes());
        }
        if r.tag == TAG_F32 {
            for &x in &r.f {
                o.extend_from_slice(&x.to_le_bytes());
            }
        } else {
            for &x in &r.i {
                o.extend_from_slice(&x.to_le_bytes());
            }
        }
    }
    o
}

struct Layer {
    wqkv: Vec<f32>,
    wo: Vec<f32>,
    wgu: Vec<f32>,
    wdown: Vec<f32>,
}

pub struct TrmModel {
    pub b: usize,
    pub s: usize,
    pub v: usize,
    pub h: usize,
    pub nh: usize,
    pub hd: usize,
    pub inter: usize,
    pub hc: usize,
    pub lc: usize,
    pub hmax: i32,
    pub pos: i32,
    pub nsteps: usize,
    eps: f32,
    c707: f32,
    escale: f32,
    emb_tok: Vec<f32>,
    emb_pos: Vec<f32>,
    cos: Vec<f32>,
    sin: Vec<f32>,
    lm: Vec<f32>,
    qw: Vec<f32>,
    qb: Vec<f32>,
    pub hinit: Vec<f32>,
    pub linit: Vec<f32>,
    layers: Vec<Layer>,
}

fn get<'a>(d: &'a HashMap<String, Rec>, name: &str, tag: u8) -> Result<&'a Rec, String> {
    let r = d.get(name).ok_or_else(|| format!("missing record {name}"))?;
    if r.tag != tag {
        return Err(format!("wrong type for {name}"));
    }
    Ok(r)
}
fn getf(d: &HashMap<String, Rec>, name: &str) -> Result<Vec<f32>, String> {
    Ok(get(d, name, TAG_F32)?.f.clone())
}
fn geti(d: &HashMap<String, Rec>, name: &str) -> Result<Vec<i32>, String> {
    Ok(get(d, name, TAG_I32)?.i.clone())
}

impl TrmModel {
    fn from_map(d: &HashMap<String, Rec>) -> Result<Self, String> {
        for r in d.values() {
            if r.tag == TAG_F32 && !r.f.iter().all(|x| x.is_finite()) {
                return Err(format!("non-finite value in {}", r.name));
            }
        }
        let c = geti(d, "cfg")?;
        if c.len() != 13 || c.iter().any(|&x| x < 0) {
            return Err("invalid cfg".into());
        }
        let u = |j: usize| c[j] as usize;
        if c[11] != 0 {
            return Err("puzzle_emb_len must be 0".into());
        }
        let k = getf(d, "const")?;
        if k.len() != 3 {
            return Err("const length".into());
        }
        let mut layers = Vec::new();
        for l in 0..u(8) {
            let p = format!("inner.L_level.layers.{l}");
            layers.push(Layer {
                wqkv: getf(d, &format!("{p}.self_attn.qkv_proj.weight"))?,
                wo: getf(d, &format!("{p}.self_attn.o_proj.weight"))?,
                wgu: getf(d, &format!("{p}.mlp.gate_up_proj.weight"))?,
                wdown: getf(d, &format!("{p}.mlp.down_proj.weight"))?,
            });
        }
        let pos = c[10];
        Ok(Self {
            b: u(0),
            s: u(1),
            v: u(2),
            h: u(3),
            nh: u(4),
            hd: u(3) / u(4),
            inter: u(5),
            hc: u(6),
            lc: u(7),
            hmax: c[9],
            pos,
            nsteps: u(12),
            eps: k[0],
            c707: k[1],
            escale: k[2],
            emb_tok: getf(d, "inner.embed_tokens.embedding_weight")?,
            emb_pos: if pos == 2 { getf(d, "inner.embed_pos.embedding_weight")? } else { Vec::new() },
            cos: if pos == 1 { getf(d, "rope.cos")? } else { Vec::new() },
            sin: if pos == 1 { getf(d, "rope.sin")? } else { Vec::new() },
            lm: getf(d, "inner.lm_head.weight")?,
            qw: getf(d, "inner.q_head.weight")?,
            qb: getf(d, "inner.q_head.bias")?,
            hinit: getf(d, "inner.H_init")?,
            linit: getf(d, "inner.L_init")?,
            layers,
        })
    }

    pub fn from_bundle_bytes(bytes: &[u8]) -> Result<Self, String> {
        let recs = read_recs(bytes, MAGIC_BUNDLE)?;
        let mut d = HashMap::new();
        for r in recs {
            d.insert(r.name.clone(), r);
        }
        Self::from_map(&d)
    }

    /// Budgeted single-step forward pass for AUE runtime (`B=1, seq_len=47, H=32`).
    /// When `max_h_cycles == 0`, executes exact 0-cycle fallback returning `H_init`.
    pub fn forward_budgeted(
        &self,
        tokens: &[i32],
        max_h_cycles: usize,
    ) -> Result<TrmStepOutput, String> {
        if self.b != 1 || self.h != HIDDEN || tokens.len() != self.s || self.s < 47 {
            return Err("forward_budgeted requires B=1, H=32, seq_len>=47".into());
        }
        let mut h45 = [0.0f32; HIDDEN];
        let mut h46 = [0.0f32; HIDDEN];
        if max_h_cycles == 0 {
            h45.copy_from_slice(&self.hinit[..HIDDEN]);
            h46.copy_from_slice(&self.hinit[..HIDDEN]);
            return Ok(TrmStepOutput {
                h_pos45: h45,
                h_pos46: h46,
                h_cycles_completed: 0,
                ops_used: OPS_FIXED,
            });
        }
        let emb = input_embeddings(self, tokens)?;
        let mut zh = vec![0.0f32; self.s * self.h];
        let mut zl = vec![0.0f32; self.s * self.h];
        for si in 0..self.s {
            for k in 0..self.h {
                zh[si * self.h + k] = self.hinit[k];
                zl[si * self.h + k] = self.linit[k];
            }
        }
        let cap = max_h_cycles.min(self.hc * (self.hmax as usize));
        for _ in 0..cap {
            let (nh, nl) = h_round(self, zh, zl, &emb);
            zh = nh;
            zl = nl;
        }
        // Query positions 45 and 46 (0-based indices 44 and 45? In S64 1-based pos 45/46 => 0-based 44/45 or 45/46:
        // S64 seq_len=47: 0-based indices 0..43 = 44 history tokens, 44 = SEP/PAD, 45 = query a1, 46 = query a2)
        h45.copy_from_slice(&zh[45 * HIDDEN..46 * HIDDEN]);
        h46.copy_from_slice(&zh[46 * HIDDEN..47 * HIDDEN]);
        Ok(TrmStepOutput {
            h_pos45: h45,
            h_pos46: h46,
            h_cycles_completed: cap,
            ops_used: OPS_FIXED + (cap as u64) * OPS_PER_H_CYCLE,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TrmStepOutput {
    pub h_pos45: [f32; HIDDEN],
    pub h_pos46: [f32; HIDDEN],
    pub h_cycles_completed: usize,
    pub ops_used: u64,
}

fn linear(x: &[f32], rows: usize, nin: usize, w: &[f32], nout: usize, b: Option<&[f32]>) -> Vec<f32> {
    let mut y = vec![0.0f32; rows * nout];
    for r in 0..rows {
        let xo = r * nin;
        for o in 0..nout {
            let wo = o * nin;
            let mut acc = 0.0f32;
            for i in 0..nin {
                acc = acc + x[xo + i] * w[wo + i];
            }
            if let Some(bb) = b {
                acc = acc + bb[o];
            }
            y[r * nout + o] = acc;
        }
    }
    y
}

fn rms_norm(x: &[f32], rows: usize, h: usize, eps: f32) -> Vec<f32> {
    let mut y = vec![0.0f32; rows * h];
    let fh = h as f32;
    for r in 0..rows {
        let mut s = 0.0f32;
        for k in 0..h {
            let v = x[r * h + k];
            s = s + v * v;
        }
        let v = s / fh;
        let inv = 1.0f32 / (v + eps).sqrt();
        for k in 0..h {
            y[r * h + k] = x[r * h + k] * inv;
        }
    }
    y
}

fn vadd(a: &[f32], b: &[f32]) -> Vec<f32> {
    a.iter().zip(b.iter()).map(|(x, y)| x + y).collect()
}

fn silu(x: f32) -> f32 {
    x * (1.0f32 / (1.0f32 + exp_det(-x)))
}

fn rope(m: &TrmModel, q: &[f32]) -> Vec<f32> {
    let hd = m.hd;
    let half = hd / 2;
    let mut y = vec![0.0f32; q.len()];
    let nrow = q.len() / hd;
    for row in 0..nrow {
        let s = row % m.s;
        for d in 0..hd {
            let x = q[row * hd + d];
            let rh = if d < half { -q[row * hd + d + half] } else { q[row * hd + d - half] };
            let a = x * m.cos[s * hd + d];
            let bb = rh * m.sin[s * hd + d];
            y[row * hd + d] = a + bb;
        }
    }
    y
}

fn attention(m: &TrmModel, l: &Layer, h: &[f32]) -> Vec<f32> {
    let (b, s, hh, nh, hd) = (m.b, m.s, m.h, m.nh, m.hd);
    let qkv = linear(h, b * s, hh, &l.wqkv, 3 * hh, None);
    let n = b * nh * s * hd;
    let mut q = vec![0.0f32; n];
    let mut k = vec![0.0f32; n];
    let mut v = vec![0.0f32; n];
    for bi in 0..b {
        for hi in 0..nh {
            for si in 0..s {
                for d in 0..hd {
                    let base = (bi * s + si) * 3 * hh;
                    let dst = ((bi * nh + hi) * s + si) * hd + d;
                    q[dst] = qkv[base + hi * hd + d];
                    k[dst] = qkv[base + (nh + hi) * hd + d];
                    v[dst] = qkv[base + (2 * nh + hi) * hd + d];
                }
            }
        }
    }
    if m.pos == 1 {
        q = rope(m, &q);
        k = rope(m, &k);
    }
    let scale = 1.0f32 / (hd as f32).sqrt();
    let mut out = vec![0.0f32; b * s * hh];
    let mut sc = vec![0.0f32; s];
    for bi in 0..b {
        for hi in 0..nh {
            let hb = (bi * nh + hi) * s;
            for i in 0..s {
                for j in 0..s {
                    let mut acc = 0.0f32;
                    for d in 0..hd {
                        acc = acc + q[(hb + i) * hd + d] * k[(hb + j) * hd + d];
                    }
                    sc[j] = acc * scale;
                }
                let mut mx = sc[0];
                for j in 1..s {
                    if sc[j] > mx {
                        mx = sc[j];
                    }
                }
                for j in 0..s {
                    sc[j] = exp_det(sc[j] - mx);
                }
                let mut z = 0.0f32;
                for j in 0..s {
                    z = z + sc[j];
                }
                for j in 0..s {
                    sc[j] = sc[j] / z;
                }
                for d in 0..hd {
                    let mut acc = 0.0f32;
                    for j in 0..s {
                        acc = acc + sc[j] * v[(hb + j) * hd + d];
                    }
                    out[(bi * s + i) * hh + hi * hd + d] = acc;
                }
            }
        }
    }
    linear(&out, b * s, hh, &l.wo, hh, None)
}

fn swiglu(m: &TrmModel, l: &Layer, x: &[f32]) -> Vec<f32> {
    let rows = m.b * m.s;
    let it = m.inter;
    let g = linear(x, rows, m.h, &l.wgu, 2 * it, None);
    let mut a = vec![0.0f32; rows * it];
    for r in 0..rows {
        for j in 0..it {
            a[r * it + j] = silu(g[r * 2 * it + j]) * g[r * 2 * it + it + j];
        }
    }
    linear(&a, rows, it, &l.wdown, m.h, None)
}

fn block(m: &TrmModel, l: &Layer, h: &[f32]) -> Vec<f32> {
    let rows = m.b * m.s;
    let t = attention(m, l, h);
    let hs = rms_norm(&vadd(h, &t), rows, m.h, m.eps);
    let mo = swiglu(m, l, &hs);
    rms_norm(&vadd(&hs, &mo), rows, m.h, m.eps)
}

fn l_level(m: &TrmModel, z: &[f32], inj: &[f32]) -> Vec<f32> {
    let mut h = vadd(z, inj);
    for l in &m.layers {
        h = block(m, l, &h);
    }
    h
}

fn input_embeddings(m: &TrmModel, tokens: &[i32]) -> Result<Vec<f32>, String> {
    let (b, s, h) = (m.b, m.s, m.h);
    let mut e = vec![0.0f32; b * s * h];
    for bi in 0..b {
        for si in 0..s {
            let t = tokens[bi * s + si];
            if t < 0 || t as usize >= m.v {
                return Err("token out of range".into());
            }
            let t = t as usize;
            for k in 0..h {
                let mut x = m.emb_tok[t * h + k];
                if m.pos == 2 {
                    x = m.c707 * (x + m.emb_pos[si * h + k]);
                }
                e[(bi * s + si) * h + k] = m.escale * x;
            }
        }
    }
    Ok(e)
}

fn h_round(m: &TrmModel, zh: Vec<f32>, zl: Vec<f32>, emb: &[f32]) -> (Vec<f32>, Vec<f32>) {
    let mut zl = zl;
    for _ in 0..m.lc {
        zl = l_level(m, &zl, &vadd(&zh, emb));
    }
    let zh = l_level(m, &zh, &zl);
    (zh, zl)
}

#[derive(Clone)]
struct Carry {
    zh: Vec<f32>,
    zl: Vec<f32>,
    steps: Vec<i32>,
    halted: Vec<bool>,
    cd_inputs: Vec<i32>,
    cd_pid: Vec<i32>,
}

fn initial_carry(m: &TrmModel) -> Carry {
    let n = m.b * m.s * m.h;
    Carry {
        zh: vec![0.0f32; n],
        zl: vec![0.0f32; n],
        steps: vec![0; m.b],
        halted: vec![true; m.b],
        cd_inputs: vec![0; m.b * m.s],
        cd_pid: vec![0; m.b],
    }
}

fn act_reset(m: &TrmModel, c: &Carry, inputs: &[i32], pid: &[i32]) -> Carry {
    let mut r = c.clone();
    let (s, h) = (m.s, m.h);
    for bi in 0..m.b {
        if !c.halted[bi] {
            continue;
        }
        for si in 0..s {
            for k in 0..h {
                r.zh[(bi * s + si) * h + k] = m.hinit[k];
                r.zl[(bi * s + si) * h + k] = m.linit[k];
            }
        }
        r.steps[bi] = 0;
        for si in 0..s {
            r.cd_inputs[bi * s + si] = inputs[bi * s + si];
        }
        r.cd_pid[bi] = pid[bi];
    }
    r
}

struct Outs {
    logits: Vec<f32>,
    q_halt: Vec<f32>,
    q_continue: Vec<f32>,
}

fn outputs_from_z(m: &TrmModel, zh: &[f32]) -> Outs {
    let (b, s, h) = (m.b, m.s, m.h);
    let logits = linear(zh, b * s, h, &m.lm, m.v, None);
    let mut x0 = vec![0.0f32; b * h];
    for bi in 0..b {
        for k in 0..h {
            x0[bi * h + k] = zh[(bi * s) * h + k];
        }
    }
    let q = linear(&x0, b, h, &m.qw, 2, Some(&m.qb));
    Outs {
        logits,
        q_halt: (0..b).map(|bi| q[2 * bi]).collect(),
        q_continue: (0..b).map(|bi| q[2 * bi + 1]).collect(),
    }
}

fn act_step(m: &TrmModel, c: &Carry, inputs: &[i32], pid: &[i32]) -> Result<(Carry, Outs), String> {
    let r = act_reset(m, c, inputs, pid);
    let emb = input_embeddings(m, &r.cd_inputs)?;
    let mut zh = r.zh.clone();
    let mut zl = r.zl.clone();
    for _ in 0..m.hc {
        let (a, b) = h_round(m, zh, zl, &emb);
        zh = a;
        zl = b;
    }
    let o = outputs_from_z(m, &zh);
    let steps: Vec<i32> = r.steps.iter().map(|&x| x + 1).collect();
    let halted: Vec<bool> = steps.iter().map(|&x| x >= m.hmax).collect();
    Ok((Carry { zh, zl, steps, halted, cd_inputs: r.cd_inputs, cd_pid: r.cd_pid }, o))
}

fn case_recs(m: &TrmModel, case: &str, c: &Carry, o: &Outs, out: &mut Vec<Rec>) {
    let (b, s, h, v) = (m.b, m.s, m.h, m.v);
    let n = |q: &str| format!("{case}.{q}");
    out.push(rec_f(n("logits"), vec![b, s, v], o.logits.clone()));
    out.push(rec_f(n("q_halt"), vec![b], o.q_halt.clone()));
    out.push(rec_f(n("q_continue"), vec![b], o.q_continue.clone()));
    out.push(rec_f(n("z_H"), vec![b, s, h], c.zh.clone()));
    out.push(rec_f(n("z_L"), vec![b, s, h], c.zl.clone()));
    out.push(rec_i(n("steps"), vec![b], c.steps.clone()));
    out.push(rec_i(n("halted"), vec![b], c.halted.iter().map(|&x| if x { 1 } else { 0 }).collect()));
    out.push(rec_i(n("cd_inputs"), vec![b, s], c.cd_inputs.clone()));
    out.push(rec_i(n("cd_pid"), vec![b], c.cd_pid.clone()));
}

fn batch_of(d: &HashMap<String, Rec>, k: i32) -> Result<(Vec<i32>, Vec<i32>), String> {
    Ok((geti(d, &format!("x{k}.inputs"))?, geti(d, &format!("x{k}.pid"))?))
}

/// Exact S60 `TRMDET1 -> TRMOUT1` runner (must match Julia `TrmDet.jl` and `rust/trm-det` bit-for-bit).
pub fn run_trm_bundle(bundle_bytes: &[u8]) -> Result<Vec<u8>, String> {
    let recs = read_recs(bundle_bytes, MAGIC_BUNDLE)?;
    let mut d = HashMap::new();
    for r in recs {
        d.insert(r.name.clone(), r);
    }
    let m = TrmModel::from_map(&d)?;
    let sin = geti(&d, "steps.input")?;
    if sin.len() != m.nsteps {
        return Err("steps.input length".into());
    }
    let mut out = Vec::new();
    let mut c = initial_carry(&m);
    let mut c1: Option<Carry> = None;
    for k in 0..m.nsteps {
        let (inp, pid) = batch_of(&d, sin[k])?;
        let (nc, o) = act_step(&m, &c, &inp, &pid)?;
        c = nc;
        if k == 0 {
            c1 = Some(c.clone());
        }
        case_recs(&m, &format!("step{}", k + 1), &c, &o, &mut out);
    }
    let mut mc = c1.ok_or("no step 1")?;
    let sh = geti(&d, "mixed.start_halted")?;
    if sh.len() != m.b {
        return Err("start_halted length".into());
    }
    mc.halted = sh.iter().map(|&x| x != 0).collect();
    let mi = geti(&d, "mixed.input")?;
    let (inp, pid) = batch_of(&d, *mi.first().ok_or("mixed.input empty")?)?;
    let (nc, o) = act_step(&m, &mc, &inp, &pid)?;
    case_recs(&m, "mixed", &nc, &o, &mut out);
    if out.len() != 45 {
        return Err(format!("internal: record count {}", out.len()));
    }
    Ok(write_recs(&out, MAGIC_OUT))
}
