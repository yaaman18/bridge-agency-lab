# S54 §2 (discussion/specs/S54-trial-run.md r4): the inputs and the reference of the two rehearsal lives, and of the
# life of the stop-and-start rehearsal (§5).
# Seed 669; trial 1 = L2, trial 2 = L2+SF. Birth in Julia core/ (canonical; core/one_life.jl onelife_birth).
# Drives n = 0..60479: n < T0 = 800 the raising drives of the S49 comparison lives (D1: LabCore.BO_CUR), from T0 the
# synthetic world synth_sched(669, 1000, 1, 300, 2.5) at world time n - T0 (experiments/synth_world.jl), no swap.
# The stop-and-start rehearsal life: seed 627, L2, drive D1 of S49 (ol_drive("D1", n)), 60480 drives.
# Writes into DIR (default experiments/trial-data):
#   drives-669.txt                 60480 lines "g1 g2"
#   birth-669-<tag>.save           the Julia save at n = 0 (tag L2, L2SF)
#   ref-669-<tag>.sha              "n sha" for n = 0..60480 (SHA-256 of the Julia save after n drives)
#   final-669-<tag>.save           the Julia save at n = 60480
#   rehearsal-drives-D1.txt, birth-627-L2-D1.save, ref-627-L2-D1.sha, final-627-L2-D1.save   the same for the rehearsal
#   make_trial.json                death steps and errors (reported, not predicted)
# Usage: cd experiments && julia --project=.. trial/make_trial.jl [DIR]
include(joinpath(@__DIR__, "..", "one_life_resume.jl"))
include(joinpath(@__DIR__, "..", "synth_world.jl"))
using SHA

const SEED = 669
const T0 = 800
const NDR = 60480
const DIR = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "..", "trial-data")

function trial_drives()
    sched = synth_sched(SEED, 1000, 1, 300, 2.5; ns = NDR - T0)
    dv = Vector{Tuple{Int,Int}}(undef, NDR)
    for n in 0:NDR-1
        g = n < T0 ? LabCore.BO_CUR[n+1] : [sched(n - T0, 1), sched(n - T0, 2)]
        (isinteger(g[1]) && isinteger(g[2]) && 0 <= g[1] <= 5 && 0 <= g[2] <= 5) || error("drive $n: $g")
        dv[n+1] = (Int(g[1]), Int(g[2]))
    end
    return dv
end

function walk_ref(seed, L, tag, dv)
    s = onelife_birth(seed, L); deadat = nothing; errs = 0
    write(joinpath(DIR, "birth-$tag.save"), onelife_save(s))
    open(joinpath(DIR, "ref-$tag.sha"), "w") do io
        println(io, 0, " ", bytes2hex(sha256(onelife_save(s))))
        for n in 0:NDR-1
            s, e = onelife_step(s, dv[n+1]); errs += e
            (s.dead && deadat === nothing) && (deadat = n + 1)
            println(io, n + 1, " ", bytes2hex(sha256(onelife_save(s))))
        end
    end
    write(joinpath(DIR, "final-$tag.save"), onelife_save(s))
    return (dead_at = deadat, death = s.death, errors = errs)
end

writedrives(f, dv) = open(io -> foreach(g -> println(io, g[1], " ", g[2]), dv), joinpath(DIR, f), "w")

mkpath(DIR)
dv = trial_drives()
writedrives("drives-$SEED.txt", dv)
r1 = walk_ref(SEED, LawL2, "$SEED-L2", dv)
r2 = walk_ref(SEED, LawL2SF, "$SEED-L2SF", dv)
dr = [ol_drive("D1", n) for n in 0:NDR-1]
writedrives("rehearsal-drives-D1.txt", dr)
r3 = walk_ref(627, LawL2, "627-L2-D1", dr)
both0 = count(g -> g == (0, 0), dv[T0+1:end])
js(r) = "{\"dead_at\":$(r.dead_at === nothing ? "null" : r.dead_at),\"death\":$(r.death === nothing ? "null" : r.death),\"errors\":$(r.errors)}"
out = "{\"seed\":$SEED,\"T0\":$T0,\"drives\":$NDR,\"steps_with_both_yields_0_from_T0\":$both0,\"L2\":$(js(r1)),\"L2SF\":$(js(r2)),\"rehearsal_627_L2_D1\":$(js(r3))}"
write(joinpath(DIR, "make_trial.json"), out * "\n")
println(out)
