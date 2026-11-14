# S49 (discussion/specs/S49-rust-onelife.md): the Julia side of the OneLife check against the Rust copy
# (rust/being-core/src/onelife.rs, being-tools onelife-*). core/one_life.jl is the reference; nothing here changes it.
# Usage: julia --project=. core/check/onelife_scenarios.jl <command> ...
#   scene                                 the check scene of core/check/run.sh (seed 627, L2 and L2+SF, D3, 3000 drives;
#                                         out/onelife-drives/D3.txt, out/onelife-jl-627-<law>-D3.sha and -3000.save)
#   drives DIR N                          writes DIR/D1.txt and DIR/D3.txt (N lines "g1 g2", from ol_drive / drive_D3)
#   jobs FILE                             runs the commands of FILE (one per line), in one process:
#     life SEED LAW DRIVEFILE N PREFIX [POINTS]    birth, N drives; PREFIX.sha ("n sha" for n = 0..N), PREFIX-<n>.save
#     continue SAVE LAW DRIVEFILE FROM TO PREFIX   a save (Rust's or Julia's) loaded by onelife_load_<law> and continued
#     exp FILE                                     "x fd std" (hex) lines: jsexp(x) against fd and against std
include(joinpath(@__DIR__, "..", "..", "experiments", "one_life_death_resume.jl"))
using SHA

const OUT = joinpath(@__DIR__, "out")

readdrives(f) = [(parse(Int, split(l)[1]), parse(Int, split(l)[2])) for l in eachline(f)]

function walk(s, dv, from, to, prefix, pts)
    deadat = s.dead ? from : nothing; errs = 0
    open(prefix * ".sha", "w") do io
        put(n, s) = (b = onelife_save(s); println(io, n, " ", bytes2hex(sha256(b)));
                     (n in pts || n == to) && write("$prefix-$n.save", b))
        put(from, s)
        for n in from:to-1
            s, e = onelife_step(s, dv[n+1]); errs += e
            (s.dead && deadat === nothing) && (deadat = n + 1)
            put(n + 1, s)
        end
    end
    println("{\"dead_at\":", deadat === nothing ? "null" : deadat, ",\"death\":", s.death === nothing ? "null" : s.death,
            ",\"errors\":", errs, "}")
end

function drives(dir, N)
    open(io -> foreach(n -> (g = ol_drive("D1", n); println(io, g[1], " ", g[2])), 0:N-1), joinpath(dir, "D1.txt"), "w")
    open(io -> foreach(n -> (g = drive_D3(n); println(io, g[1], " ", g[2])), 0:N-1), joinpath(dir, "D3.txt"), "w")
end

h(s) = reinterpret(Float64, parse(UInt64, s; base = 16))
function expcheck(f)
    n = 0; bad = 0; badstd = 0; firstbad = nothing
    for l in eachline(f)
        v = split(l); x = h(v[1]); j = reinterpret(UInt64, LabCore.jsexp(x)); n += 1
        if j != parse(UInt64, v[2]; base = 16); bad += 1; firstbad === nothing && (firstbad = v[1]); end
        badstd += j != parse(UInt64, v[3]; base = 16)
    end
    println("{\"inputs\":", n, ",\"fd_mismatch\":", bad, ",\"std_mismatch\":", badstd, ",\"first_bad\":",
            firstbad === nothing ? "null" : "\"$firstbad\"", "}")
end

function command(a)
    if a[1] == "life"
        pts = length(a) >= 7 ? [parse(Int, x) for x in split(a[7], ",") if !isempty(x)] : Int[]
        walk(onelife_birth(parse(Int, a[2]), ol_law(a[3])), readdrives(a[4]), 0, parse(Int, a[5]), a[6], pts)
    elseif a[1] == "continue"
        s = ol_load(ol_law(a[3]), read(a[2]))
        walk(s, readdrives(a[4]), parse(Int, a[5]), parse(Int, a[6]), a[7], Int[])
    elseif a[1] == "exp"
        expcheck(a[2])
    else
        error("unknown command $(a[1])")
    end
end

function main(args)
    if args[1] == "scene"
        dir = joinpath(OUT, "onelife-drives"); mkpath(dir); drives(dir, 3000)
        for law in ("L2", "L2+SF")
            walk(onelife_birth(627, ol_law(law)), readdrives(joinpath(dir, "D3.txt")), 0, 3000,
                 joinpath(OUT, "onelife-jl-627-$law-D3"), Int[])
        end
    elseif args[1] == "drives"
        drives(args[2], parse(Int, args[3]))
    elseif args[1] == "jobs"
        for l in eachline(args[2]); isempty(strip(l)) || command(String.(split(l))); end
    else
        command(args)
    end
end
main(ARGS)
