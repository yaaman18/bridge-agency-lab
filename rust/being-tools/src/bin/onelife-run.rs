//! onelife-run RUNFILE (S49 §2): lives one OneLife from its run file. Each line "g1 g2" of the standard input is one
//! drive: the state is stepped (being_core::onelife::step, the law from the save's law identity) and the run file is
//! replaced atomically (temporary file in the same directory, fsync, rename, fsync of the directory). A dead life
//! goes on consuming drives; its payload stays the same and only n grows. The end of the input ends the run (exit 0).
//! No birth: a missing run file is an error. Any error (the run file, a line, a drive out of {0..5}^2 on a living
//! state, n at u64::MAX, a write) stops with a non-zero exit and nothing saved; nothing is repaired or made anew.
//! The only inputs are the run file and the standard input; the only argument is the run file's place.
use being_core::onelife;
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};

const E_USAGE: i32 = 2;
const E_READ: i32 = 3;
const E_RUNFILE: i32 = 4;
const E_INPUT: i32 = 5;
const E_LINE: i32 = 6;
const E_NMAX: i32 = 7;
const E_DRIVE: i32 = 8;
const E_WRITE: i32 = 9;

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
    let stdin = std::io::stdin();
    let mut input = stdin.lock();
    let mut line = Vec::new();
    let mut saves: u64 = 0;
    loop {
        line.clear();
        match input.read_until(b'\n', &mut line) {
            Ok(0) => return 0,
            Ok(_) => {}
            Err(e) => {
                eprintln!("onelife-run: reading the input: {}", e);
                return E_INPUT;
            }
        }
        let g = match parse_line(&line) {
            Some(g) => g,
            None => {
                eprintln!("onelife-run: line {} is not two integers", n.wrapping_add(1));
                return E_LINE;
            }
        };
        if n == u64::MAX {
            eprintln!("onelife-run: n is at its maximum");
            return E_NMAX;
        }
        let (s2, err) = onelife::step(&s, g);
        if err {
            eprintln!("onelife-run: drive {:?} out of range at n = {}", g, n);
            return E_DRIVE;
        }
        let file = onelife::run_encode(n + 1, &onelife::save(&s2));
        saves += 1;
        #[cfg(feature = "crashpoint")]
        let r = replace(path, &file, saves, &crash);
        #[cfg(not(feature = "crashpoint"))]
        let r = replace(path, &file, saves);
        if let Err(e) = r {
            eprintln!("onelife-run: writing the run file: {}", e);
            return E_WRITE;
        }
        s = s2;
        n += 1;
    }
}

fn main() {
    std::process::exit(run());
}
