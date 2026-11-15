//! onelife-run RUNFILE (S49 §2): lives one OneLife from its run file. Each line "g1 g2" of the standard input is one
//! drive: the state is stepped (being_core::onelife::step, the law from the save's law identity) and the run file is
//! replaced atomically (temporary file in the same directory, fsync, rename, fsync of the directory). A dead life
//! goes on consuming drives; its payload stays the same and only n grows. The end of the input ends the run (exit 0).
//! No birth: a missing run file is an error. Any error (the run file, a line, a drive out of {0..5}^2 on a living
//! state, n at u64::MAX, a write) stops with a non-zero exit and nothing saved; nothing is repaired or made anew.
//! The only inputs are the run file and the standard input; the only argument is the run file's place.
//! One writer (S49b §2): before the run file is read, flock(LOCK_EX | LOCK_NB) is taken on "<name>.lock" beside it
//! (made if missing; never read, written or removed; the OS drops the lock when the process ends). If it cannot be
//! taken, nothing is read or written and the exit is 9.
//! The step interval (S49c §1): after each saved step the executable sleeps INTERVAL (10 s) before it reads the next
//! drive; it never reads the time (only Duration and thread::sleep). The test build (feature fastinterval) has 0.
//! The audit (S49c §2): "<name>.audit" beside the run file, append only, one chained line per record (start, wait,
//! begin, commit, end, error, break). Its tail is read only to chain the next line; it never reaches the state, n or
//! the run file. If the audit cannot be written, the run stops (exit 10) before stepping. An audit whose last line has
//! no newline (S49d) gets one newline before its break line, so the break stands on a line of its own.
use being_core::{onelife, sha256::sha256};
use std::io::{BufRead, Write};
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};
use std::time::Duration;

/// The step interval: a constant of this executable (S49c §1, H4).
#[cfg(not(feature = "fastinterval"))]
const INTERVAL: Duration = Duration::from_secs(10);
/// The test build only (feature fastinterval): no interval.
#[cfg(feature = "fastinterval")]
const INTERVAL: Duration = Duration::from_secs(0);

const E_USAGE: i32 = 2;
const E_READ: i32 = 3;
const E_RUNFILE: i32 = 4;
const E_INPUT: i32 = 5;
const E_LINE: i32 = 6;
const E_NMAX: i32 = 7;
const E_DRIVE: i32 = 8;
const E_WRITE: i32 = 9;
const E_LOCK: i32 = 9;
const E_AUDIT: i32 = 10;

#[cfg(not(feature = "nolock"))]
extern "C" {
    fn flock(fd: i32, operation: i32) -> i32;
}
/// flock(fd, LOCK_EX | LOCK_NB) == 0 (LOCK_EX = 2, LOCK_NB = 4 on macOS and Linux).
#[cfg(not(feature = "nolock"))]
fn lock_ex_nb(f: &std::fs::File) -> bool {
    unsafe { flock(f.as_raw_fd(), 2 | 4) == 0 }
}
/// The negative control of gate L2 (feature nolock, test build only): the lock is not taken.
#[cfg(feature = "nolock")]
fn lock_ex_nb(f: &std::fs::File) -> bool {
    let _ = f.as_raw_fd();
    true
}

/// The crash points of the test build (feature crashpoint): abort at `stage` of the `k`-th save of this process.
#[cfg(feature = "crashpoint")]
struct Crash {
    stage: u32,
    k: u64,
}
#[cfg(feature = "crashpoint")]
fn crash_at(c: &Option<Crash>, stage: u32, save: u64) {
    if let Some(c) = c {
        if c.stage == stage && c.k == save {
            eprintln!("ONELIFE-CRASHPOINT stage {} save {}", stage, save);
            std::process::abort();
        }
    }
}

/// One integer token: optional '-', decimal digits. Out of the i64 range it is kept out of {0..5}.
fn int_token(t: &str) -> Option<i64> {
    let (neg, d) = match t.strip_prefix('-') {
        Some(r) => (true, r),
        None => (false, t),
    };
    if d.is_empty() || !d.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    Some(match d.parse::<i64>() {
        Ok(v) => {
            if neg {
                -v
            } else {
                v
            }
        }
        Err(_) => {
            if neg {
                i64::MIN
            } else {
                i64::MAX
            }
        }
    })
}
/// A line of exactly two integer tokens separated by ASCII white space.
fn parse_line(line: &[u8]) -> Option<[i64; 2]> {
    let s = std::str::from_utf8(line).ok()?;
    let v: Vec<&str> = s.split_ascii_whitespace().collect();
    if v.len() != 2 {
        return None;
    }
    Some([int_token(v[0])?, int_token(v[1])?])
}

fn parent_of(p: &Path) -> PathBuf {
    match p.parent() {
        Some(d) if !d.as_os_str().is_empty() => d.to_path_buf(),
        _ => PathBuf::from("."),
    }
}

/// "<name><ext>" beside the run file.
fn beside(path: &Path, ext: &str) -> PathBuf {
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(ext);
    parent_of(path).join(name)
}

/// The writer's lock: "<name>.lock" opened (made if missing, not truncated) and held for the life of the process.
fn take_lock(path: &Path) -> Result<std::fs::File, String> {
    let lp = beside(path, ".lock");
    let f = std::fs::OpenOptions::new().write(true).create(true).truncate(false).open(&lp).map_err(|e| format!("cannot open the lock file {}: {}", lp.display(), e))?;
    if lock_ex_nb(&f) {
        Ok(f)
    } else {
        Err(format!("the run file is held by another writer (lock {})", lp.display()))
    }
}

/// Temporary file in the same directory -> fsync -> rename -> fsync of the directory.
fn replace(path: &Path, bytes: &[u8], #[allow(unused)] save: u64, #[cfg(feature = "crashpoint")] c: &Option<Crash>) -> std::io::Result<()> {
    let dir = parent_of(path);
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(".tmp");
    let tmp = dir.join(name);
    #[cfg(feature = "crashpoint")]
    crash_at(c, 1, save);
    let mut f = std::fs::OpenOptions::new().write(true).create(true).truncate(true).open(&tmp)?;
    f.write_all(bytes)?;
    #[cfg(feature = "crashpoint")]
    crash_at(c, 2, save);
    f.sync_all()?;
    drop(f);
    #[cfg(feature = "crashpoint")]
    crash_at(c, 3, save);
    std::fs::rename(&tmp, path)?;
    #[cfg(feature = "crashpoint")]
    crash_at(c, 4, save);
    std::fs::File::open(&dir)?.sync_all()?;
    Ok(())
}

// ---- audit begin (S49c §2) ----
/// The start of every chain (a new audit, and every break): independent of any earlier value.
const GENESIS: &str = "0000000000000000000000000000000000000000000000000000000000000000";

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{:02x}", x)).collect()
}
fn is_hex64(t: &str) -> bool {
    t.len() == 64 && t.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
fn is_dec(t: &str) -> bool {
    // n, or n + 1 (wait, begin) up to 2^64
    !t.is_empty() && t.len() <= 20 && t.bytes().all(|b| b.is_ascii_digit()) && t.parse::<u128>().map_or(false, |v| v <= 1u128 << 64)
}
/// One audit line "<record> <prev> <hash>", hash = SHA-256 of "<record> <prev>": Some((is_break, prev, hash)) if
/// the record is well formed and the hash holds.
fn audit_line(l: &str) -> Option<(bool, &str, &str)> {
    let t: Vec<&str> = l.split(' ').collect();
    if t.len() < 4 {
        return None;
    }
    let (h, p, r) = (t[t.len() - 1], t[t.len() - 2], &t[..t.len() - 2]);
    if !is_hex64(h) || !is_hex64(p) || hex(&sha256(l[..l.len() - 65].as_bytes())) != h {
        return None;
    }
    let ok = match (r[0], r.len()) {
        ("start", 2) | ("wait", 2) | ("begin", 2) => is_dec(r[1]),
        ("commit", 3) => is_dec(r[1]) && is_hex64(r[2]),
        ("end", 3) => is_dec(r[1]) && r[2] == "eof",
        ("error", 3) => is_dec(r[1]) && is_dec(r[2]),
        ("break", 2) => matches!(r[1], "missing" | "unreadable" | "mismatch"),
        _ => false,
    };
    if ok {
        Some((r[0] == "break", p, h))
    } else {
        None
    }
}
/// The tail of the last chain of the audit's bytes (GENESIS for an empty audit); None if it does not hold. A break
/// line (prev = GENESIS) starts a new chain; every other line must carry the hash of the line before it.
fn chain_tail(b: &[u8]) -> Option<String> {
    if b.is_empty() {
        return Some(GENESIS.to_string());
    }
    if b[b.len() - 1] != b'\n' {
        return None;
    }
    let s = std::str::from_utf8(&b[..b.len() - 1]).ok()?;
    let mut prev = GENESIS.to_string();
    let mut ok = true;
    for l in s.split('\n') {
        match audit_line(l) {
            Some((true, p, h)) if p == GENESIS => {
                prev = h.to_string();
                ok = true;
            }
            Some((_, p, h)) if ok && p == prev => prev = h.to_string(),
            _ => ok = false,
        }
    }
    if ok {
        Some(prev)
    } else {
        None
    }
}

/// The audit of one process. `tail` goes only into the next line written.
struct Audit {
    f: std::fs::File,
    tail: String,
}
impl Audit {
    /// Opens "<name>.audit" for appending (made if missing). A missing, unreadable or broken audit gets a break line
    /// that starts a new chain from GENESIS.
    fn open(path: &Path) -> Result<Audit, String> {
        let ap = beside(path, ".audit");
        let (tail, brk, nl) = match std::fs::read(&ap) {
            Ok(b) => {
                // S49d: a partial last line is closed by one newline before the break
                let nl = b.last().map_or(false, |&x| x != b'\n');
                match chain_tail(&b) {
                    Some(t) => (t, None, false),
                    None => (GENESIS.to_string(), Some("mismatch"), nl),
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (GENESIS.to_string(), Some("missing"), false),
            Err(_) => (GENESIS.to_string(), Some("unreadable"), false),
        };
        let f = std::fs::OpenOptions::new().append(true).create(true).open(&ap).map_err(|e| format!("cannot open the audit {}: {}", ap.display(), e))?;
        let mut a = Audit { f, tail };
        if let Some(r) = brk {
            if nl {
                a.f.write_all(b"\n").map_err(|e| format!("writing the audit: {}", e))?;
            }
            a.log(&format!("break {}", r))?;
        }
        Ok(a)
    }
    /// Appends "<record> <tail> <hash>" in one write.
    fn log(&mut self, record: &str) -> Result<(), String> {
        let body = format!("{} {}", record, self.tail);
        let h = hex(&sha256(body.as_bytes()));
        self.f.write_all(format!("{} {}\n", body, h).as_bytes()).map_err(|e| format!("writing the audit: {}", e))?;
        self.tail = h;
        Ok(())
    }
}
/// An error stop: "error n code" is appended (best effort) and the code is the exit.
fn stop(audit: &mut Audit, n: u64, code: i32) -> i32 {
    if let Err(e) = audit.log(&format!("error {} {}", n, code)) {
        eprintln!("onelife-run: {}", e);
    }
    code
}
// ---- audit end ----

fn run() -> i32 {
    let args: Vec<String> = std::env::args().collect();
    #[cfg(not(feature = "crashpoint"))]
    if args.len() != 2 {
        eprintln!("usage: onelife-run RUNFILE");
        return E_USAGE;
    }
    #[cfg(feature = "crashpoint")]
    let crash: Option<Crash> = if args.len() == 2 {
        None
    } else if args.len() == 5 && args[2] == "--crash" {
        match (args[3].parse::<u32>(), args[4].parse::<u64>()) {
            (Ok(stage), Ok(k)) if (1..=4).contains(&stage) && k >= 1 => Some(Crash { stage, k }),
            _ => {
                eprintln!("usage: onelife-run RUNFILE [--crash STAGE(1-4) K]");
                return E_USAGE;
            }
        }
    } else {
        eprintln!("usage: onelife-run RUNFILE [--crash STAGE(1-4) K]");
        return E_USAGE;
    };
    let path = Path::new(&args[1]);
    let _lock = match take_lock(path) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("onelife-run: {}", e);
            return E_LOCK;
        }
    };
    let bytes = match std::fs::read(path) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("onelife-run: cannot read the run file: {}", e);
            return E_READ;
        }
    };
    let (mut n, _, mut s) = match onelife::run_decode(&bytes) {
        Ok(x) => x,
        Err(e) => {
            eprintln!("onelife-run: {}", e);
            return E_RUNFILE;
        }
    };
    drop(bytes);
    let mut audit = match Audit::open(path) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("onelife-run: {}", e);
            return E_AUDIT;
        }
    };
    if let Err(e) = audit.log(&format!("start {}", n)) {
        eprintln!("onelife-run: {}", e);
        return E_AUDIT;
    }
    let stdin = std::io::stdin();
    let mut input = stdin.lock();
    let mut line = Vec::new();
    let mut saves: u64 = 0;
    loop {
        if let Err(e) = audit.log(&format!("wait {}", n as u128 + 1)) {
            eprintln!("onelife-run: {}", e);
            return E_AUDIT;
        }
        line.clear();
        match input.read_until(b'\n', &mut line) {
            Ok(0) => {
                if let Err(e) = audit.log(&format!("end {} eof", n)) {
                    eprintln!("onelife-run: {}", e);
                    return E_AUDIT;
                }
                return 0;
            }
            Ok(_) => {}
            Err(e) => {
                eprintln!("onelife-run: reading the input: {}", e);
                return stop(&mut audit, n, E_INPUT);
            }
        }
        if let Err(e) = audit.log(&format!("begin {}", n as u128 + 1)) {
            eprintln!("onelife-run: {}", e);
            return E_AUDIT;
        }
        let g = match parse_line(&line) {
            Some(g) => g,
            None => {
                eprintln!("onelife-run: line {} is not two integers", n.wrapping_add(1));
                return stop(&mut audit, n, E_LINE);
            }
        };
        if n == u64::MAX {
            eprintln!("onelife-run: n is at its maximum");
            return stop(&mut audit, n, E_NMAX);
        }
        let (s2, err) = onelife::step(&s, g);
        if err {
            eprintln!("onelife-run: drive {:?} out of range at n = {}", g, n);
            return stop(&mut audit, n, E_DRIVE);
        }
        let payload = onelife::save(&s2);
        let file = onelife::run_encode(n + 1, &payload);
        saves += 1;
        #[cfg(feature = "crashpoint")]
        let r = replace(path, &file, saves, &crash);
        #[cfg(not(feature = "crashpoint"))]
        let r = replace(path, &file, saves);
        if let Err(e) = r {
            eprintln!("onelife-run: writing the run file: {}", e);
            return stop(&mut audit, n, E_WRITE);
        }
        s = s2;
        n += 1;
        if let Err(e) = audit.log(&format!("commit {} {}", n, hex(&sha256(&payload)))) {
            eprintln!("onelife-run: {}", e);
            return E_AUDIT;
        }
        std::thread::sleep(INTERVAL);
    }
}

fn main() {
    std::process::exit(run());
}
