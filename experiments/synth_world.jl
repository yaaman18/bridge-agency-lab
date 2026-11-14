# S47 §3: the synthetic world generator (discussion/specs/S47-synth-grid.md r3). Julia only (not ported to Rust).
# For world time s >= 0 (s = t - 800 after the fed raising) and patch k in {1, 2}:
#   g_k(s) = clamp(round(M + A sin(2π (s + θ_u) / P + φ_k) + σ z_{u,k}(⌊s / L⌋)), 0, 5),  φ_1 = 0, φ_2 = π, A = 2.5.
# θ_u: a uniform integer in 0..P-1 drawn from the world seed u. z_{u,k}(b): standard normal (Box-Muller) from the
# stream Mulberry(SW_Z * u + k), block b using the uniforms 2b+1 and 2b+2 of that stream. Rounding is Base.round
# (ties to even). A step with both yields 0 is kept (Q2). No use of Julia's default random numbers.
# Requires LabCore (Mulberry) to be loaded by the includer.

const SW_THETA = 104729   # stream constants of the generator (new; the world seed u enters linearly)
const SW_Z = 130363
const SW_A = 2.5
const SW_NS = 9200        # world times 0..9199 (T0 = 800, STEPS = 10000)

sw_theta(u, P) = floor(Int, P * Mulberry(SW_THETA * u + 1)())
function sw_z(u, k, nblocks)
    r = Mulberry(SW_Z * u + k); z = Vector{Float64}(undef, nblocks)
    for b in 1:nblocks
        u1 = 1.0 - r(); u2 = r()   # u1 in (0, 1]
        z[b] = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2)
    end
    return z
end
# The yields of window u at the point (P, σ, L, M) as a table ns x 2.
function synth_table(u, P, sigma, L, M; ns = SW_NS)
    th = sw_theta(u, P); Lb = L === nothing ? ns : L; nb = (ns - 1) ÷ Lb + 1
    z = (sw_z(u, 1, nb), sw_z(u, 2, nb)); phi = (0.0, pi)
    g = Matrix{Float64}(undef, ns, 2)
    for s in 0:ns-1, k in 1:2
        x = M + SW_A * sin(2.0 * pi * (s + th) / P + phi[k]) + (sigma == 0 ? 0.0 : sigma * z[k][s ÷ Lb + 1])
        g[s+1, k] = clamp(round(x), 0.0, 5.0)
    end
    return g
end
# The SCHED function for body_org_run (world time s, patch k).
function synth_sched(u, P, sigma, L, M; ns = SW_NS)
    g = synth_table(u, P, sigma, L, M; ns = ns)
    return (s, k) -> g[s+1, k]
end
