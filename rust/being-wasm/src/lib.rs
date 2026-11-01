//! WebAssembly exports of the being for the browser page. Two instances of this module run in the page: one in a
//! Web Worker that lives the being (exports `w_*`), and one on the page that shows it (exports `v_*`). Strings go
//! in through `alloc` (the module takes ownership) and come out as a pointer to an output buffer of `out_len` bytes.
use being_core::json::{self, Json};
use being_core::life::Life;
use being_core::view::{Save, View};
use std::cell::RefCell;

struct Worker {
    life: Option<Life>,
    speed: f64,
    running: bool,
    acc: f64,
    reveal: bool,
}
thread_local! {
    static W: RefCell<Worker> = RefCell::new(Worker { life: None, speed: 5.0, running: true, acc: 0.0, reveal: false });
    static V: RefCell<View> = RefCell::new(View::new());
    static OUT: RefCell<Vec<u8>> = RefCell::new(Vec::new());
    static FRAME: RefCell<Vec<u32>> = RefCell::new(Vec::new());
}

#[no_mangle]
pub extern "C" fn alloc(n: usize) -> *mut u8 {
    let mut v = Vec::<u8>::with_capacity(n.max(1));
    let p = v.as_mut_ptr();
    std::mem::forget(v);
    p
}
fn take(p: *mut u8, n: usize) -> String {
    if n == 0 {
        return String::new();
    }
    let v = unsafe { Vec::from_raw_parts(p, n, n.max(1)) };
    String::from_utf8(v).unwrap_or_default()
}
fn out(s: String) -> *const u8 {
    OUT.with(|o| {
        *o.borrow_mut() = s.into_bytes();
        o.borrow().as_ptr()
    })
}
#[no_mangle]
pub extern "C" fn out_len() -> usize {
    OUT.with(|o| o.borrow().len())
}

// ---- the worker: lives the being ----

/// Start from the saved record (empty = a newborn). Returns the number of steps caught up for the time the page was
/// closed: elapsed seconds since savedAt times the saved speed, at most 50,000.
#[no_mangle]
pub extern "C" fn w_init(p: *mut u8, n: usize, now_ms: f64) -> f64 {
    let s = take(p, n);
    let saved = if s.is_empty() { None } else { json::parse(&s).ok() };
    W.with(|w| {
        let mut w = w.borrow_mut();
        let speed = saved.as_ref().map(|l| l.at("speed").num()).filter(|x| x.is_finite() && *x > 0.0).unwrap_or(5.0);
        let saved_at = saved.as_ref().map(|l| l.at("savedAt").num()).unwrap_or(f64::NAN);
        let catchup = if saved_at.is_finite() && saved_at > 0.0 {
            (((now_ms - saved_at) / 1000.0) * speed).max(0.0).min(50000.0) as i64
        } else {
            0
        };
        let life = match Life::new(saved, now_ms) {
            Ok(l) => l,
            Err(_) => Life::new(None, now_ms).unwrap(),
        };
        w.life = Some(life);
        w.speed = speed;
        if catchup > 0 {
            w.life.as_mut().unwrap().live(catchup);
        }
        catchup as f64
    })
}
fn with_life<R>(f: impl FnOnce(&mut Life) -> R) -> Option<R> {
    W.with(|w| w.borrow_mut().life.as_mut().map(f))
}
/// Called every 100 ms: advances speed / 10 steps (with the fraction carried over) while running.
#[no_mangle]
pub extern "C" fn w_tick() {
    W.with(|w| {
        let mut w = w.borrow_mut();
        if !w.running || w.life.is_none() {
            return;
        }
        w.acc += w.speed / 10.0;
        let n = w.acc as i64;
        if n > 0 {
            w.acc -= n as f64;
            w.life.as_mut().unwrap().live(n);
        }
    })
}
#[no_mangle]
pub extern "C" fn w_speed() -> f64 {
    W.with(|w| w.borrow().speed)
}
#[no_mangle]
pub extern "C" fn w_set_speed(v: f64) {
    W.with(|w| w.borrow_mut().speed = v.max(1.0).min(200.0))
}
#[no_mangle]
pub extern "C" fn w_running() -> i32 {
    W.with(|w| w.borrow().running as i32)
}
#[no_mangle]
pub extern "C" fn w_toggle_run() {
    W.with(|w| {
        let mut w = w.borrow_mut();
        w.running = !w.running;
    })
}
#[no_mangle]
pub extern "C" fn w_reverse() {
    with_life(|l| l.reverse());
}
#[no_mangle]
pub extern "C" fn w_stasis() {
    with_life(|l| l.stasis(60));
}
#[no_mangle]
pub extern "C" fn w_reset(now_ms: f64) {
    W.with(|w| w.borrow_mut().life = Some(Life::new(None, now_ms).unwrap()));
}
#[no_mangle]
pub extern "C" fn w_gesture(k: i32) {
    with_life(|l| l.gesture(k as i64));
}
#[no_mangle]
pub extern "C" fn w_mode(p: *mut u8, n: usize) {
    let m = take(p, n);
    if ["live", "replay", "blind"].contains(&m.as_str()) {
        with_life(|l| l.set_mode(&m));
    }
}
#[no_mangle]
pub extern "C" fn w_counting(on: i32) {
    with_life(|l| l.set_counting(on != 0));
}
#[no_mangle]
pub extern "C" fn w_reveal(on: i32) {
    W.with(|w| w.borrow_mut().reveal = on != 0);
}
#[no_mangle]
pub extern "C" fn w_clear_stats() {
    with_life(|l| l.clear_stats());
}
/// Start the session: speed 5, running, segment 1.
#[no_mangle]
pub extern "C" fn w_auto_start() {
    W.with(|w| {
        let mut w = w.borrow_mut();
        w.speed = 5.0;
        w.running = true;
        if let Some(l) = w.life.as_mut() {
            l.start_auto();
        }
    })
}
#[no_mangle]
pub extern "C" fn w_auto_stop() {
    with_life(|l| l.stop_auto());
}
#[no_mangle]
pub extern "C" fn w_snapshot() -> *const u8 {
    let s = W.with(|w| {
        let w = w.borrow();
        w.life.as_ref().map(|l| l.snapshot(w.reveal).to_string()).unwrap_or_default()
    });
    out(s)
}
/// The record to save (the being with the current speed and the time of saving).
#[no_mangle]
pub extern "C" fn w_save(now_ms: f64) -> *const u8 {
    let s = W.with(|w| {
        let w = w.borrow();
        w.life.as_ref().map_or(String::new(), |l| {
            let mut rec = l.l.clone();
            rec.set("speed", Json::n(w.speed));
            rec.set("savedAt", Json::n(now_ms));
            rec.to_string()
        })
    });
    out(s)
}

// ---- the page: shows the being ----

#[no_mangle]
pub extern "C" fn v_snapshot(p: *mut u8, n: usize) {
    if let Ok(s) = json::parse(&take(p, n)) {
        V.with(|v| v.borrow_mut().set_snapshot(s));
    }
}
/// Watching from another tab: show the record the owner saved.
#[no_mangle]
pub extern "C" fn v_watch(p: *mut u8, n: usize) {
    if let Ok(rec) = json::parse(&take(p, n)) {
        if let Ok(l) = Life::new(Some(rec), 0.0) {
            let s = l.snapshot(false);
            V.with(|v| {
                let mut v = v.borrow_mut();
                v.watching = true;
                v.save = Save::OtherTab;
                v.set_snapshot(s)
            });
        }
    }
}
#[no_mangle]
pub extern "C" fn v_flags(reveal: i32, observer: i32, dark: i32) {
    V.with(|v| {
        let mut v = v.borrow_mut();
        v.reveal = reveal != 0;
        v.observer = observer != 0;
        v.dark = dark != 0;
    })
}
/// Save status: 0 preparing, 1 saved, 2 quota, 3 failed, 4 view only, 5 browser only, 6 other tab, 7 caught up.
#[no_mangle]
pub extern "C" fn v_save(code: i32, caught: f64, ago_ms: f64) {
    V.with(|v| {
        let mut v = v.borrow_mut();
        v.save = match code {
            1 => Save::Saved,
            2 => Save::Quota,
            3 => Save::Failed,
            4 => Save::ViewOnly,
            5 => Save::BrowserOnly,
            6 => Save::OtherTab,
            7 => Save::CaughtUp,
            _ => Save::Preparing,
        };
        v.caught = caught as i64;
        v.saved_ago_ms = ago_ms;
    })
}
#[no_mangle]
pub extern "C" fn v_presence(visible: i32, focused: i32, idle_ms: f64) -> i32 {
    V.with(|v| v.borrow_mut().presence(visible != 0, focused != 0, idle_ms) as i32)
}
#[no_mangle]
pub extern "C" fn v_ui() -> *const u8 {
    out(V.with(|v| v.borrow().ui().to_string()))
}
/// Draw panel `id` (world, mem, cCall, cSed, cSav, cUn) at w x h device pixels; returns RGBA pixels (w * h * 4 bytes).
#[no_mangle]
pub extern "C" fn v_draw(p: *mut u8, n: usize, w: usize, h: usize, dpr: f64) -> *const u32 {
    let id = take(p, n);
    let f = V.with(|v| v.borrow().draw(&id, w, h, dpr));
    FRAME.with(|fr| {
        *fr.borrow_mut() = f.px;
        fr.borrow().as_ptr()
    })
}
