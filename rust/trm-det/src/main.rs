// S60 deterministic inference of TRM (spec discussion/specs/S60-trm-det.md r3). Copy of the canonical Julia
// experiments/trm/det/TrmDet.jl; the two must execute the same binary32 ops in the same order.
// Port of SamsungSAILMontreal/TinyRecursiveModels (commit 7de0d20), eval-mode forward, attention variant,
// puzzle_emb_len 0. Copyright (c) 2025 Samsung Electronics Co., Ltd. MIT License: experiments/trm/LICENSE-upstream-MIT.txt
//
// Sums start at +0 and run over increasing index; no mul_add, no libm, no float environment changes.
// Usage: trm-det BUNDLE OUT [--mutate linear_rev|softmax_rev]   (exit 2 on a bad bundle). Timing goes to stderr.

use std::collections::HashMap;
use std::io::Write;
use std::time::Instant;

const MAGIC_BUNDLE: &[u8; 8] = b"TRMDET1\n";
const MAGIC_OUT: &[u8; 8] = b"TRMOUT1\n";
const TAG_F32: u8 = 1;
const TAG_I32: u8 = 2;

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
            let v = raw.chunks_exact(4).map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect();
            recs.push(rec_f(name, dims, v));
        } else if tag == TAG_I32 {
            let v = raw.chunks_exact(4).map(|c| i32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect();
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

// ---------------- exp_det (spec §1) ----------------

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

fn fb(b: u32) -> f32 {
    f32::from_bits(b)
}

fn exp_det(x: f32) -> f32 {
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

// ---------------- model ----------------

#[derive(Clone, Copy, PartialEq)]
enum Mutate {
    None,
    LinearRev,
    SoftmaxRev,
}

struct Layer {
    wqkv: Vec<f32>,
    wo: Vec<f32>,
    wgu: Vec<f32>,
    wdown: Vec<f32>,
}

struct Model {
    b: usize,
    s: usize,
    v: usize,
    h: usize,
    nh: usize,
    hd: usize,
    inter: usize,
    hc: usize,
    lc: usize,
    hmax: i32,
    pos: i32,
    nsteps: usize,
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
    hinit: Vec<f32>,
    linit: Vec<f32>,
    layers: Vec<Layer>,
    mutate: Mutate,
}

fn get<'a>(d: &'a HashMap<String, Rec>, name: &str, tag: u8) -> Result<&'a Rec, String> {
    let r = d.get(name).ok_or(format!("missing record {}", name))?;
    if r.tag != tag {
        return Err(format!("wrong type for {}", name));
    }
    Ok(r)
}
fn getf(d: &HashMap<String, Rec>, name: &str) -> Result<Vec<f32>, String> {
    Ok(get(d, name, TAG_F32)?.f.clone())
}
fn geti(d: &HashMap<String, Rec>, name: &str) -> Result<Vec<i32>, String> {
    Ok(get(d, name, TAG_I32)?.i.clone())
}

fn build_model(d: &HashMap<String, Rec>, mutate: Mutate) -> Result<Model, String> {
    for r in d.values() {
        if r.tag == TAG_F32 && !r.f.iter().all(|x| x.is_finite()) {
            return Err(format!("non-finite value in {}", r.name));
        }
    }
    let c = geti(d, "cfg")?;
    if c.len() != 13 {
        return Err("cfg length".into());
    }
    if c.iter().any(|&x| x < 0) {
        return Err("negative cfg".into());
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
        let p = format!("inner.L_level.layers.{}", l);
        layers.push(Layer {
            wqkv: getf(d, &format!("{}.self_attn.qkv_proj.weight", p))?,
            wo: getf(d, &format!("{}.self_attn.o_proj.weight", p))?,
            wgu: getf(d, &format!("{}.mlp.gate_up_proj.weight", p))?,
            wdown: getf(d, &format!("{}.mlp.down_proj.weight", p))?,
        });
    }
    let pos = c[10];
    Ok(Model {
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
        mutate,
    })
}

// y[r,o] = sum_i x[r,i]*W[o,i] (+ b[o]); acc from +0, i increasing (rev: decreasing, control m1 only)
fn linear(x: &[f32], rows: usize, nin: usize, w: &[f32], nout: usize, b: Option<&[f32]>, rev: bool) -> Vec<f32> {
    let mut y = vec![0.0f32; rows * nout];
    for r in 0..rows {
        let xo = r * nin;
        for o in 0..nout {
            let wo = o * nin;
            let mut acc = 0.0f32;
            if rev {
                for i in (0..nin).rev() {
                    acc = acc + x[xo + i] * w[wo + i];
                }
            } else {
                for i in 0..nin {
                    acc = acc + x[xo + i] * w[wo + i];
                }
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
    assert_eq!(a.len(), b.len());
    a.iter().zip(b.iter()).map(|(x, y)| x + y).collect()
}

fn silu(x: f32) -> f32 {
    x * (1.0f32 / (1.0f32 + exp_det(-x)))
}

fn rope(m: &Model, q: &[f32]) -> Vec<f32> {
    let hd = m.hd;
    let half = hd / 2;
    let mut y = vec![0.0f32; q.len()];
    let nrow = q.len() / hd;
    for row in 0..nrow {
        let s = row % m.s;
        for d in 0..hd {
            let x = q[row * hd + d];
            let rh = if d < half { -q[row * hd + d + half] } else { q[row * hd + d - half] };
            let c = m.cos[s * hd + d];
            let sn = m.sin[s * hd + d];
            let a = x * c;
            let bb = rh * sn;
            y[row * hd + d] = a + bb;
        }
    }
    y
}

fn attention(m: &Model, l: &Layer, h: &[f32], first_layer: bool) -> Vec<f32> {
    let (b, s, hh, nh, hd) = (m.b, m.s, m.h, m.nh, m.hd);
    let qkv = linear(h, b * s, hh, &l.wqkv, 3 * hh, None, m.mutate == Mutate::LinearRev && first_layer);
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
                if m.mutate == Mutate::SoftmaxRev {
                    for j in (0..s).rev() {
                        z = z + sc[j];
                    }
                } else {
                    for j in 0..s {
                        z = z + sc[j];
                    }
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
    linear(&out, b * s, hh, &l.wo, hh, None, false)
}

fn swiglu(m: &Model, l: &Layer, x: &[f32]) -> Vec<f32> {
    let rows = m.b * m.s;
    let it = m.inter;
    let g = linear(x, rows, m.h, &l.wgu, 2 * it, None, false);
    let mut a = vec![0.0f32; rows * it];
    for r in 0..rows {
        for j in 0..it {
            a[r * it + j] = silu(g[r * 2 * it + j]) * g[r * 2 * it + it + j];
        }
    }
    linear(&a, rows, it, &l.wdown, m.h, None, false)
}

fn block(m: &Model, l: &Layer, h: &[f32], first_layer: bool) -> Vec<f32> {
    let rows = m.b * m.s;
    let t = attention(m, l, h, first_layer);
    let hs = rms_norm(&vadd(h, &t), rows, m.h, m.eps);
    let mo = swiglu(m, l, &hs);
    rms_norm(&vadd(&hs, &mo), rows, m.h, m.eps)
}

fn l_level(m: &Model, z: &[f32], inj: &[f32]) -> Vec<f32> {
    let mut h = vadd(z, inj);
    for (li, l) in m.layers.iter().enumerate() {
        h = block(m, l, &h, li == 0);
    }
    h
}

fn input_embeddings(m: &Model, tokens: &[i32]) -> Result<Vec<f32>, String> {
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

fn h_round(m: &Model, zh: Vec<f32>, zl: Vec<f32>, emb: &[f32]) -> (Vec<f32>, Vec<f32>) {
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

fn initial_carry(m: &Model) -> Carry {
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

fn act_reset(m: &Model, c: &Carry, inputs: &[i32], pid: &[i32]) -> Carry {
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

fn outputs_from_z(m: &Model, zh: &[f32]) -> Outs {
    let (b, s, h) = (m.b, m.s, m.h);
    let logits = linear(zh, b * s, h, &m.lm, m.v, None, false);
    let mut x0 = vec![0.0f32; b * h];
    for bi in 0..b {
        for k in 0..h {
            x0[bi * h + k] = zh[(bi * s) * h + k];
        }
    }
    let q = linear(&x0, b, h, &m.qw, 2, Some(&m.qb), false);
    Outs {
        logits,
        q_halt: (0..b).map(|bi| q[2 * bi]).collect(),
        q_continue: (0..b).map(|bi| q[2 * bi + 1]).collect(),
    }
}

fn act_step(m: &Model, c: &Carry, inputs: &[i32], pid: &[i32]) -> Result<(Carry, Outs), String> {
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

fn case_recs(m: &Model, case: &str, c: &Carry, o: &Outs, out: &mut Vec<Rec>) {
    let (b, s, h, v) = (m.b, m.s, m.h, m.v);
    let n = |q: &str| format!("{}.{}", case, q);
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
    Ok((geti(d, &format!("x{}.inputs", k))?, geti(d, &format!("x{}.pid", k))?))
}

fn run(d: &HashMap<String, Rec>, m: &Model) -> Result<Vec<Rec>, String> {
    let sin = geti(d, "steps.input")?;
    if sin.len() != m.nsteps {
        return Err("steps.input length".into());
    }
    let mut out = Vec::new();
    let mut c = initial_carry(m);
    let mut c1: Option<Carry> = None;
    for k in 0..m.nsteps {
        let (inp, pid) = batch_of(d, sin[k])?;
        let t0 = Instant::now();
        let (nc, o) = act_step(m, &c, &inp, &pid)?;
        eprintln!("step{} {:.6} s", k + 1, t0.elapsed().as_secs_f64());
        c = nc;
        if k == 0 {
            c1 = Some(c.clone());
        }
        case_recs(m, &format!("step{}", k + 1), &c, &o, &mut out);
    }
    let mut mc = c1.ok_or("no step 1")?;
    let sh = geti(d, "mixed.start_halted")?;
    if sh.len() != m.b {
        return Err("start_halted length".into());
    }
    mc.halted = sh.iter().map(|&x| x != 0).collect();
    let mi = geti(d, "mixed.input")?;
    let (inp, pid) = batch_of(d, *mi.first().ok_or("mixed.input empty")?)?;
    let t0 = Instant::now();
    let (nc, o) = act_step(m, &mc, &inp, &pid)?;
    eprintln!("mixed {:.6} s", t0.elapsed().as_secs_f64());
    case_recs(m, "mixed", &nc, &o, &mut out);
    Ok(out)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut mutate = Mutate::None;
    if args.len() == 5 && args[3] == "--mutate" {
        mutate = match args[4].as_str() {
            "linear_rev" => Mutate::LinearRev,
            "softmax_rev" => Mutate::SoftmaxRev,
            _ => {
                eprintln!("unknown mutation");
                std::process::exit(2);
            }
        };
    } else if args.len() != 3 {
        eprintln!("usage: trm-det BUNDLE OUT [--mutate linear_rev|softmax_rev]");
        std::process::exit(2);
    }
    let t0 = Instant::now();
    let bytes = match std::fs::read(&args[1]) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("read {}: {}", args[1], e);
            std::process::exit(2);
        }
    };
    let recs = match read_recs(&bytes, MAGIC_BUNDLE) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("bad bundle: {}", e);
            std::process::exit(2);
        }
    };
    let mut d = HashMap::new();
    for r in recs {
        d.insert(r.name.clone(), r);
    }
    let m = match build_model(&d, mutate) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("bad bundle: {}", e);
            std::process::exit(2);
        }
    };
    let out = match run(&d, &m) {
        Ok(o) => o,
        Err(e) => {
            eprintln!("bad bundle: {}", e);
            std::process::exit(2);
        }
    };
    if out.len() != 45 {
        eprintln!("internal: record count {}", out.len());
        std::process::exit(1);
    }
    let bytes = write_recs(&out, MAGIC_OUT);
    let mut f = match std::fs::File::create(&args[2]) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("create {}: {}", args[2], e);
            std::process::exit(1);
        }
    };
    if f.write_all(&bytes).is_err() {
        eprintln!("write failed");
        std::process::exit(1);
    }
    eprintln!("total {:.6} s", t0.elapsed().as_secs_f64());
}
