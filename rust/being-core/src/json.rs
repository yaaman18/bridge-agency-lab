//! A small JSON value, parser and writer (no_std). The saved being is the JSON record the app stores in the
//! artifact's db; it is kept as a value so that fields this version does not use survive a round trip.
//! Numbers are written as JSON.stringify writes them: integers without a fraction, others in the shortest form
//! that reads back to the same bits; NaN and infinities as null.

use alloc::string::String;
use alloc::vec::Vec;
use core::fmt::Write;

#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    pub fn obj() -> Json {
        Json::Obj(Vec::new())
    }
    pub fn get(&self, k: &str) -> Option<&Json> {
        match self {
            Json::Obj(v) => v.iter().find(|(a, _)| a == k).map(|(_, b)| b),
            _ => None,
        }
    }
    pub fn get_mut(&mut self, k: &str) -> Option<&mut Json> {
        match self {
            Json::Obj(v) => v.iter_mut().find(|(a, _)| a == k).map(|(_, b)| b),
            _ => None,
        }
    }
    /// Insert or replace a field (an existing field keeps its place).
    pub fn set(&mut self, k: &str, val: Json) {
        if let Json::Obj(v) = self {
            if let Some(slot) = v.iter_mut().find(|(a, _)| a == k) {
                slot.1 = val;
            } else {
                v.push((String::from(k), val));
            }
        }
    }
    pub fn remove(&mut self, k: &str) {
        if let Json::Obj(v) = self {
            v.retain(|(a, _)| a != k);
        }
    }
    /// The field, or Null when absent (like reading an undefined property).
    pub fn at(&self, k: &str) -> &Json {
        static NULL: Json = Json::Null;
        self.get(k).unwrap_or(&NULL)
    }
    pub fn at_mut(&mut self, k: &str) -> &mut Json {
        if self.get(k).is_none() {
            self.set(k, Json::Null);
        }
        self.get_mut(k).unwrap()
    }
    pub fn is_null(&self) -> bool {
        matches!(self, Json::Null)
    }
    /// The number (Null reads as NaN, as the app reads a saved null).
    pub fn num(&self) -> f64 {
        match self {
            Json::Num(x) => *x,
            Json::Bool(b) => {
                if *b {
                    1.0
                } else {
                    0.0
                }
            }
            _ => f64::NAN,
        }
    }
    pub fn int(&self) -> i64 {
        self.num() as i64
    }
    pub fn truthy(&self) -> bool {
        match self {
            Json::Null => false,
            Json::Bool(b) => *b,
            Json::Num(x) => *x != 0.0 && !x.is_nan(),
            Json::Str(s) => !s.is_empty(),
            _ => true,
        }
    }
    pub fn str(&self) -> &str {
        match self {
            Json::Str(s) => s.as_str(),
            _ => "",
        }
    }
    pub fn arr(&self) -> &[Json] {
        match self {
            Json::Arr(v) => v.as_slice(),
            _ => &[],
        }
    }
    pub fn arr_mut(&mut self) -> &mut Vec<Json> {
        if !matches!(self, Json::Arr(_)) {
            *self = Json::Arr(Vec::new());
        }
        match self {
            Json::Arr(v) => v,
            _ => unreachable!(),
        }
    }
    pub fn n(x: f64) -> Json {
        Json::Num(x)
    }
    pub fn i(x: i64) -> Json {
        Json::Num(x as f64)
    }
    pub fn s(x: &str) -> Json {
        Json::Str(String::from(x))
    }
    pub fn nums(v: &[f64]) -> Json {
        Json::Arr(v.iter().map(|&x| Json::Num(x)).collect())
    }
    pub fn ints<T: Copy + Into<i64>>(v: &[T]) -> Json {
        Json::Arr(v.iter().map(|&x| Json::Num(x.into() as f64)).collect())
    }
    pub fn bools(v: &[bool]) -> Json {
        Json::Arr(v.iter().map(|&x| Json::Bool(x)).collect())
    }
    pub fn to_string(&self) -> String {
        let mut s = String::new();
        write_json(self, &mut s);
        s
    }
}

pub fn write_num(x: f64, out: &mut String) {
    if !x.is_finite() {
        out.push_str("null");
    } else if x == (x as i64) as f64 && x.abs() < 9.007199254740992e15 {
        let _ = write!(out, "{}", x as i64);
    } else {
        let _ = write!(out, "{}", x);
    }
}

pub fn write_str(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

pub fn write_json(v: &Json, out: &mut String) {
    match v {
        Json::Null => out.push_str("null"),
        Json::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Json::Num(x) => write_num(*x, out),
        Json::Str(s) => write_str(s, out),
        Json::Arr(a) => {
            out.push('[');
            for (i, x) in a.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_json(x, out);
            }
            out.push(']');
        }
        Json::Obj(o) => {
            out.push('{');
            for (i, (k, x)) in o.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_str(k, out);
                out.push(':');
                write_json(x, out);
            }
            out.push('}');
        }
    }
}

struct P<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> P<'a> {
    fn ws(&mut self) {
        while self.i < self.b.len() && matches!(self.b[self.i], b' ' | b'\n' | b'\r' | b'\t') {
            self.i += 1;
        }
    }
    fn lit(&mut self, s: &str, v: Json) -> Result<Json, ()> {
        if self.b[self.i..].starts_with(s.as_bytes()) {
            self.i += s.len();
            Ok(v)
        } else {
            Err(())
        }
    }
    fn hex4(&mut self) -> Result<u32, ()> {
        if self.i + 4 > self.b.len() {
            return Err(());
        }
        let s = core::str::from_utf8(&self.b[self.i..self.i + 4]).map_err(|_| ())?;
        self.i += 4;
        u32::from_str_radix(s, 16).map_err(|_| ())
    }
    fn string(&mut self) -> Result<String, ()> {
        self.i += 1;
        let mut out = String::new();
        loop {
            if self.i >= self.b.len() {
                return Err(());
            }
            let c = self.b[self.i];
            match c {
                b'"' => {
                    self.i += 1;
                    return Ok(out);
                }
                b'\\' => {
                    self.i += 1;
                    let e = *self.b.get(self.i).ok_or(())?;
                    self.i += 1;
                    match e {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{8}'),
                        b'f' => out.push('\u{c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let mut u = self.hex4()?;
                            if (0xD800..0xDC00).contains(&u) && self.b[self.i..].starts_with(b"\\u") {
                                self.i += 2;
                                let lo = self.hex4()?;
                                u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00);
                            }
                            out.push(char::from_u32(u).unwrap_or('\u{FFFD}'));
                        }
                        _ => return Err(()),
                    }
                }
                _ => {
                    let start = self.i;
                    while self.i < self.b.len() && self.b[self.i] != b'"' && self.b[self.i] != b'\\' {
                        self.i += 1;
                    }
                    out.push_str(core::str::from_utf8(&self.b[start..self.i]).map_err(|_| ())?);
                }
            }
        }
    }
    fn value(&mut self) -> Result<Json, ()> {
        self.ws();
        let c = *self.b.get(self.i).ok_or(())?;
        match c {
            b'n' => self.lit("null", Json::Null),
            b't' => self.lit("true", Json::Bool(true)),
            b'f' => self.lit("false", Json::Bool(false)),
            b'"' => Ok(Json::Str(self.string()?)),
            b'[' => {
                self.i += 1;
                let mut v = Vec::new();
                self.ws();
                if self.b.get(self.i) == Some(&b']') {
                    self.i += 1;
                    return Ok(Json::Arr(v));
                }
                loop {
                    v.push(self.value()?);
                    self.ws();
                    match self.b.get(self.i) {
                        Some(b',') => self.i += 1,
                        Some(b']') => {
                            self.i += 1;
                            return Ok(Json::Arr(v));
                        }
                        _ => return Err(()),
                    }
                }
            }
            b'{' => {
                self.i += 1;
                let mut v = Vec::new();
                self.ws();
                if self.b.get(self.i) == Some(&b'}') {
                    self.i += 1;
                    return Ok(Json::Obj(v));
                }
                loop {
                    self.ws();
                    if self.b.get(self.i) != Some(&b'"') {
                        return Err(());
                    }
                    let k = self.string()?;
                    self.ws();
                    if self.b.get(self.i) != Some(&b':') {
                        return Err(());
                    }
                    self.i += 1;
                    let x = self.value()?;
                    v.push((k, x));
                    self.ws();
                    match self.b.get(self.i) {
                        Some(b',') => self.i += 1,
                        Some(b'}') => {
                            self.i += 1;
                            return Ok(Json::Obj(v));
                        }
                        _ => return Err(()),
                    }
                }
            }
            _ => {
                let start = self.i;
                while self.i < self.b.len() && matches!(self.b[self.i], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9') {
                    self.i += 1;
                }
                let s = core::str::from_utf8(&self.b[start..self.i]).map_err(|_| ())?;
                s.parse::<f64>().map(Json::Num).map_err(|_| ())
            }
        }
    }
}

pub fn parse(s: &str) -> Result<Json, ()> {
    let mut p = P { b: s.as_bytes(), i: 0 };
    let v = p.value()?;
    p.ws();
    if p.i != p.b.len() {
        return Err(());
    }
    Ok(v)
}
