# TRM-type constituents on the material layer (canonical version). Port of matter/fevo.js (= evo_trm.js bit for bit,
# check_fast.js), whose header (stages 33, 35, 38-40, 45) is the specification. Two switches reproduce the earlier
# copies whose random draws differ: wp = false gives trm.js (stage 33: no inherited read-out weight wp), lineage = false
# gives trm.js / trm2.js (no founder lineage id; in evo_trm.js the id is a number of the network record, so a clone
# draws one more mutation for it, which is then overwritten by the parent's id).
# Modes: "trm", "fixed", "nogate", "noinherit", "predact", "frozen".

const EVO_D = 4; const EVO_K = 4; const N_REC = 3; const ETA = 0.05; const ERR0 = 0.05; const THETA_PI = 0.5
const MUT = 0.05; const INIT = 0.5

gauss(r) = sqrt(-2 * jslog(r() + 1e-12)) * jscos(2 * Float64(π) * r())
_mat(r, m, n, s) = [[s * gauss(r) for _ in 1:n] for _ in 1:m]

mutable struct TNet
    Wz::Vector{Vector{Float64}}; Wx::Vector{Vector{Float64}}; Wn::Vector{Vector{Float64}}; b::Vector{Float64}
    Wy::Vector{Vector{Float64}}; wa::Vector{Float64}; ba::Float64
    wp::Union{Nothing,Float64}
    z::Vector{Float64}; y::Union{Nothing,Vector{Float64}}; err::Float64
    line::Union{Nothing,Int}
end
function fresh_net(r, wp::Bool)
    Wz = _mat(r, EVO_D, EVO_D, INIT); Wx = _mat(r, EVO_D, EVO_K, INIT); Wn = _mat(r, EVO_D, EVO_D, INIT); b = _mat(r, 1, EVO_D, INIT)[1]
    Wy = _mat(r, EVO_K, EVO_D, 0.1); wa = _mat(r, 1, EVO_D, INIT)[1]
    w = wp ? INIT * gauss(r) : nothing
    TNet(Wz, Wx, Wn, b, Wy, wa, 0.0, w, zeros(EVO_D), nothing, 0.2, nothing)
end
# The JavaScript clone is JSON.parse(JSON.stringify(net)) with a reviver adding s * gauss(r) to every number except err,
# in document order: Wz, Wx, Wn, b, Wy, wa, ba, wp, z, y, (err), line.
function clone_net(c::TNet, r, s)
    mut(v::Float64) = v + s * gauss(r)
    mutv(v) = [mut(x) for x in v]
    Wz = [mutv(row) for row in c.Wz]; Wx = [mutv(row) for row in c.Wx]; Wn = [mutv(row) for row in c.Wn]; b = mutv(c.b)
    Wy = [mutv(row) for row in c.Wy]; wa = mutv(c.wa); ba = mut(c.ba); wp = c.wp === nothing ? nothing : mut(c.wp)
    z = mutv(c.z); y = c.y === nothing ? nothing : mutv(c.y)
    c.line === nothing || mut(Float64(c.line))
    TNet(Wz, Wx, Wn, b, Wy, wa, ba, wp, z, y, c.err, c.line)
end

mutable struct EvoLife
    mode::String
    w::World
    net::Vector{Union{Nothing,TNet}}
    act::Vector{Float64}
    r::Mulberry
    ctl::Ctl
end
prec(L::EvoLife, i) = 1 / (1 + L.net[i].err / ERR0)

function make_evo(mode::String, seed::Integer; reservoir = 300, W = 24, H = 24, seeds = nothing, at = (12, 12),
                  hooks = (;), actGate = 0.5, bindConst = nothing, wp = true, lineage = true)
    w = make_world(; reservoir = reservoir, W = W, H = H); r = Mulberry(seed); n = W * H
    net = Vector{Union{Nothing,TNet}}(nothing, n)
    founders = 0
    for a in (seeds === nothing ? [at] : seeds); seed!(w, a..., 1); end
    for i in 1:n
        if w.C[i] != 0; net[i] = fresh_net(r, wp); lineage && (net[i].line = founders); founders += 1; end
    end
    act = ones(n)
    L = EvoLife(mode, w, net, act, r, NOCTL)
    hdiv = get(hooks, :divide, nothing); hdeath = get(hooks, :death, nothing)
    if mode == "fixed"
        L.ctl = Ctl(on_divide = (i, j) -> (net[j] = fresh_net(r, wp); nothing), on_death = i -> (net[i] = nothing; nothing))
    else
        gated = !(mode in ("nogate", "predact", "frozen"))
        function ondiv(i, j)
            line = net[i].line
            net[j] = mode == "noinherit" ? fresh_net(r, wp) : clone_net(net[i], r, MUT)
            net[j].y = nothing; net[j].line = line
            hdiv === nothing || hdiv(i, j)
            nothing
        end
        L.ctl = Ctl(activity = i -> act[i], bind = bindConst === nothing ? nothing : (i -> Float64(bindConst)),
                    may_divide = i -> act[i] >= actGate && (!gated || prec(L, i) >= THETA_PI),
                    on_divide = ondiv, on_death = i -> (hdeath === nothing || hdeath(i); net[i] = nothing; nothing))
    end
    return L
end

function think!(L::EvoLife)
    w = L.w; A = w.A; B = w.B; net = L.net; n = nsites(w); mode = L.mode; nb = w.nb4
    zs = Union{Nothing,Vector{Float64}}[c === nothing ? nothing : copy(c.z) for c in net]
    x = zeros(EVO_K); zbar = zeros(EVO_D)
    for i in 1:n
        c = net[i]; c === nothing && continue
        x[1] = A[i] * 4; x[2] = 0 + A[nb[1, i]] + A[nb[2, i]] + A[nb[3, i]] + A[nb[4, i]]; x[3] = B[i]
        x[4] = (0 + B[nb[1, i]] + B[nb[2, i]] + B[nb[3, i]] + B[nb[4, i]]) / 4
        if c.y !== nothing
            e = 0.0
            for k in 1:EVO_K
                d = x[k] - c.y[k]; e += abs(d) / EVO_K
                if mode != "frozen"; row = c.Wy[k]; for j in 1:EVO_D; row[j] += ETA * d * c.z[j]; end; end
            end
            c.err = 0.95 * c.err + 0.05 * e
        end
        ns = [nb[m, i] for m in 1:4 if zs[nb[m, i]] !== nothing]
        fill!(zbar, 0.0)
        for j in ns, d in 1:EVO_D; zbar[d] += zs[j][d] / length(ns); end
        for _ in 1:N_REC
            z = c.z; nz = Vector{Float64}(undef, EVO_D)
            for d in 1:EVO_D
                s1 = 0.0; s2 = 0.0; s3 = 0.0; r1 = c.Wz[d]; r2 = c.Wx[d]; r3 = c.Wn[d]
                for e in 1:EVO_D; s1 = s1 + r1[e] * z[e]; end
                for e in 1:EVO_K; s2 = s2 + r2[e] * x[e]; end
                for e in 1:EVO_D; s3 = s3 + r3[e] * zbar[e]; end
                nz[d] = jstanh(c.b[d] + s1 + s2 + s3)
            end
            c.z = nz
        end
        y = Vector{Float64}(undef, EVO_K)
        for k in 1:EVO_K; s = 0.0; row = c.Wy[k]; for e in 1:EVO_D; s = s + row[e] * c.z[e]; end; y[k] = s; end
        c.y = y
        pa = mode in ("predact", "frozen") ? (c.wp === nothing ? 0.0 : c.wp) * c.y[1] : 0.0
        sa = 0.0; for e in 1:EVO_D; sa = sa + c.wa[e] * c.z[e]; end
        L.act[i] = mode == "fixed" ? 1.0 : 0.1 + 0.9 / (1 + jsexp(-(c.ba + pa + sa)))
    end
end
function step!(L::EvoLife, sources)
    L.mode != "fixed" && think!(L)
    step!(L.w, sources, L.ctl)
end

function evo_stats(L::EvoLife)
    w = L.w; n = nsites(w); c = 0; aSum = 0.0; piSum = 0.0
    for i in 1:n
        if w.C[i] != 0; c += 1; aSum += L.act[i]; L.net[i] === nothing || (piSum += prec(L, i)); end
    end
    ok(i) = w.C[i] != 0 && L.net[i] !== nothing && (L.mode == "fixed" || prec(L, i) >= THETA_PI)
    seen = falses(n); inForm = 0
    for i in 1:n
        (ok(i) && !seen[i]) || continue
        stack = [i]; comp = 0; seen[i] = true
        while !isempty(stack)
            u = pop!(stack); comp += 1
            for m in 1:4; v = w.nb4[m, u]; if ok(v) && !seen[v]; seen[v] = true; push!(stack, v); end; end
        end
        comp >= 3 && (inForm += comp)
    end
    return (count = c, activity = c > 0 ? aSum / c : 0.0, precision = c > 0 ? piSum / c : 0.0, F = c > 0 ? inForm / c : 0.0,
            bound = count_matter(w).bound)
end

# The two source patches with seasons of 500 steps (fevo.js sources); sites 1-based.
function evo_sources(w::World, t; scale = 1.0, starve = nothing)
    W = w.p.W; on = (t ÷ 500) % 2 == 0; s = Tuple{Int,Float64}[]
    (starve !== nothing && t >= starve[1] && t < starve[2]) && return s
    for (cx, cy) in ((6, 12), (18, 12)), dy in -1:1, dx in -1:1
        push!(s, ((cy + dy) * W + cx + dx + 1, (on ? 1.0 : 0.3) * w.p.SRC * scale))
    end
    return s
end
