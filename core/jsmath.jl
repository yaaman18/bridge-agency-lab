# Arithmetic that reproduces the JavaScript copies (Node / V8) bit for bit, so that the Julia rules (the canonical
# version since 2026-10-31) and the JavaScript copies (the app, and the history of results) can be checked against
# each other step by step.
#   exp, tanh, log  V8 uses fdlibm; Julia's openlibm (FreeBSD msun, also fdlibm) gives the same bits (checked on 400,000
#                   inputs in the ranges used, core/check/math.jl). Base.exp etc. differ in about 10% of inputs.
#   cos             V8 uses the fdlibm 5.3 kernel; openlibm's newer kernel differs in about 1% of inputs, so the fdlibm 5.3
#                   cos (with the medium-range argument reduction, |x| < 2^19 pi/2) is written out here.
#   hypot           V8's Math.hypot (normalise by the largest, Kahan sum, sqrt, scale back).
#   rng             mulberry32 as written in the JavaScript files (32-bit wrapping arithmetic).
#   tofixed         Number.prototype.toFixed followed by unary + (exact decimal rounding, ties away from zero).

const LIBM = Base.Math.libm
jsexp(x::Float64) = ccall((:exp, LIBM), Float64, (Float64,), x)
jstanh(x::Float64) = ccall((:tanh, LIBM), Float64, (Float64,), x)
jslog(x::Float64) = ccall((:log, LIBM), Float64, (Float64,), x)

_hi(x::Float64) = (reinterpret(UInt64, x) >> 32) % UInt32
function _kcos(x::Float64, y::Float64)
    C1 = 4.16666666666666019037e-02; C2 = -1.38888888888741095749e-03; C3 = 2.48015872894767294178e-05
    C4 = -2.75573143513906633035e-07; C5 = 2.08757232129817482790e-09; C6 = -1.13596475577881948265e-11
    ix = _hi(x) & 0x7fffffff
    if ix < 0x3e400000 && trunc(Int, x) == 0
        return 1.0
    end
    z = x * x; r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
    ix < 0x3FD33333 && return 1.0 - (0.5 * z - (z * r - x * y))
    qx = ix > 0x3fe90000 ? 0.28125 : reinterpret(Float64, UInt64(ix - 0x00200000) << 32)
    hz = 0.5 * z - qx; a = 1.0 - qx
    return a - (hz - (z * r - x * y))
end
function _ksin(x::Float64, y::Float64, iy::Int)
    S1 = -1.66666666666666324348e-01; S2 = 8.33333333332248946124e-03; S3 = -1.98412698298579493134e-04
    S4 = 2.75573137070700676789e-06; S5 = -2.50507602534068634195e-08; S6 = 1.58969099521155010221e-10
    ix = _hi(x) & 0x7fffffff
    if ix < 0x3e400000 && trunc(Int, x) == 0
        return x
    end
    z = x * x; v = z * x; r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
    iy == 0 ? x + v * (S1 + z * r) : x - ((z * (0.5 * y - v * r) - y) - v * S1)
end
const _NPIO2_HW = UInt32[0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C, 0x4025FDBB, 0x402921FB,
    0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C, 0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB, 0x403AB41B, 0x403C463A,
    0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C, 0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB,
    0x4046C6CB, 0x40478FDB, 0x404858EB, 0x404921FB]
function _rem_pio2(x::Float64)
    invpio2 = 6.36619772367581382433e-01; pio2_1 = 1.57079632673412561417e+00; pio2_1t = 6.07710050650619224932e-11
    pio2_2 = 6.07710050630396597660e-11; pio2_2t = 2.02226624879595063154e-21; pio2_3 = 2.02226624871116645580e-21
    pio2_3t = 8.47842766036889956997e-32
    hx = reinterpret(Int32, _hi(x)); ix = _hi(x) & 0x7fffffff
    if ix < 0x4002d97c
        if hx > 0
            z = x - pio2_1
            if ix != 0x3ff921fb
                y0 = z - pio2_1t; return 1, y0, (z - y0) - pio2_1t
            else
                z -= pio2_2; y0 = z - pio2_2t; return 1, y0, (z - y0) - pio2_2t
            end
        else
            z = x + pio2_1
            if ix != 0x3ff921fb
                y0 = z + pio2_1t; return -1, y0, (z - y0) + pio2_1t
            else
                z += pio2_2; y0 = z + pio2_2t; return -1, y0, (z - y0) + pio2_2t
            end
        end
    end
    ix <= 0x413921fb || error("jscos: argument outside the medium range (|x| < 2^19 pi/2) is not ported")
    t = abs(x); n = trunc(Int32, t * invpio2 + 0.5); fn = Float64(n)
    r = t - fn * pio2_1; w = fn * pio2_1t
    if n < 32 && ix != _NPIO2_HW[n]
        y0 = r - w
    else
        j = Int(ix >> 20); y0 = r - w; i = j - Int((_hi(y0) >> 20) & 0x7ff)
        if i > 16
            t = r; w = fn * pio2_2; r = t - w; w = fn * pio2_2t - ((t - r) - w); y0 = r - w
            i = j - Int((_hi(y0) >> 20) & 0x7ff)
            if i > 49
                t = r; w = fn * pio2_3; r = t - w; w = fn * pio2_3t - ((t - r) - w); y0 = r - w
            end
        end
    end
    y1 = (r - y0) - w
    hx < 0 ? (-Int(n), -y0, -y1) : (Int(n), y0, y1)
end
function jscos(x::Float64)
    ix = _hi(x) & 0x7fffffff
    ix <= 0x3fe921fb && return _kcos(x, 0.0)
    ix >= 0x7ff00000 && return x - x
    n, y0, y1 = _rem_pio2(x)
    k = n & 3
    k == 0 ? _kcos(y0, y1) : k == 1 ? -_ksin(y0, y1, 1) : k == 2 ? -_kcos(y0, y1) : _ksin(y0, y1, 1)
end

function jshypot(a::Float64, b::Float64)
    x = abs(a); y = abs(b)
    (isinf(x) || isinf(y)) && return Inf
    (isnan(x) || isnan(y)) && return NaN
    m = max(x, y)
    m == 0 && return 0.0
    s = 0.0; comp = 0.0
    for v in (x, y)
        n = v / m; summand = n * n - comp; pre = s + summand; comp = (pre - s) - summand; s = pre
    end
    return sqrt(s) * m
end

# mulberry32: state as the JavaScript int32 (stored as a signed integer in saved beings).
mutable struct Mulberry
    s::UInt32
end
Mulberry(seed::Integer) = Mulberry(UInt32(mod(Int64(seed), 4294967296)))
function (r::Mulberry)()
    r.s += 0x6D2B79F5
    s = r.s
    t = (s ⊻ (s >> 15)) * (s | 0x00000001)
    t = (t + (t ⊻ (t >> 7)) * (t | 0x0000003d)) ⊻ t
    return Float64(t ⊻ (t >> 14)) / 4294967296.0
end
state_int32(r::Mulberry) = Int(reinterpret(Int32, r.s))

function tofixed(x::Float64, f::Int)
    isfinite(x) || return x
    q = Rational{BigInt}(x) * big(10)^f
    n = q >= 0 ? floor(BigInt, q + 1 // 2) : -floor(BigInt, -q + 1 // 2)
    return Float64(Rational{BigInt}(n, big(10)^f))
end
