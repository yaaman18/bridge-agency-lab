//! Native tools for the Rust copy of the app's engine.
//!   being-tools check   runs the circuit and life scenarios of core/check (jl_scenarios.jl) and writes
//!                       core/check/out/rs-<name>.json, to be compared with the Julia outputs (compare.js rs jl).
use being_core::circuit::{self, CState, Circuit, Contrast, Opts};
use being_core::json::{self, Json};
use being_core::life::{self, Life};
use std::path::PathBuf;

fn lab() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join("..")
}
fn out(name: &str, v: &Json) {
    let dir = lab().join("core/check/out");
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join(format!("rs-{}.json", name)), v.to_string()).unwrap();
}
fn out_named(file: &str, v: &Json) {
    let dir = lab().join("core/check/out");
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join(format!("{}.json", file)), v.to_string()).unwrap();
}
fn read_json(p: PathBuf) -> Json {
    json::parse(&std::fs::read_to_string(&p).unwrap_or_else(|_| panic!("read {:?}", p))).expect("json")
}
fn load_being(f: &str) -> Json {
    let d = read_json(lab().join("memory/backup").join(f));
    match d.get("data") {
        Some(x) => x.clone(),
        None => d,
    }
}
/// JSON round trip, as the app's save and load do (NaN becomes null).
fn rt(v: &Json) -> Json {
    json::parse(&v.to_string()).unwrap()
}
fn mulberry(seed: u32) -> impl FnMut() -> f64 {
    let mut s = Json::n(seed as f64);
    move || life::draw(&mut s)
}

fn circuit_run(partner: bool, contrast: Option<Contrast>, variant: &str, scarce: bool) -> Json {
    let mut b = Circuit::newborn(partner, partner);
    let mut st = CState::init(&b);
    let mut noise = mulberry(7);
    let mut gr = mulberry(99);
    let m1 = b.unit("m1").unwrap();
    let mut r = [50.0f64, 50.0];
    let mut wt = 0i64;
    let mut trace = Vec::new();
    let mut win: Vec<(Vec<bool>, Vec<i32>)> = Vec::new();
    for t in 0..6000i64 {
        if t == 3000 {
            circuit::cross(&mut b.perm);
        }
        let mut opts = Opts { contrast, ..Opts::default() };
        match variant {
            "memory" => opts.memory = false,
            "orient" => opts.orient = false,
            "explore" => opts.explore = false,
            "fail" => opts.fail = false,
            "idle" => opts.idle_first = true,
            _ => {}
        }
        if (2000..2100).contains(&t) {
            opts.sil = vec![4, m1];
        }
        let y = if t < 400 {
            if (t / 50) % 2 == 0 { [5.0, 0.0] } else { [0.0, 5.0] }
        } else if t < 800 {
            if ((t - 400) / 15) % 2 == 0 { [5.0, 2.0] } else { [2.0, 5.0] }
        } else {
            [r[0].min(5.0), r[1].min(5.0)]
        };
        let g = if partner { if gr() < 0.1 { 1.0 + (gr() * 4.0).floor() } else { 0.0 } } else { 0.0 };
        let o = circuit::step(&mut st, &b, &[y[0], y[1], g], &opts, &mut noise);
        if t >= 800 {
            wt += 1;
            let s = if scarce && wt % 3 != 0 { [0.0, 0.0] } else { life::season(wt) };
            r = [50f64.min(r[0] - o.d[0] + s[0]), 50f64.min(r[1] - o.d[1] + s[1])];
        }
        win.push((st.active.clone(), st.q.clone()));
        if win.len() > 5 {
            win.remove(0);
        }
        let sum = |v: &Vec<i32>| Json::i(v.iter().map(|&x| x as i64).sum());
        trace.push(Json::Arr(vec![
            Json::Arr(o.acting.iter().map(|&m| Json::i(m as i64)).collect()),
            Json::nums(&o.d),
            Json::i(o.gate as i64),
            Json::i(o.call as i64),
            Json::i(o.call_answered as i64),
            Json::i(o.call_failed),
            Json::i(o.call_while_waiting as i64),
            sum(&st.q),
            sum(&st.sg),
            sum(&st.h),
            Json::i(circuit::form(&win, &b) as i64),
        ]));
    }
    let opt_nums = |v: &Option<Vec<f64>>| v.as_ref().map_or(Json::Null, |x| Json::nums(x));
    let fin = Json::Obj(vec![
        ("q".into(), Json::ints(&st.q)),
        ("sg".into(), Json::ints(&st.sg)),
        ("h".into(), Json::ints(&st.h)),
        ("off".into(), Json::ints(&st.off)),
        ("active".into(), Json::bools(&st.active)),
        ("prev".into(), Json::bools(st.prev.as_ref().unwrap())),
        (
            "pend".into(),
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
        ),
        ("fresh".into(), Json::ints(&st.fresh)),
        ("cOn".into(), opt_nums(&st.c_on)),
        ("cOff".into(), opt_nums(&st.c_off)),
        ("lastM".into(), st.last_m.as_ref().map_or(Json::Null, |v| Json::ints(v))),
        ("t".into(), Json::i(st.t)),
    ]);
    Json::Obj(vec![("trace".into(), Json::Arr(trace)), ("final".into(), fin)])
}

enum Act {
    Gesture(i64),
    StartAuto,
    Reverse,
    Stasis(i64),
    Reload,
    StopAuto,
    Mode(&'static str),
    Mark(&'static str),
    ClearStats,
}
fn script() -> Vec<(i64, Act)> {
    let mut s = Vec::new();
    let mut i = 37;
    while i <= 6000 {
        s.push((i, Act::Gesture(1 + (i % 4))));
        i += 37;
    }
    s.push((300, Act::StartAuto));
    s.push((2000, Act::Reverse));
    s.push((2500, Act::Stasis(150)));
    s.push((3000, Act::Reload));
    s.push((4600, Act::StopAuto));
    s.push((4700, Act::Mode("blind")));
    s.push((5200, Act::Mark("x")));
    s.push((5500, Act::ClearStats));
    s
}
fn life_run(start: Option<Json>, steps: i64) -> Json {
    let mut l = Life::new(start, 0.0).unwrap();
    l.set_counting(true);
    let sc = script();
    let mut trace = Vec::new();
    for i in 1..=steps {
        for (at, a) in &sc {
            if *at != i {
                continue;
            }
            match a {
                Act::Gesture(k) => l.gesture(*k),
                Act::StartAuto => l.start_auto(),
                Act::Reverse => l.reverse(),
                Act::Stasis(n) => l.stasis(*n),
                Act::Reload => {
                    l = Life::new(Some(rt(&l.l)), 0.0).unwrap();
                    l.set_counting(true);
                }
                Act::StopAuto => l.stop_auto(),
                Act::Mode(m) => l.set_mode(m),
                Act::Mark(x) => l.mark(x),
                Act::ClearStats => l.clear_stats(),
            }
        }
        l.live(1);
        trace.push(l.last.as_ref().unwrap().to_json(false));
    }
    Json::Obj(vec![("trace".into(), Json::Arr(trace)), ("L".into(), rt(&l.l))])
}

fn check() {
    let t0 = std::time::Instant::now();
    let rules: [(&str, Option<Contrast>); 7] = [
        ("null", None),
        ("sed", Some(Contrast::Sed)),
        ("learn", Some(Contrast::Learn)),
        ("learn2", Some(Contrast::Learn2)),
        ("learn3", Some(Contrast::Learn3)),
        ("bin3", Some(Contrast::Bin3)),
        ("donly", Some(Contrast::Donly)),
    ];
    for (n, c) in rules {
        out(&format!("circuit-{}-p", n), &circuit_run(true, c, "", false));
    }
    out("circuit-null-np", &circuit_run(false, None, "", false));
    out("circuit-bin3-np", &circuit_run(false, Some(Contrast::Bin3), "", false));
    for v in ["memory", "orient", "explore", "fail"] {
        out(&format!("circuit-null-no{}", v), &circuit_run(true, None, v, false));
    }
    out("circuit-bin3-nomemory", &circuit_run(true, Some(Contrast::Bin3), "memory", false));
    for (n, c) in rules.iter().filter(|(n, _)| ["bin3", "learn3", "learn2", "sed", "learn"].contains(n)) {
        out(&format!("circuit-{}-scarce", n), &circuit_run(true, *c, "", true));
    }
    out("circuit-null-idle-p", &circuit_run(true, None, "idle", false));
    out("circuit-bin3-idle-p", &circuit_run(true, Some(Contrast::Bin3), "idle", false));
    out("circuit-bin3-idle-np", &circuit_run(false, Some(Contrast::Bin3), "idle", false));
    out("circuit-bin3-idle-scarce", &circuit_run(true, Some(Contrast::Bin3), "idle", true));
    // the app's rule since v3.7 (bin3+idle); compared with the Julia scenarios *-idle
    out("life-age86642-idle", &life_run(Some(rt(&load_being("being-state-pre-learn3-age86642.json"))), 6000));
    out("life-v513-idle", &life_run(Some(rt(&load_being("being-state-session2-v513.json"))), 3000));
    out("life-v438-blind-idle", &life_run(Some(rt(&load_being("being-state-session-v438.json"))), 3000));
    out("life-fresh-idle", &life_run(None, 3000));
    out("life-from-v34-idle", &life_run(Some(read_json(lab().join("core/check/out/state-v34-after3000.json"))), 2000));
    out("life-v528-idle", &life_run(Some(rt(&read_json(lab().join("audit/in/state-v528.json")))), 3000));
    eprintln!("rust scenarios written in {} ms", t0.elapsed().as_millis());
}

/// The scenario that core/check/wasm_equiv.js runs through the WebAssembly exports (same rules, built for the
/// browser): the being saved at version 513, 3000 steps with gestures, the session, a reversal and a pause.
fn wasm_equiv() {
    let mut l = Life::new(Some(rt(&load_being("being-state-session2-v513.json"))), 0.0).unwrap();
    l.set_counting(true);
    for i in 1..=3000i64 {
        if i % 37 == 0 {
            l.gesture(1 + (i % 4));
        }
        if i == 300 {
            l.start_auto();
        }
        if i == 2000 {
            l.reverse();
        }
        if i == 2500 {
            l.stasis(60);
        }
        if i == 2700 {
            l.set_mode("blind");
        }
        l.live(1);
    }
    let mut rec = rt(&l.l);
    rec.remove("speed");
    rec.remove("savedAt");
    out_named("native-wasm-equiv", &Json::Obj(vec![("L".into(), rec), ("snap".into(), rt(&l.snapshot(true)))]));
}

fn base64(b: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut s = String::with_capacity(b.len() / 3 * 4 + 4);
    for c in b.chunks(3) {
        let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        s.push(T[(n >> 18) as usize & 63] as char);
        s.push(T[(n >> 12) as usize & 63] as char);
        s.push(if c.len() > 1 { T[(n >> 6) as usize & 63] as char } else { '=' });
        s.push(if c.len() > 2 { T[n as usize & 63] as char } else { '=' });
    }
    s
}
/// Builds app/index.html: the page's markup (app/page.head.html, app/page.body.html), the WebAssembly module
/// (base64) and the bridge (app/bridge.js).
fn page() {
    let app = lab().join("app");
    let wasm = std::fs::read(lab().join("rust/target/wasm32-unknown-unknown/release/being_wasm.wasm")).expect("build being-wasm first");
    let head = std::fs::read_to_string(app.join("page.head.html")).unwrap();
    let body = std::fs::read_to_string(app.join("page.body.html")).unwrap();
    let bridge = std::fs::read_to_string(app.join("bridge.js")).unwrap();
    let html = format!(
        "{}{}<script id=\"wasm\" type=\"application/octet-stream\">\n{}\n</script>\n<script>\n{}</script>\n",
        head, body, base64(&wasm), bridge
    );
    std::fs::write(app.join("index.html"), &html).unwrap();
    eprintln!("app/index.html: {} bytes (WebAssembly {} bytes)", html.len(), wasm.len());
}

/// The saved being lived `steps` steps by the app's Rust engine (no gestures, no buttons); writes the record.
fn run_state(input: &str, steps: i64, output: &str) {
    let rec = json::parse(&std::fs::read_to_string(input).unwrap()).expect("json");
    let mut l = Life::new(Some(rec), 0.0).expect("v3 record");
    l.live(steps);
    std::fs::write(output, l.l.to_string()).unwrap();
}
/// Noninterference of the page's read path: the being lived `steps` steps with, at every step, the snapshot (both
/// ways), the page's texts and all six panels drawn, against the being lived without them. Prints a JSON result.
fn purity(input: &str, steps: i64) {
    use being_core::view::View;
    let rec = json::parse(&std::fs::read_to_string(input).unwrap()).expect("json");
    let mut a = Life::new(Some(rec.clone()), 0.0).unwrap();
    a.live(steps);
    let mut b = Life::new(Some(rec), 0.0).unwrap();
    let mut v = View::new();
    for i in 0..steps {
        b.live(1);
        let s = b.snapshot(i % 2 == 0);
        let _ = b.snapshot(i % 2 == 1);
        v.set_snapshot(s);
        v.observer = i % 3 == 0;
        let _ = v.ui();
        if i % 50 == 0 {
            for id in ["world", "mem", "cCall", "cSed", "cSav", "cUn"] {
                let _ = v.draw(id, 300, 150, 1.0);
            }
        }
    }
    let same = a.l.to_string() == b.l.to_string();
    println!("{{\"steps\":{},\"identical\":{}}}", steps, same);
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(|s| s.as_str()) {
        Some("check") => {
            check();
            wasm_equiv();
        }
        Some("page") => page(),
        Some("run-state") => run_state(&args[2], args[3].parse().unwrap(), &args[4]),
        Some("purity") => purity(&args[2], args[3].parse().unwrap()),
        _ => eprintln!("usage: being-tools check | page | run-state IN STEPS OUT | purity IN STEPS"),
    }
}
