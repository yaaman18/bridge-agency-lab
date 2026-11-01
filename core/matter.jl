# The material layer (canonical version). Port of matter/fmatter.js (= matter2.js bit for bit, check_fast.js; with no
# control = matter.js, stage 32). The header of matter/matter.js is the specification (conserved free and bound matter
# on a torus, a Lenia-like field, constituents, the meta-layer axiom A-gen, the MaterialPort). Same arithmetic in the
# same order. Sites are 1-based here: site i (Julia) = site i - 1 (JavaScript) = (y, x) with i - 1 = y W + x.

const MATTER_DEF = (W = 24, H = 24, RING = 3, MU = 0.35, SIGMA = 0.12, ADV = 0.6, DIFF = 0.08, EROSION = 0.002,
                    BIND = 0.25, CAP = 1.0, TURNOVER = 0.02, METAB = 0.004, THETA_EXIST = 0.2, THETA_DIV = 0.8, SRC = 0.06)

mutable struct Port
    reservoir::Float64
    scale::Float64
    unit::String
    inflow::Float64
    outflow::Float64
end
Port(reservoir; scale = 1.0, unit = "mu") = Port(Float64(reservoir), scale, unit, 0.0, 0.0)
function port_take!(p::Port, x::Float64)
    t = max(0.0, min(x, p.reservoir)); p.reservoir -= t; p.inflow += t; return t
end
port_give!(p::Port, x::Float64) = (p.reservoir += x; p.outflow += x; nothing)

function kernel(R::Int)
    k = Tuple{Int,Int,Float64}[]; s = 0.0
    for dy in -R:R, dx in -R:R
        r = jshypot(Float64(dx), Float64(dy)) / R
        (r == 0 || r > 1) && continue
        w = jsexp(4 - 1 / (r * (1 - r) + 1e-9))
        if w > 1e-6; push!(k, (dx, dy, w)); s += w; end
    end
    return [(dx, dy, w / s) for (dx, dy, w) in k]
end

mutable struct World
    p::typeof(MATTER_DEF)
    A::Vector{Float64}
    B::Vector{Float64}
    C::Vector{UInt8}
    K::Vector{Tuple{Int,Int,Float64}}
    port::Port
    t::Int
    born::Int
    died::Int
    spontaneous::Bool
    # index tables (fmatter.js tables())
    kIdx::Matrix{Int}; kW::Vector{Float64}; nb4::Matrix{Int}
    P::Vector{Float64}; out::Vector{Float64}; scl::Vector{Float64}
    pi::Vector{Int}; pj::Vector{Int}; pf::Vector{Float64}
end
function make_world(; reservoir = 2000.0, spontaneous = false, kw...)
    p0 = merge(MATTER_DEF, NamedTuple(kw))
    p = typeof(MATTER_DEF)(Tuple(convert(fieldtype(typeof(MATTER_DEF), k), getfield(p0, k)) for k in keys(MATTER_DEF)))
    W = p.W; H = p.H; n = W * H; K = kernel(p.RING); nk = length(K)
    site(x, y) = mod(y, H) * W + mod(x, W) + 1
    kIdx = Matrix{Int}(undef, nk, n); nb4 = Matrix{Int}(undef, 4, n)
    for y in 0:H-1, x in 0:W-1
        i = y * W + x + 1
        for (m, (dx, dy, _)) in enumerate(K); kIdx[m, i] = site(x + dx, y + dy); end
        for (m, (dx, dy)) in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1))); nb4[m, i] = site(x + dx, y + dy); end
    end
    World(p, zeros(n), zeros(n), zeros(UInt8, n), K, Port(reservoir), 0, 0, 0, spontaneous,
          kIdx, [k[3] for k in K], nb4, zeros(n), zeros(n), zeros(n), zeros(Int, 4n), zeros(Int, 4n), zeros(4n))
end
nsites(w::World) = length(w.A)

bell(u, mu, s) = 2 * jsexp(-((u - mu) * (u - mu)) / (2 * s * s)) - 1
function total(w::World)
    s = w.port.reservoir
    for i in eachindex(w.A); s += w.A[i] + w.B[i]; end
    return s
end

# Control of the constituents (matter2.js ctl): activity(i) scales the maintenance cost and binding, bind(i) (stage 45)
# the binding alone, may_divide(i) gates division, on_divide(i, j) / on_death(i) carry internal state.
Base.@kwdef struct Ctl
    activity::Union{Nothing,Function} = nothing
    bind::Union{Nothing,Function} = nothing
    may_divide::Union{Nothing,Function} = nothing
    on_divide::Union{Nothing,Function} = nothing
    on_death::Union{Nothing,Function} = nothing
end
const NOCTL = Ctl()

function step!(w::World, sources, ctl::Ctl = NOCTL)
    p = w.p; A = w.A; B = w.B; C = w.C; n = nsites(w); nk = length(w.kW); P = w.P; out = w.out; scl = w.scl
    for (i, amount) in sources; A[i] += port_take!(w.port, amount); end
    for i in 1:n
        u = 0.0
        for m in 1:nk; j = w.kIdx[m, i]; u += w.kW[m] * (A[j] + B[j]); end
        P[i] = bell(u, p.MU, p.SIGMA)
    end
    fill!(out, 0.0); np = 0; ADV = p.ADV; DIFF = p.DIFF
    for i in 1:n, m in 1:4
        j = w.nb4[m, i]
        f = ADV * A[i] * max(0.0, P[j] - P[i]) / 4 + DIFF * max(0.0, A[i] - A[j]) / 4
        if f > 0; np += 1; w.pi[np] = i; w.pj[np] = j; w.pf[np] = f; out[i] += f; end
    end
    for i in 1:n; scl[i] = out[i] > A[i] ? A[i] / out[i] : 1.0; end
    for q in 1:np; i = w.pi[q]; j = w.pj[q]; g = w.pf[q] * scl[i]; A[i] -= g; A[j] += g; end
    for i in 1:n; e = A[i] * p.EROSION; A[i] -= e; port_give!(w.port, e); end
    for i in 1:n
        C[i] == 0 && continue
        a = ctl.activity === nothing ? 1.0 : ctl.activity(i)
        m = min(B[i], p.METAB * a); B[i] -= m; port_give!(w.port, m)
        r = B[i] * p.TURNOVER; B[i] -= r; A[i] += r
        ba = ctl.bind === nothing ? a : ctl.bind(i)
        bb = min(p.CAP - B[i], p.BIND * ba * A[i]); B[i] += bb; A[i] -= bb
        if B[i] < p.THETA_EXIST
            C[i] = 0; A[i] += B[i]; B[i] = 0.0; w.died += 1
            ctl.on_death === nothing || ctl.on_death(i)
        end
    end
    order = [i for i in 1:n if C[i] != 0 && B[i] >= p.THETA_DIV && (ctl.may_divide === nothing || ctl.may_divide(i))]
    for i in order
        j = 0
        for m in 1:4
            c = w.nb4[m, i]; C[c] != 0 && continue
            (j == 0 || A[c] > A[j]) && (j = c)
        end
        j == 0 && continue
        half = B[i] / 2; B[i] -= half; B[j] += half; C[j] = 1; w.born += 1
        ctl.on_divide === nothing || ctl.on_divide(i, j)
    end
    if w.spontaneous
        for i in 1:n
            if C[i] == 0 && A[i] >= p.THETA_EXIST * 2; bb = A[i] / 2; A[i] -= bb; B[i] += bb; C[i] = 1; w.born += 1; end
        end
    end
    w.t += 1
    return w
end
# A founder group: the (2r+1)^2 sites around (cx, cy) (0-based coordinates as in the JavaScript), 0.6 mu each.
function seed!(w::World, cx, cy, r)
    W = w.p.W
    for y in cy-r:cy+r, x in cx-r:cx+r
        i = y * W + x + 1; w.B[i] = port_take!(w.port, 0.6); w.C[i] = 1
    end
end
nconstituents(w::World) = count(!=(0), w.C)
function count_matter(w::World)
    c = 0; b = 0.0
    for i in eachindex(w.C); if w.C[i] != 0; c += 1; b += w.B[i]; end; end
    return (constituents = c, bound = tofixed(b, 3))
end
