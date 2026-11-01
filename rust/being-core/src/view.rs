//! What the page shows, computed from a snapshot of the being (life.rs snapshot()): the texts and states of the
//! page's elements (`ui`), and the panels drawn into frame buffers (`draw`). The browser page only copies these
//! into the document; on dedicated hardware the same panels can go to a display.

use crate::circuit::FEATURE_NAMES;
use crate::draw::{floor, round, text_width, Frame, Rgb};
use crate::json::Json;
use alloc::format;
use alloc::string::String;
use alloc::vec;
use alloc::vec::Vec;

pub struct Palette {
    pub paper: Rgb,
    pub panel: Rgb,
    pub ink: Rgb,
    pub muted: Rgb,
    pub line: Rgb,
    pub p1: Rgb,
    pub p2: Rgb,
    pub act: Rgb,
    pub bad: Rgb,
    pub sed: Rgb,
}
pub const LIGHT: Palette = Palette {
    paper: Rgb::hex(0xedf0f2),
    panel: Rgb::hex(0xf9fafb),
    ink: Rgb::hex(0x1b2430),
    muted: Rgb::hex(0x5b6878),
    line: Rgb::hex(0xc9d1d9),
    p1: Rgb::hex(0x2f68b0),
    p2: Rgb::hex(0x23845a),
    act: Rgb::hex(0xb9790c),
    bad: Rgb::hex(0xb8382a),
    sed: Rgb::hex(0x7a4fa8),
};
pub const DARK: Palette = Palette {
    paper: Rgb::hex(0x10151b),
    panel: Rgb::hex(0x182029),
    ink: Rgb::hex(0xe1e7ee),
    muted: Rgb::hex(0x93a1b1),
    line: Rgb::hex(0x2b3643),
    p1: Rgb::hex(0x6fa5ea),
    p2: Rgb::hex(0x5dc092),
    act: Rgb::hex(0xe8b24c),
    bad: Rgb::hex(0xef6e5e),
    sed: Rgb::hex(0xb896e6),
};

/// Save status, set by the page from what the db and the browser storage answered.
#[derive(Clone, Copy, PartialEq)]
pub enum Save {
    Preparing,
    Saved,
    Quota,
    Failed,
    ViewOnly,
    BrowserOnly,
    OtherTab,
    CaughtUp,
}

pub struct View {
    pub snap: Json,
    pub reveal: bool,
    pub observer: bool,
    pub dark: bool,
    pub watching: bool,
    last_call_age: i64,
    last_ans_age: i64,
    last_call_waiting: bool,
    pub present: bool,
    absent: u8,
    pub save: Save,
    pub caught: i64,
    pub saved_ago_ms: f64,
}

pub fn thousands(x: i64) -> String {
    let s = format!("{}", x.abs());
    let mut out = String::new();
    for (i, c) in s.chars().enumerate() {
        if i > 0 && (s.len() - i) % 3 == 0 {
            out.push(',');
        }
        out.push(c);
    }
    if x < 0 {
        format!("-{}", out)
    } else {
        out
    }
}
fn fixed(x: f64, d: usize) -> String {
    format!("{:.*}", d, x)
}
fn kv(pairs: Vec<(&str, Json)>) -> Json {
    Json::Obj(pairs.into_iter().map(|(k, v)| (String::from(k), v)).collect())
}

impl View {
    pub fn new() -> View {
        View {
            snap: Json::Null,
            reveal: false,
            observer: false,
            dark: false,
            watching: false,
            last_call_age: -99,
            last_ans_age: -99,
            last_call_waiting: false,
            present: false,
            absent: 0,
            save: Save::Preparing,
            caught: 0,
            saved_ago_ms: -1.0,
        }
    }
    fn pal(&self) -> &'static Palette {
        if self.dark {
            &DARK
        } else {
            &LIGHT
        }
    }
    /// A new snapshot (the page's render()): remembers when the circuit last called and was answered.
    pub fn set_snapshot(&mut self, s: Json) {
        let age = s.at("age").int();
        let l = s.at("last");
        if l.at("call").truthy() {
            self.last_call_age = age;
            self.last_call_waiting = l.at("callWhileWaiting").truthy();
        }
        if l.at("callAnswered").truthy() {
            self.last_ans_age = age;
        }
        self.snap = s;
    }
    /// The person counts as present when the page is visible, focused, and was used within 60 s.
    pub fn presence(&mut self, visible: bool, focused: bool, idle_ms: f64) -> bool {
        self.present = visible && focused && idle_ms < 60000.0;
        self.absent = if !visible { 1 } else if !focused { 2 } else if idle_ms >= 60000.0 { 3 } else { 0 };
        self.present
    }
    fn absent_why(&self) -> &'static str {
        match self.absent {
            1 => "別のタブを見ている",
            2 => "このページに焦点がない。ページ内をクリックしてください",
            _ => "60秒操作がない",
        }
    }
    fn save_text(&self) -> String {
        let m = match self.save {
            Save::Preparing => String::from("準備中"),
            Save::Saved => String::from("保存済み"),
            Save::Quota => String::from("保存の容量が一杯です"),
            Save::Failed => String::from("保存できず（このブラウザには保存）"),
            Save::ViewOnly => String::from("見るだけ"),
            Save::BrowserOnly => String::from("このブラウザだけに保存"),
            Save::OtherTab => String::from("別のタブで生きています（見るだけ）"),
            Save::CaughtUp => format!("閉じていた間の {} 歩を追いつき計算しました", thousands(self.caught)),
        };
        if self.saved_ago_ms >= 0.0 {
            format!("{}・{}秒前", m, round(self.saved_ago_ms / 1000.0))
        } else {
            m
        }
    }

    /// Texts ("t"), classes ("c"), widths in % ("w"), disabled ("d"), hidden ("h") and the checked mode ("r").
    pub fn ui(&self) -> Json {
        let s = &self.snap;
        let mut t: Vec<(&str, Json)> = Vec::new();
        let mut c: Vec<(&str, Json)> = Vec::new();
        let mut w: Vec<(&str, Json)> = Vec::new();
        let mut d: Vec<(&str, Json)> = Vec::new();
        let mut h: Vec<(&str, Json)> = Vec::new();
        let watch = self.watching;
        for id in ["run", "stasis", "reverse", "reset", "speed", "pad1", "pad2", "pad3", "pad4", "mLive", "mReplay", "mBlind", "autoStart", "autoStop", "clearStats"] {
            d.push((id, Json::Bool(watch)));
        }
        t.push(("vSave", Json::Str(self.save_text())));
        if s.is_null() {
            return kv(vec![("t", kv(t)), ("d", kv(d))]);
        }
        let age = s.at("age").int();
        let phase = s.at("phase").str();
        let pname = match phase {
            "nursery" => "保育期",
            "school" => "学校期",
            _ => "世界",
        };
        t.push(("vAge", Json::Str(thousands(age))));
        t.push(("vPhase", Json::Str(format!("{}{}", pname, if s.at("stasis").truthy() { "（停止中）" } else { "" }))));
        let sed: i64 = s.at("sg").arr().iter().map(|x| x.int()).sum();
        t.push(("vSed", Json::Str(format!("{}", sed))));
        t.push(("vRev", Json::Str(format!("{}", s.at("reversals").int()))));
        let l = s.at("last");
        if !l.is_null() {
            let formed = l.at("formed").truthy();
            t.push(("chip1", Json::s(if formed { "形あり" } else { "形を失っている" })));
            c.push(("chip1", Json::s(if formed { "chip ok" } else { "chip bad" })));
            let acting = l.at("acting").arr();
            if !acting.is_empty() {
                let ans = l.at("answered").arr()[0].truthy();
                t.push(("chip2", Json::Str(format!("区画{}で行為 {}", acting[0].int(), if ans { "答えあり" } else { "答えなし" }))));
                c.push(("chip2", Json::s(if ans { "chip act" } else { "chip bad" })));
            } else {
                t.push(("chip2", Json::s("行為なし")));
                c.push(("chip2", Json::s("chip")));
            }
            let y = l.at("y").arr();
            t.push(("worldCap", Json::Str(format!("区画1 収量 {}　　区画2 収量 {}", y[0].int(), y[1].int()))));
            // the lamp: the circuit calls you
            let recent = age - self.last_call_age <= 1;
            let ans = age - self.last_ans_age <= 3;
            c.push(("lamp", Json::s(if ans { "dot ans" } else if recent { "dot on" } else { "dot" })));
            let pend = s.at("pend");
            let head = if ans {
                String::from("答えが届いた")
            } else if !pend.is_null() {
                if pend.at("n").int() > 1 {
                    format!("呼びかけている（{} 件が答え待ち）", pend.at("n").int())
                } else {
                    String::from("呼びかけている")
                }
            } else {
                String::from("静か")
            };
            let kind = if age - self.last_call_age <= 12 {
                if self.last_call_waiting { "・直前の呼びかけは重ねた呼びかけ" } else { "・直前の呼びかけは間を置いた呼びかけ" }
            } else {
                ""
            };
            let sub = if ans {
                String::from("あなたの身ぶりで、取っておいた予測が確かめられた")
            } else if !pend.is_null() {
                format!("いちばん古い呼びかけの残り {} 歩", pend.at("left").int().max(0))
            } else {
                String::from("いまは呼びかけていない")
            };
            t.push(("lampHead", Json::Str(head)));
            t.push(("lampSub", Json::Str(format!("{}{}", sub, kind))));
            w.push(("pendBar", Json::n(if pend.is_null() { 0.0 } else { 100.0 * (pend.at("left").num().max(0.0)) / 10.0 })));
        }
        for k in 0..4usize {
            let id = ["gs1", "gs2", "gs3", "gs4"][k];
            t.push((id, Json::Str(format!("{}・新しさ {}", k + 1, s.at("fresh").arr().get(k).map_or(0, |x| x.int())))));
        }
        let p = s.at("partner");
        let mode = p.at("mode").str();
        let mut info = format!("記録した身ぶり {} 件", p.at("rec").int());
        if p.at("ignored").int() > 0 {
            info.push_str(&format!("・流し直し中に届かなかった身ぶり {} 件", p.at("ignored").int()));
        }
        if mode == "blind" && !self.reveal {
            info.push_str("・盲検中（いまの条件は伏せている）");
        } else if !l.is_null() && l.at("cond").truthy() {
            info.push_str(if l.at("cond").str() == "live" { "・いまの条件：生" } else { "・いまの条件：流し直し" });
        }
        t.push(("statInfo", Json::Str(info)));
        h.push(("replayWarn", Json::Bool(!(mode == "replay" && p.at("rec").int() < 3))));
        let stats = p.at("stats");
        h.push(("statTable", Json::Bool(stats.is_null())));
        if !stats.is_null() {
            for (cond, pre) in [("live", "stL"), ("replay", "stR")] {
                let x = stats.at(cond);
                let (steps, calls) = (x.at("steps").num(), x.at("calls").num());
                let cell = |v: String| Json::Str(v);
                let ids = [format!("{}1", pre), format!("{}2", pre), format!("{}3", pre), format!("{}4", pre), format!("{}5", pre)];
                let vals = [
                    thousands(steps as i64),
                    if steps > 0.0 { fixed(100.0 * calls / steps, 1) } else { String::from("–") },
                    if calls > 0.0 { fixed(x.at("answered").num() / calls, 3) } else { String::from("–") },
                    if calls > 0.0 { fixed(x.at("waiting").num().max(0.0) / calls, 3) } else { String::from("–") },
                    format!("{}", x.at("gestures").int()),
                ];
                for i in 0..5 {
                    t.push((leak(&ids[i]), cell(vals[i].clone())));
                }
            }
        }
        h.push(("revealBtn", Json::Bool(mode != "blind")));
        t.push(("revealBtn", Json::s(if self.reveal { "結果を伏せる" } else { "結果を見る" })));
        let a = s.at("session").at("auto");
        let seg = if a.truthy() { a.at("seg").int() } else { 0 };
        let an = if a.truthy() { a.at("n").int() } else { 0 };
        let instr = match seg {
            1 => "段階1：呼びかけに何度でも答えてください（身ぶりは混ぜて）。",
            2 => "段階2：「間を置いた呼びかけ」にだけ答え、「重ねた呼びかけ」には答えずに待ってください。",
            3 => "段階3：自由に関わってください（いまは生か流し直しかを伏せています）。",
            4 => "終わりました。ありがとうございました。Claude に「終わった」と伝えてください。",
            9 => "途中でやめました。",
            _ => "",
        };
        t.push(("segInstr", Json::s(instr)));
        w.push(("segBar", Json::n(if (1..=3).contains(&seg) { (100 * (an % 1500)) as f64 / 1500.0 } else if seg == 4 { 100.0 } else { 0.0 })));
        let n_ev = s.at("session").at("n").int();
        let seg_info = if (1..=3).contains(&seg) {
            format!(
                "段階{}・{} / 1,500 歩・{}・記録 {} 件",
                seg,
                thousands(an % 1500),
                if self.present { String::from("記録中") } else { format!("一時停止中（{}）", self.absent_why()) },
                n_ev
            )
        } else if seg != 0 {
            format!("記録 {} 件", n_ev)
        } else {
            String::from("まだ始めていません。")
        };
        t.push(("segInfo", Json::Str(seg_info)));
        d.retain(|x| x.0 != "autoStart");
        d.push(("autoStart", Json::Bool(watch || (1..=3).contains(&seg))));
        let hist = s.at("hist");
        for (id, cv, key) in [("cCallEmpty", "cCall", "calls"), ("cSedEmpty", "cSed", "sediment"), ("cSavEmpty", "cSav", "savings"), ("cUnEmpty", "cUn", "unans")] {
            let empty = hist.at(key).arr().is_empty();
            h.push((id, Json::Bool(!empty)));
            h.push((cv, Json::Bool(empty)));
        }
        h.push(("obsNote", Json::Bool(!self.observer)));
        kv(vec![("t", kv(t)), ("c", kv(c)), ("w", kv(w)), ("d", kv(d)), ("h", kv(h)), ("r", Json::s(mode))])
    }

    /// Draw panel `id` into a frame of w x h device pixels (dpr device pixels per CSS pixel).
    pub fn draw(&self, id: &str, w: usize, h: usize, dpr: f64) -> Frame {
        let mut f = Frame::new(w, h);
        let pal = self.pal();
        f.clear(pal.panel);
        if self.snap.is_null() || w == 0 || h == 0 {
            return f;
        }
        let hist = self.snap.at("hist");
        match id {
            "world" => self.draw_world(&mut f, dpr),
            "mem" => self.draw_mem(&mut f, dpr),
            "cCall" => draw_calls(&mut f, dpr, hist.at("calls").arr(), pal),
            "cSed" => draw_series(&mut f, dpr, hist.at("sediment").arr(), pal.sed, 0, pal),
            "cSav" => draw_series(&mut f, dpr, hist.at("savings").arr(), pal.p1, 1, pal),
            "cUn" => draw_series(&mut f, dpr, hist.at("unans").arr(), pal.bad, 2, pal),
            _ => {}
        }
        f
    }

    fn draw_world(&self, f: &mut Frame, _dpr: f64) {
        let pal = self.pal();
        let s = &self.snap;
        let k = f.w as f64 / 360.0;
        let l = s.at("last");
        let act = if !l.is_null() && !l.at("acting").arr().is_empty() { l.at("acting").arr()[0].int() } else { 0 };
        let y: Vec<f64> = if l.is_null() { vec![0.0, 0.0] } else { l.at("y").arr().iter().map(|x| x.num()).collect() };
        let fs = floor(1.8 * k + 0.5).max(1.0);
        for i in 0..2usize {
            let x = 50.0 + i as f64 * 170.0;
            let (top, hh, ww) = (30.0, 150.0, 90.0);
            let col = if i == 1 { pal.p2 } else { pal.p1 };
            f.rrect_line(x * k, top * k, ww * k, hh * k, 6.0 * k, 1.5 * k, pal.line);
            let val = if s.at("phase").str() == "world" { s.at("R").arr()[i].num() } else { y[i] * 10.0 };
            let fh = hh * val / 50.0;
            f.rrect((x + 4.0) * k, (top + hh - fh + 2.0) * k, (ww - 8.0) * k, ((fh - 6.0).max(0.0)) * k, 3.0 * k, col, 0.85);
            let lab = if i == 0 { "1" } else { "2" };
            f.text((x + ww / 2.0) * k - text_width(lab, fs) / 2.0, (top - 10.0) * k - 7.0 * fs, fs, lab, pal.ink);
            let yl = format!("{}", y[i] as i64);
            f.text((x + ww / 2.0) * k - text_width(&yl, fs) / 2.0, (top + hh + 10.0) * k, fs, &yl, pal.muted);
            if act == i as i64 + 1 {
                f.rrect_line((x - 6.0) * k, (top - 6.0) * k, (ww + 12.0) * k, (hh + 12.0) * k, 9.0 * k, 3.0 * k, pal.act);
            }
        }
    }

    fn meaning(&self, i: usize) -> &'static str {
        if i >= 8 {
            return FEATURE_NAMES[i];
        }
        let swap = |i: usize| match i {
            0 => 1,
            1 => 0,
            2 => 3,
            3 => 2,
            6 => 7,
            7 => 6,
            x => x,
        };
        let j = if self.snap.at("reversals").int() % 2 == 1 { swap(i) } else { i };
        FEATURE_NAMES[j]
    }

    fn draw_mem(&self, f: &mut Frame, dpr: f64) {
        let pal = self.pal();
        let s = &self.snap;
        let names: Vec<&str> = s.at("names").arr().iter().map(|x| x.str()).collect();
        let edges: Vec<(&str, &str)> = s.at("edges").arr().iter().map(|e| (e.arr()[0].str(), e.arr()[1].str())).collect();
        let q = s.at("q").arr();
        let sg = s.at("sg").arr();
        let fs = floor(1.5 * dpr + 0.5).max(1.0);
        let lw = if self.observer { 150.0 } else { 46.0 };
        let (cw, ch, gap, head) = (64.0, 30.0, 4.0, 22.0);
        for (j, m) in ["m1", "m2", "m3"].iter().enumerate() {
            let x = lw + j as f64 * (cw + gap);
            f.text(x * dpr, (head - 8.0) * dpr - 7.0 * fs, fs, m, pal.muted);
        }
        let mut rows: Vec<String> = names.iter().filter(|n| n.starts_with('r')).map(|n| String::from(*n)).collect();
        rows.push(String::from("core"));
        for (i, r) in rows.iter().enumerate() {
            let y = head + i as f64 * (ch + gap);
            let label = if r == "core" {
                String::from("c")
            } else if self.observer {
                let idx: usize = r[1..].parse::<usize>().unwrap_or(1) - 1;
                format!("{} {}", r, self.meaning(idx))
            } else {
                r.clone()
            };
            f.text(0.0, (y + ch / 2.0) * dpr - 3.5 * fs, fs, &label, pal.muted);
            for (j, m) in ["m1", "m2", "m3"].iter().enumerate() {
                let src = if r == "core" { format!("c{}", &m[1..]) } else { r.clone() };
                let k = edges.iter().position(|e| e.0 == src && e.1 == *m);
                let x = lw + j as f64 * (cw + gap);
                f.rrect_line(x * dpr, y * dpr, cw * dpr, ch * dpr, 5.0 * dpr, 1.0 * dpr, pal.line);
                if let Some(k) = k {
                    let qq = q[k].num();
                    if qq > 0.0 {
                        f.rrect((x + 1.0) * dpr, (y + 1.0) * dpr, (cw - 2.0) * dpr, (ch - 2.0) * dpr, 4.0 * dpr, pal.p1, 0.15 + qq * 0.2);
                    }
                    let n = sg[k].int();
                    for t in 0..n {
                        let cx = x + cw - 4.0 - 3.0 - (n - 1 - t) as f64 * 8.0;
                        f.disc(cx * dpr, (y + ch - 3.0 - 3.0) * dpr, 3.0 * dpr, pal.sed);
                    }
                }
            }
        }
    }
}

fn leak(s: &str) -> &'static str {
    // ids of the stats table (10 short strings, built once per call); kept static to fit the (&str, Json) list
    match s {
        "stL1" => "stL1", "stL2" => "stL2", "stL3" => "stL3", "stL4" => "stL4", "stL5" => "stL5",
        "stR1" => "stR1", "stR2" => "stR2", "stR3" => "stR3", "stR4" => "stR4", _ => "stR5",
    }
}

struct Axes {
    k: f64,
    w: f64,
    h: f64,
    x0: f64,
    x1: f64,
    ymax: f64,
}
impl Axes {
    fn x(&self, v: f64) -> f64 {
        (34.0 + (self.w - 44.0) * (v - self.x0) / (self.x1 - self.x0)) * self.k
    }
    fn y(&self, v: f64) -> f64 {
        (self.h - 18.0 - (self.h - 30.0) * v / self.ymax) * self.k
    }
}
fn axes(f: &mut Frame, dpr: f64, x0: f64, x1: f64, ymax: f64, pal: &Palette) -> Axes {
    let a = Axes { k: dpr, w: f.w as f64 / dpr, h: f.h as f64 / dpr, x0, x1, ymax };
    let fs = floor(1.5 * dpr + 0.5).max(1.0);
    f.rect(34.0 * dpr, a.y(0.0) - 0.5 * dpr, (a.w - 42.0) * dpr, 1.0 * dpr, pal.line);
    let top = format!("{}", ymax as i64);
    f.text(4.0 * dpr, a.y(ymax) - 3.5 * fs, fs, &top, pal.muted);
    f.text(4.0 * dpr, a.y(0.0) - 3.5 * fs, fs, "0", pal.muted);
    let l0 = thousands(x0 as i64);
    f.text(34.0 * dpr, f.h as f64 - 7.0 * fs - 2.0 * dpr, fs, &l0, pal.muted);
    let l1 = thousands(x1 as i64);
    f.text(f.w as f64 - 8.0 * dpr - text_width(&l1, fs), f.h as f64 - 7.0 * fs - 2.0 * dpr, fs, &l1, pal.muted);
    a
}

fn draw_calls(f: &mut Frame, dpr: f64, pts: &[Json], pal: &Palette) {
    if pts.is_empty() {
        return;
    }
    let p = |i: usize, j: usize| pts[i].arr()[j].num();
    let x0 = p(0, 0);
    let x1 = p(pts.len() - 1, 0).max(x0 + 1.0);
    let a = axes(f, dpr, x0, x1, 100.0, pal);
    let bw = ((a.w - 44.0) / pts.len() as f64 - 0.5).min(4.0).max(1.5);
    for i in 0..pts.len() {
        let (x, c) = (a.x(p(i, 0)), p(i, 1));
        f.rect(x - bw / 2.0 * dpr, a.y(c), bw * dpr, a.y(0.0) - a.y(c), pal.act);
    }
    for i in 0..pts.len() {
        let (x, an) = (a.x(p(i, 0)), p(i, 2));
        let hh = (if an > 0.0 { 3.0 * dpr } else { 0.0 }).max(a.y(0.0) - a.y(an));
        f.rect(x - bw / 2.0 * dpr, a.y(0.0) - hh, bw * dpr, hh, pal.p2);
    }
}

/// kind 0: line, 1: dots, 2: bars.
fn draw_series(f: &mut Frame, dpr: f64, pts: &[Json], col: Rgb, kind: u8, pal: &Palette) {
    if pts.is_empty() {
        return;
    }
    let p = |i: usize, j: usize| pts[i].arr()[j].num();
    let x0 = p(0, 0);
    let x1 = p(pts.len() - 1, 0).max(x0 + 1.0);
    let ymax = (0..pts.len()).map(|i| p(i, 1)).fold(4.0f64, f64::max);
    let a = axes(f, dpr, x0, x1, ymax, pal);
    match kind {
        0 => {
            for i in 1..pts.len() {
                f.line(a.x(p(i - 1, 0)), a.y(p(i - 1, 1)), a.x(p(i, 0)), a.y(p(i, 1)), 2.0 * dpr, col);
            }
            if pts.len() == 1 {
                f.disc(a.x(p(0, 0)), a.y(p(0, 1)), dpr, col);
            }
        }
        1 => {
            for i in 0..pts.len() {
                f.disc(a.x(p(i, 0)), a.y(p(i, 1).min(ymax)), 3.0 * dpr, col);
            }
        }
        _ => {
            for i in 0..pts.len() {
                f.rect(a.x(p(i, 0)) - 2.0 * dpr, a.y(p(i, 1)), 4.0 * dpr, a.y(0.0) - a.y(p(i, 1)), col);
            }
        }
    }
}
