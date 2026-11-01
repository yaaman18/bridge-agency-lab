//! The world and life loop of the app. Copy of the canonical core/life.jl (v3.7, rule bin3+idle: bin3 with the idle-first
//! choice of item 72; v3.5/v3.6 ran bin3). The saved being L is
//! the JSON record the app stores in the artifact's db (0-based indices, NaN saved as null), kept as a JSON value.
//! Not ported (as in Julia): migration of v1/v2 records.

use crate::circuit::{self, CState, Circuit, Contrast, Opts, Pend, StepOut};
use crate::json::Json;
use alloc::collections::VecDeque;
use alloc::string::String;
use alloc::vec;
use alloc::vec::Vec;
use alloc::format;

pub const RULE: &str = "bin3+idle";
/// The contrast rule and the idle-first choice of a rule name (core/life.jl RULES).
pub fn rule_spec(name: &str) -> Option<(Contrast, bool)> {
    match name {
        "bin3" => Some((Contrast::Bin3, false)),
        "bin3+idle" => Some((Contrast::Bin3, true)),
        _ => None,
    }
}
pub const AUTO_SEG: i64 = 1500;
pub const NURSERY: i64 = 400;
pub const SCHOOL: i64 = 400;
pub const BLOCK: i64 = 300;
pub const MAXGAP: i64 = 200;

pub fn season(t: i64) -> [f64; 2] {
    let c = ((t - 1) % 1000) + 1;
    if c <= 300 {
        [3.0, 2.0]
    } else if c <= 600 {
        [0.0, 5.0]
    } else {
        [5.0, 0.0]
    }
}

pub fn apply_reversal(perm: &mut [usize; 11], rev: i64) {
    *perm = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    if rev % 2 == 1 {
        circuit::cross(perm);
    }
}

/// mulberry32 on an int32 state kept as a JSON number.
pub fn draw(state: &mut Json) -> f64 {
    let mut s = (state.num() as i64 as i32) as u32;
    s = s.wrapping_add(0x6D2B79F5);
    let mut t = (s ^ (s >> 15)).wrapping_mul(s | 1);
    t = (t.wrapping_add((t ^ (t >> 7)).wrapping_mul(t | 61))) ^ t;
    *state = Json::n((s as i32) as f64);
    ((t ^ (t >> 14)) as f64) / 4294967296.0
}

fn stats0() -> Json {
    let one = || {
        Json::Obj(vec![
            ("steps".into(), Json::i(0)),
            ("calls".into(), Json::i(0)),
            ("answered".into(), Json::i(0)),
            ("gestures".into(), Json::i(0)),
            ("waiting".into(), Json::i(0)),
        ])
    };
    Json::Obj(vec![("live".into(), one()), ("replay".into(), one())])
}

fn fresh_partner() -> Json {
    Json::Obj(vec![
        ("mode".into(), Json::s("live")),
        ("rec".into(), Json::Arr(Vec::new())),
        ("rp".into(), Json::Null),
        ("brng".into(), Json::i(777)),
        ("bcond".into(), Json::s("live")),
        ("bnext".into(), Json::i(0)),
        ("stats".into(), stats0()),
        ("ignored".into(), Json::i(0)),
    ])
}

pub fn fresh_life(born: f64) -> Json {
    let b = Circuit::newborn(true, true);
    let st = CState::init(&b);
    let hist = Json::Obj(vec![
        ("sediment".into(), Json::Arr(Vec::new())),
        ("unans".into(), Json::Arr(Vec::new())),
        ("savings".into(), Json::Arr(Vec::new())),
        ("calls".into(), Json::Arr(Vec::new())),
    ]);
    Json::Obj(vec![
        ("v".into(), Json::i(3)),
        ("age".into(), Json::i(0)),
        ("wt".into(), Json::i(0)),
        ("R".into(), Json::nums(&[circuit::CAP, circuit::CAP])),
        ("active".into(), Json::bools(&st.active)),
        ("q".into(), Json::ints(&st.q)),
        ("sg".into(), Json::ints(&st.sg)),
        ("h".into(), Json::ints(&st.h)),
        ("off".into(), Json::ints(&st.off)),
        ("prev".into(), Json::bools(&st.active)),
        ("rng".into(), Json::i(20261030)),
        ("reversals".into(), Json::i(0)),
        ("stasisUntil".into(), Json::i(0)),
        ("hist".into(), hist),
        ("unansWindow".into(), Json::i(0)),
        ("callWindow".into(), Json::nums(&[0.0, 0.0])),
        ("lastAct".into(), Json::obj()),
        ("open".into(), Json::Null),
        ("pend".into(), Json::Null),
        ("fresh".into(), Json::ints(&st.fresh)),
        ("partner".into(), fresh_partner()),
        ("born".into(), Json::n(born)),
    ])
}

/// What the last step showed (life_turn.js `last`).
#[derive(Clone, Debug)]
pub struct Last {
    pub y: [f64; 3],
    pub acting: Vec<u8>,
    pub answered: Vec<bool>,
    pub call: bool,
    pub call_answered: bool,
    pub call_failed: i64,
    pub call_while_waiting: bool,
    pub gesture: i64,
    pub cond: String,
    pub formed: bool,
    pub phase: &'static str,
}

impl Last {
    pub fn to_json(&self, hide_cond: bool) -> Json {
        Json::Obj(vec![
            ("y".into(), Json::nums(&self.y)),
            ("acting".into(), Json::Arr(self.acting.iter().map(|&p| Json::i(p as i64)).collect())),
            ("answered".into(), Json::bools(&self.answered)),
            ("call".into(), Json::Bool(self.call)),
            ("callAnswered".into(), Json::Bool(self.call_answered)),
            ("callFailed".into(), Json::i(self.call_failed)),
            ("callWhileWaiting".into(), Json::Bool(self.call_while_waiting)),
            ("gesture".into(), Json::i(self.gesture)),
            ("cond".into(), if hide_cond { Json::Null } else { Json::s(&self.cond) }),
            ("formed".into(), Json::Bool(self.formed)),
            ("phase".into(), Json::s(self.phase)),
        ])
    }
}

pub struct Life {
    pub l: Json,
    pub b: Circuit,
    pub st: CState,
    pub queue: VecDeque<i64>,
    pub win: VecDeque<(Vec<bool>, Vec<i32>)>,
    pub counting: bool,
    pub counted: i64,
    pub last_cond: Option<String>,
    pub last: Option<Last>,
}

fn push_cap(v: &mut Json, x: Json, cap: usize) {
    let a = v.arr_mut();
    a.push(x);
    if a.len() > cap {
        a.remove(0);
    }
}
fn incr(v: &mut Json, by: f64) {
    *v = Json::n(v.num() + by);
}
fn nanv(a: &Json) -> Option<Vec<f64>> {
    if a.is_null() {
        None
    } else {
        Some(a.arr().iter().map(|x| x.num()).collect())
    }
}

impl Life {
    /// From a saved v3 record, or a newborn (`born` = the time of birth in ms).
    pub fn new(saved: Option<Json>, born: f64) -> Result<Life, &'static str> {
        let mut l = saved.unwrap_or_else(|| fresh_life(born));
        if l.at("v").num() != 3.0 {
            return Err("records of v1/v2 need life_turn.js migrate(), which is not ported");
        }
        let mut b = Circuit::newborn(true, true);
        if l.at("rule").str() != RULE || l.get("rule").is_none() {
            let age = l.at("age").clone();
            let mut hist = if l.at("ruleHist").is_null() { Vec::new() } else { l.at("ruleHist").arr().to_vec() };
            hist.push(Json::Arr(vec![age.clone(), Json::s(RULE)]));
            l.set("ruleHist", Json::Arr(hist));
            let prior = if l.get("rule").is_none() || l.at("rule").is_null() { None } else { rule_spec(l.at("rule").str()) };
            l.set("rule", Json::s(RULE));
            // the contrast statistics and the last acts are kept when only the choice changes (bin3 -> bin3+idle)
            let keep = prior.map_or(false, |p| p.0 == rule_spec(RULE).unwrap().0) && l.get("lastM").map_or(false, |x| !x.is_null());
            if !keep {
                l.set("cOn", Json::Null);
                l.set("cOff", Json::Null);
                l.set("lastM", Json::Arr(b.names.iter().map(|_| age.clone()).collect()));
            }
        }
        let ints = |k: &str, l: &Json| -> Vec<i32> { l.at(k).arr().iter().map(|x| x.int() as i32).collect() };
        let bools = |k: &str, l: &Json| -> Vec<bool> { l.at(k).arr().iter().map(|x| x.truthy()).collect() };
        let age = l.at("age").int();
        let pend = l
            .at("pend")
            .arr()
            .iter()
            .map(|p| Pend {
                t: p.at("t").int(),
                e: p.at("E").arr().iter().map(|k| k.int() as usize).collect(),
                r: p.at("R").arr().iter().map(|k| k.int() as usize).collect(),
            })
            .collect();
        let fr = ints("fresh", &l);
        let st = CState {
            active: bools("active", &l),
            q: ints("q", &l),
            sg: ints("sg", &l),
            h: ints("h", &l),
            off: l.at("off").arr().iter().map(|x| x.int()).collect(),
            t: age,
            pend,
            fresh: [fr[0], fr[1], fr[2], fr[3]],
            prev: Some(bools("prev", &l)),
            c_on: nanv(l.at("cOn")),
            c_off: nanv(l.at("cOff")),
            last_m: Some(if l.at("lastM").is_null() {
                vec![age; b.names.len()]
            } else {
                l.at("lastM").arr().iter().map(|x| x.int()).collect()
            }),
        };
        apply_reversal(&mut b.perm, l.at("reversals").int());
        if !l.at("session").truthy() {
            l.set("session", Json::Obj(vec![("marks".into(), Json::Arr(Vec::new())), ("ev".into(), Json::Arr(Vec::new()))]));
        }
        Ok(Life { l, b, st, queue: VecDeque::new(), win: VecDeque::new(), counting: false, counted: 0, last_cond: None, last: None })
    }

    pub fn phase(&self) -> &'static str {
        let a = self.l.at("age").int();
        if a < NURSERY {
            "nursery"
        } else if a < NURSERY + SCHOOL {
            "school"
        } else {
            "world"
        }
    }

    fn condition(&mut self, now: i64) -> String {
        let p = self.l.at_mut("partner");
        let mode = String::from(p.at("mode").str());
        if mode != "blind" {
            return mode;
        }
        if now as f64 >= p.at("bnext").num() {
            let x = draw(p.at_mut("brng"));
            p.set("bcond", Json::s(if x < 0.5 { "live" } else { "replay" }));
            p.set("bnext", Json::i(now + BLOCK));
            p.set("rp", Json::Null);
        }
        String::from(p.at("bcond").str())
    }

    fn replay_gesture(&mut self) -> i64 {
        let p = self.l.at_mut("partner");
        let len = p.at("rec").arr().len() as i64;
        if len < 3 {
            return 0;
        }
        if p.at("rp").is_null() {
            p.set("rp", Json::Obj(vec![("j".into(), Json::i(0)), ("wait".into(), Json::i(1))]));
        }
        let wait = p.at("rp").at("wait").int() - 1;
        p.at_mut("rp").set("wait", Json::i(wait));
        if wait > 0 {
            return 0;
        }
        let j = p.at("rp").at("j").int();
        let rec = p.at("rec").arr();
        let g = rec[j as usize].arr()[1].int();
        let nj = (j + 1) % len;
        let gap = rec[nj as usize].arr()[0].int() - rec[j as usize].arr()[0].int();
        let w = if nj == 0 { 50 } else { 1.max(MAXGAP.min(gap)) };
        p.set("rp", Json::Obj(vec![("j".into(), Json::i(nj)), ("wait".into(), Json::i(w))]));
        g
    }

    fn log(&mut self, e: Json) {
        let s = self.l.at_mut("session");
        push_cap(s.at_mut("ev"), e, 12000);
    }

    pub fn live(&mut self, n: i64) {
        let (ct, idle) = rule_spec(RULE).unwrap();
        let opts = Opts { contrast: Some(ct), idle_first: idle, ..Opts::default() };
        let rec_in = |b: &Circuit, m: usize| -> Vec<usize> {
            (0..b.edges.len()).filter(|&k| b.edges[k].1 == m && b.kind[b.edges[k].0] == circuit::Kind::R).collect()
        };
        for _ in 0..n {
            let ph = self.phase();
            let age = self.l.at("age").int();
            let now = age + 1;
            let in_world = ph == "world";
            let mut y: Vec<f64> = if ph == "nursery" {
                if (age / 50) % 2 == 0 { vec![5.0, 0.0] } else { vec![0.0, 5.0] }
            } else if ph == "school" {
                if ((age - NURSERY) / 15) % 2 == 0 { vec![5.0, 2.0] } else { vec![2.0, 5.0] }
            } else if (age as f64) < self.l.at("stasisUntil").num() {
                vec![0.0, 0.0]
            } else {
                let r = self.l.at("R").arr();
                vec![r[0].num().min(5.0), r[1].num().min(5.0)]
            };
            let cond = self.condition(now);
            let g;
            if cond == "live" {
                g = self.queue.pop_front().unwrap_or(0);
                if g != 0 {
                    push_cap(self.l.at_mut("partner").at_mut("rec"), Json::Arr(vec![Json::i(now), Json::i(g)]), 2000);
                }
            } else {
                if !self.queue.is_empty() {
                    let ql = self.queue.len() as f64;
                    incr(self.l.at_mut("partner").at_mut("ignored"), ql);
                    if self.counting {
                        self.log(Json::Arr(vec![Json::s("u"), Json::i(now), Json::n(ql)]));
                    }
                    self.queue.clear();
                }
                g = self.replay_gesture();
            }
            y.push(g as f64);
            let before = self.st.q.clone();
            let o: StepOut = {
                let rng = self.l.at_mut("rng");
                let mut noise = || draw(rng);
                circuit::step(&mut self.st, &self.b, &y, &opts, &mut noise)
            };
            self.l.set("age", Json::i(self.st.t));
            let age = self.st.t;
            if in_world {
                let wt = self.l.at("wt").int() + 1;
                self.l.set("wt", Json::i(wt));
                let gr = if (age as f64) <= self.l.at("stasisUntil").num() { [0.0, 0.0] } else { season(wt) };
                let r: Vec<f64> = self.l.at("R").arr().iter().map(|x| x.num()).collect();
                let nr = [circuit::CAP.min(r[0] - o.d[0] + gr[0]), circuit::CAP.min(r[1] - o.d[1] + gr[1])];
                self.l.set("R", Json::nums(&nr));
            }
            self.win.push_back((self.st.active.clone(), self.st.q.clone()));
            if self.win.len() > circuit::WINDOW {
                self.win.pop_front();
            }
            for &m in &o.acting {
                if self.b.patch[m] > 2 {
                    continue;
                }
                let ans = o.answered_of(m).unwrap_or(false);
                if !ans {
                    incr(self.l.at_mut("unansWindow"), 1.0);
                }
                let key = format!("{}", m);
                let la = self.l.at("lastAct").get(&key).map(|x| x.num());
                let gap = la.map_or(f64::INFINITY, |a| age as f64 - a);
                if ans && gap >= 32.0 && !self.l.at("open").truthy() {
                    self.l.set(
                        "open",
                        Json::Obj(vec![("m".into(), Json::i(m as i64)), ("conf".into(), Json::i(0)), ("age".into(), Json::i(age))]),
                    );
                }
                let la = self.l.at_mut("lastAct");
                if !matches!(la, Json::Obj(_)) {
                    *la = Json::obj();
                }
                la.set(&key, Json::i(age));
            }
            if self.l.at("open").truthy() {
                let m = self.l.at("open").at("m").int() as usize;
                let ks = rec_in(&self.b, m);
                if ks.iter().any(|&k| self.st.q[k] > before[k]) {
                    incr(self.l.at_mut("open").at_mut("conf"), 1.0);
                }
                if ks.iter().any(|&k| self.st.q[k] >= circuit::SMAX) || self.l.at("open").at("conf").num() > 20.0 {
                    let entry = Json::Arr(vec![self.l.at("open").at("age").clone(), self.l.at("open").at("conf").clone()]);
                    push_cap(self.l.at_mut("hist").at_mut("savings"), entry, 300);
                    self.l.set("open", Json::Null);
                }
            }
            if o.call {
                incr(&mut self.l.at_mut("callWindow").arr_mut()[0], 1.0);
            }
            if o.call_answered {
                incr(&mut self.l.at_mut("callWindow").arr_mut()[1], 1.0);
            }
            if self.counting {
                {
                    let s = self.l.at_mut("partner").at_mut("stats").at_mut(&cond);
                    incr(s.at_mut("steps"), 1.0);
                    if o.call {
                        incr(s.at_mut("calls"), 1.0);
                    }
                    if o.call_while_waiting {
                        incr(s.at_mut("waiting"), 1.0);
                    }
                    if o.call_answered {
                        incr(s.at_mut("answered"), 1.0);
                    }
                    if g != 0 {
                        incr(s.at_mut("gestures"), 1.0);
                    }
                }
                let c = if cond == "live" { 1 } else { 0 };
                if self.last_cond.as_deref() != Some(cond.as_str()) {
                    self.log(Json::Arr(vec![Json::s("b"), Json::i(now), Json::i(c)]));
                    self.last_cond = Some(cond.clone());
                }
                let mut seg_change: Option<i64> = None;
                {
                    let s = self.l.at_mut("session");
                    if let Some(a) = s.get_mut("auto") {
                        if a.truthy() && a.at("seg").num() <= 3.0 {
                            let nn = a.at("n").int() + 1;
                            a.set("n", Json::i(nn));
                            if nn % AUTO_SEG == 0 {
                                let seg = a.at("seg").int() + 1;
                                a.set("seg", Json::i(seg));
                                seg_change = Some(seg);
                            }
                        }
                    }
                    if let Some(seg) = seg_change {
                        let label = if seg <= 3 { Json::Str(format!("{}", seg)) } else { Json::s("end") };
                        s.at_mut("marks").arr_mut().push(Json::Arr(vec![Json::i(now), label]));
                    }
                }
                if let Some(seg) = seg_change {
                    let p = self.l.at_mut("partner");
                    p.set("mode", Json::s(if seg == 3 { "blind" } else { "live" }));
                    p.set("rp", Json::Null);
                    p.set("bnext", Json::i(0));
                }
                if g != 0 {
                    self.log(Json::Arr(vec![Json::s("g"), Json::i(now), Json::i(g), Json::i(c)]));
                }
                if o.call {
                    self.log(Json::Arr(vec![Json::s("c"), Json::i(now), Json::i(if o.call_while_waiting { 1 } else { 0 }), Json::i(c)]));
                }
                if o.call_answered {
                    self.log(Json::Arr(vec![Json::s("a"), Json::i(now), Json::i(c)]));
                }
                self.counted += 1;
                if self.counted % 100 == 0 {
                    let mut e = vec![Json::s("s"), Json::i(now), Json::i(self.st.sg.iter().map(|&x| x as i64).sum())];
                    for nm in ["r9", "r10", "r11", "c3"] {
                        let k = self.b.edge(nm, "m3").unwrap();
                        e.push(Json::i(self.st.q[k] as i64));
                        e.push(Json::i(self.st.sg[k] as i64));
                    }
                    e.push(Json::i(if self.formed() { 1 } else { 0 }));
                    self.log(Json::Arr(e));
                }
            }
            if age % 100 == 0 {
                let sed: i64 = self.st.sg.iter().map(|&x| x as i64).sum();
                push_cap(self.l.at_mut("hist").at_mut("sediment"), Json::Arr(vec![Json::i(age), Json::i(sed)]), 600);
                let cw = self.l.at("callWindow").clone();
                push_cap(
                    self.l.at_mut("hist").at_mut("calls"),
                    Json::Arr(vec![Json::i(age), cw.arr()[0].clone(), cw.arr()[1].clone()]),
                    600,
                );
                self.l.set("callWindow", Json::nums(&[0.0, 0.0]));
            }
            if age % 1000 == 0 {
                let uw = self.l.at("unansWindow").clone();
                push_cap(self.l.at_mut("hist").at_mut("unans"), Json::Arr(vec![Json::i(age), uw]), 300);
                self.l.set("unansWindow", Json::i(0));
            }
            let pa: Vec<usize> = o.acting.iter().copied().filter(|&m| self.b.patch[m] <= 2).collect();
            self.last = Some(Last {
                y: [y[0], y[1], y[2]],
                acting: pa.iter().map(|&m| self.b.patch[m]).collect(),
                answered: pa.iter().map(|&m| o.answered_of(m).unwrap_or(false)).collect(),
                call: o.call,
                call_answered: o.call_answered,
                call_failed: o.call_failed,
                call_while_waiting: o.call_while_waiting,
                gesture: g,
                cond,
                formed: self.formed(),
                phase: ph,
            });
        }
        self.sync();
    }

    pub fn formed(&self) -> bool {
        let w: Vec<(Vec<bool>, Vec<i32>)> = self.win.iter().cloned().collect();
        !w.is_empty() && circuit::form(&w, &self.b)
    }

    /// Write the circuit's state back into the record (life_turn.js does this at the end of live()).
    pub fn sync(&mut self) {
        let st = &self.st;
        let l = &mut self.l;
        l.set("active", Json::bools(&st.active));
        l.set("q", Json::ints(&st.q));
        l.set("sg", Json::ints(&st.sg));
        l.set("h", Json::ints(&st.h));
        l.set("off", Json::ints(&st.off));
        l.set("prev", Json::bools(st.prev.as_ref().unwrap()));
        l.set(
            "pend",
            Json::Arr(
                st.pend
                    .iter()
                    .map(|p| {
                        Json::Obj(vec![
                            ("t".into(), Json::i(p.t)),
                            ("E".into(), Json::Arr(p.e.iter().map(|&k| Json::i(k as i64)).collect())),
                            ("R".into(), Json::Arr(p.r.iter().map(|&k| Json::i(k as i64)).collect())),
                        ])
                    })
                    .collect(),
            ),
        );
        l.set("fresh", Json::ints(&st.fresh));
        l.set("cOn", st.c_on.as_ref().map_or(Json::Null, |v| Json::nums(v)));
        l.set("cOff", st.c_off.as_ref().map_or(Json::Null, |v| Json::nums(v)));
        l.set("lastM", Json::ints(st.last_m.as_ref().unwrap()));
    }

    // ---- what the page's buttons do ----
    pub fn set_counting(&mut self, on: bool) {
        self.counting = on;
    }
    pub fn gesture(&mut self, k: i64) {
        if k >= 1 && k <= circuit::KINDS as i64 && self.queue.len() < 4 {
            self.queue.push_back(k);
        }
    }
    pub fn set_mode(&mut self, m: &str) {
        let p = self.l.at_mut("partner");
        if p.at("mode").str() == m {
            return;
        }
        p.set("mode", Json::s(m));
        p.set("rp", Json::Null);
        p.set("bnext", Json::i(0));
    }
    pub fn clear_stats(&mut self) {
        let p = self.l.at_mut("partner");
        p.set("stats", stats0());
        p.set("ignored", Json::i(0));
    }
    pub fn mark(&mut self, label: &str) {
        let age = self.l.at("age").clone();
        self.l.at_mut("session").at_mut("marks").arr_mut().push(Json::Arr(vec![age, Json::s(label)]));
    }
    pub fn start_auto(&mut self) {
        let age = self.l.at("age").clone();
        let s = self.l.at_mut("session");
        s.set("auto", Json::Obj(vec![("n".into(), Json::i(0)), ("seg".into(), Json::i(1))]));
        s.at_mut("marks").arr_mut().push(Json::Arr(vec![age, Json::s("1")]));
        let p = self.l.at_mut("partner");
        p.set("mode", Json::s("live"));
        p.set("rp", Json::Null);
        p.set("bnext", Json::i(0));
    }
    pub fn stop_auto(&mut self) {
        let age = self.l.at("age").clone();
        let s = self.l.at_mut("session");
        let go = s.get("auto").map_or(false, |a| a.truthy() && a.at("seg").num() <= 3.0);
        if go {
            s.at_mut("auto").set("seg", Json::i(9));
            s.at_mut("marks").arr_mut().push(Json::Arr(vec![age, Json::s("end")]));
            self.l.at_mut("partner").set("mode", Json::s("live"));
        }
    }
    pub fn reverse(&mut self) {
        let r = self.l.at("reversals").int() + 1;
        self.l.set("reversals", Json::i(r));
        apply_reversal(&mut self.b.perm, r);
    }
    pub fn stasis(&mut self, n: i64) {
        let a = self.l.at("age").int();
        self.l.set("stasisUntil", Json::i(a + n));
    }

    /// What the page draws (life_turn.js snapshot()).
    pub fn snapshot(&self, reveal: bool) -> Json {
        let p = self.l.at("partner");
        let hide = p.at("mode").str() == "blind" && !reveal;
        let st = &self.st;
        let pend = if st.pend.is_empty() {
            Json::Null
        } else {
            Json::Obj(vec![
                ("left".into(), Json::i(circuit::W - (self.l.at("age").int() - st.pend[0].t))),
                ("n".into(), Json::i(st.pend.len() as i64)),
            ])
        };
        let s = self.l.at("session");
        Json::Obj(vec![
            ("age".into(), self.l.at("age").clone()),
            ("wt".into(), self.l.at("wt").clone()),
            ("R".into(), self.l.at("R").clone()),
            ("q".into(), Json::ints(&st.q)),
            ("sg".into(), Json::ints(&st.sg)),
            ("active".into(), Json::bools(&st.active)),
            ("reversals".into(), self.l.at("reversals").clone()),
            ("stasis".into(), Json::Bool((self.l.at("age").num()) < self.l.at("stasisUntil").num())),
            ("last".into(), self.last.as_ref().map_or(Json::Null, |x| x.to_json(hide))),
            ("phase".into(), Json::s(self.phase())),
            ("hist".into(), self.l.at("hist").clone()),
            (
                "edges".into(),
                Json::Arr(
                    self.b
                        .edges
                        .iter()
                        .map(|e| Json::Arr(vec![Json::s(&self.b.names[e.0]), Json::s(&self.b.names[e.1])]))
                        .collect(),
                ),
            ),
            ("names".into(), Json::Arr(self.b.names.iter().map(|n| Json::s(n)).collect())),
            ("born".into(), self.l.at("born").clone()),
            ("migratedAt".into(), self.l.at("migratedAt").clone()),
            ("pend".into(), pend),
            ("fresh".into(), Json::ints(&st.fresh)),
            ("h".into(), Json::ints(&st.h)),
            (
                "partner".into(),
                Json::Obj(vec![
                    ("mode".into(), p.at("mode").clone()),
                    ("rec".into(), Json::i(p.at("rec").arr().len() as i64)),
                    ("ignored".into(), p.at("ignored").clone()),
                    ("stats".into(), if hide { Json::Null } else { p.at("stats").clone() }),
                ]),
            ),
            (
                "session".into(),
                Json::Obj(vec![
                    ("marks".into(), s.at("marks").clone()),
                    ("n".into(), Json::i(s.at("ev").arr().len() as i64)),
                    ("auto".into(), s.at("auto").clone()),
                ]),
            ),
        ])
    }
}
