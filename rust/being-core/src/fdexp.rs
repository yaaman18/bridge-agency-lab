//! The arithmetic of the OneLife path (S49), written out so that it does not depend on a platform libm:
//!   exp    fdlibm e_exp.c (FreeBSD msun, the algorithm of Julia's openlibm, core/jsmath.jl jsexp); f64 operations only,
//!          in the C order, no fused multiply-add.
//!   sqrt   correctly rounded (integer square root of the significand), equal to the IEEE operation Julia uses.
//!   floor  exact.
//!   hypot  core/jsmath.jl jshypot (V8's Math.hypot).
//!   min / max  Julia's Base.min / Base.max on Float64 (NaN and signed zeros included).

#[inline]
fn hi(x: f64) -> u32 {
    (x.to_bits() >> 32) as u32
}
#[inline]
fn lo(x: f64) -> u32 {
    x.to_bits() as u32
}
#[inline]
fn words(h: u32, l: u32) -> f64 {
    f64::from_bits(((h as u64) << 32) | l as u64)
}

const HALF: [f64; 2] = [0.5, -0.5];
const O_THRESHOLD: f64 = 7.09782712893383973096e+02;
const U_THRESHOLD: f64 = -7.45133219101941108420e+02;
const LN2HI: [f64; 2] = [6.93147180369123816490e-01, -6.93147180369123816490e-01];
const LN2LO: [f64; 2] = [1.90821492927058770002e-10, -1.90821492927058770002e-10];
const INVLN2: f64 = 1.44269504088896338700e+00;
const P1: f64 = 1.66666666666666019037e-01;
const P2: f64 = -2.77777777770155933842e-03;
const P3: f64 = 6.61375632143793436117e-05;
const P4: f64 = -1.65339022054652515390e-06;
const P5: f64 = 4.13813679705723846039e-08;
const HUGE: f64 = 1.0e+300;
const TWOM1000: f64 = 9.33263618503218878990e-302;
const TWO1023: f64 = 8.98846567431157953865e+307; // 0x1p1023

/// fdlibm __ieee754_exp.
pub fn exp(x0: f64) -> f64 {
    let mut x = x0;
    let mut hi_ = 0.0f64;
    let mut lo_ = 0.0f64;
    let mut k: i32 = 0;
    let mut hx = hi(x);
    let xsb = ((hx >> 31) & 1) as usize;
    hx &= 0x7fffffff;
    // non-finite argument, overflow, underflow
    if hx >= 0x40862E42 {
        if hx >= 0x7ff00000 {
            if ((hx & 0xfffff) | lo(x)) != 0 {
                return x + x;
            }
            return if xsb == 0 { x } else { 0.0 };
        }
        if x > O_THRESHOLD {
            return HUGE * HUGE;
        }
        if x < U_THRESHOLD {
            return TWOM1000 * TWOM1000;
        }
    }
    // argument reduction
    if hx > 0x3fd62e42 {
        if hx < 0x3FF0A2B2 {
            hi_ = x - LN2HI[xsb];
            lo_ = LN2LO[xsb];
            k = 1 - xsb as i32 - xsb as i32;
        } else {
            k = (INVLN2 * x + HALF[xsb]) as i32;
            let t = k as f64;
            hi_ = x - t * LN2HI[0];
            lo_ = t * LN2LO[0];
        }
        x = hi_ - lo_;
    } else if hx < 0x3e300000 {
        if HUGE + x > 1.0 {
            return 1.0 + x;
        }
    } else {
        k = 0;
    }
    // x is now in the primary range
    let t = x * x;
    let twopk = if k >= -1021 {
        words((0x3ff00000i32 + (k << 20)) as u32, 0)
    } else {
        words((0x3ff00000i32 + ((k + 1000) << 20)) as u32, 0)
    };
    let c = x - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
    if k == 0 {
        return 1.0 - ((x * c) / (c - 2.0) - x);
    }
    let y = 1.0 - ((lo_ - (x * c) / (2.0 - c)) - hi_);
    if k >= -1021 {
        if k == 1024 {
            return y * 2.0 * TWO1023;
        }
        y * twopk
    } else {
        y * twopk * TWOM1000
    }
}

/// Correctly rounded square root (round to nearest even), as the IEEE operation.
pub fn sqrt(x: f64) -> f64 {
    let b = x.to_bits();
    if x.is_nan() {
        return x + x;
    }
    if x == 0.0 {
        return x;
    }
    if x < 0.0 {
        return f64::NAN;
    }
    if x.is_infinite() {
        return x;
    }
    // x = m * 2^e with m an integer, normalised to 53 bits
    let be = ((b >> 52) & 0x7ff) as i64;
    let mut m = b & 0x000f_ffff_ffff_ffff;
    let mut e;
    if be == 0 {
        e = -1074i64;
        while m & (1u64 << 52) == 0 {
            m <<= 1;
            e -= 1;
        }
    } else {
        m |= 1u64 << 52;
        e = be - 1075;
    }
    let mut mm = m as u128;
    if e & 1 != 0 {
        mm <<= 1;
        e -= 1;
    }
    // r = isqrt(mm * 2^54), in [2^53, 2^54)
    let nn = mm << 54;
    let mut r: u128 = 0;
    let mut bit: u128 = 1u128 << 126;
    let mut rem = nn;
    while bit > rem {
        bit >>= 2;
    }
    while bit != 0 {
        if rem >= r + bit {
            rem -= r + bit;
            r = (r >> 1) + bit;
        } else {
            r >>= 1;
        }
        bit >>= 2;
    }
    // sqrt(x) = sqrt(nn) * 2^((e - 54) / 2); the result significand is r >> 1 (53 bits), rounded with r & 1 and rem
    let mut sig = (r >> 1) as u64;
    let rb = (r & 1) as u64;
    let sticky = rem != 0;
    let mut ex = (e - 54) / 2 + 1;
    if rb == 1 && (sticky || sig & 1 == 1) {
        sig += 1;
        if sig == 1u64 << 53 {
            sig >>= 1;
            ex += 1;
        }
    }
    // sig in [2^52, 2^53): value = sig * 2^ex; the result is always normal for a positive finite x
    let bexp = (ex + 52 + 1023) as u64;
    f64::from_bits((bexp << 52) | (sig & 0x000f_ffff_ffff_ffff))
}

/// Exact floor.
pub fn floor(x: f64) -> f64 {
    if x.is_nan() || x == 0.0 || x.abs() >= 4503599627370496.0 {
        return x;
    }
    let t = (x as i64) as f64;
    if t > x {
        t - 1.0
    } else if t == 0.0 && x < 0.0 {
        -0.0
    } else {
        t
    }
}

/// Julia Base.min(x::Float64, y::Float64).
#[inline]
pub fn jmin(x: f64, y: f64) -> f64 {
    let diff = x - y;
    let argmin = if diff.is_sign_negative() { x } else { y };
    if x.is_nan() || y.is_nan() {
        diff
    } else {
        argmin
    }
}
/// Julia Base.max(x::Float64, y::Float64).
#[inline]
pub fn jmax(x: f64, y: f64) -> f64 {
    let diff = x - y;
    let argmax = if diff.is_sign_negative() { y } else { x };
    if x.is_nan() || y.is_nan() {
        diff
    } else {
        argmax
    }
}

/// core/jsmath.jl jshypot.
pub fn hypot(a: f64, b: f64) -> f64 {
    let x = a.abs();
    let y = b.abs();
    if x.is_infinite() || y.is_infinite() {
        return f64::INFINITY;
    }
    if x.is_nan() || y.is_nan() {
        return f64::NAN;
    }
    let m = jmax(x, y);
    if m == 0.0 {
        return 0.0;
    }
    let mut s = 0.0f64;
    let mut comp = 0.0f64;
    for v in [x, y] {
        let n = v / m;
        let summand = n * n - comp;
        let pre = s + summand;
        comp = (pre - s) - summand;
        s = pre;
    }
    sqrt(s) * m
}
