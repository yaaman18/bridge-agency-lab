# S48 helper (discussion/specs/S48-one-life.md r2): the drives D1 / D2, and the other process of P4 and G4 (3).
# Included by one_life_check.jl for the drives; run as a script it does one of:
#   julia --project=.. one_life_resume.jl resume <manifest.json> <out.json>
#     loads each listed save (taken from the straight run, not chained), continues to the next save point, saves, and
#     compares the bytes with the straight run's save there.
#   julia --project=.. one_life_resume.jl straight <seed> <law> <drive> <N> <rngseed> <out.json>
#     a straight run from birth; writes the SHA-256 chain of the saves after every drive (G4 (3)).
include(joinpath(@__DIR__, "..", "core", "one_life.jl"))
using JSON, Random

# D1: BO_CUR for 800 steps, then the frozen seasons from 0; D2: the frozen seasons from step 0.
function ol_drive(kind::String, t::Int)
    g = kind == "D1" ? (t < 800 ? LabCore.BO_CUR[t+1] : LabCore.bo_season(t - 800)) : kind == "D2" ? LabCore.bo_season(t) : error("drive $kind")
    (isinteger(g[1]) && isinteger(g[2])) || error("non-integer drive")
    return (Int(g[1]), Int(g[2]))
end
ol_law(name::String) = name == "L2" ? LawL2 : name == "L2+SF" ? LawL2SF : error("law $name")
ol_load(L, bytes) = L === LawL2 ? onelife_load_L2(bytes) : onelife_load_L2SF(bytes)

function ol_resume(manifest::String, out::String)
    m = JSON.parsefile(manifest); L = ol_law(m["law"]); kind = m["drive"]; rows = Any[]
    for seg in m["segments"]
        s = ol_load(L, read(seg["from_file"])); n0 = seg["from"]; n1 = seg["to"]; err = false
        for n in n0:n1-1; s, e = onelife_step(s, ol_drive(kind, n)); err |= e; end
        same = onelife_save(s) == read(seg["to_file"])
        push!(rows, Dict("from" => n0, "to" => n1, "same" => same, "error" => err))
    end
    write(out, JSON.json(Dict("pid" => getpid(), "rows" => rows)))
end

function ol_straight(seed::Int, law::String, kind::String, N::Int, rngseed::Int, out::String)
    Random.seed!(rngseed)
    s = onelife_birth(seed, ol_law(law)); h = sha256(onelife_save(s))
    for n in 0:N-1
        s, _ = onelife_step(s, ol_drive(kind, n)); h = sha256(vcat(h, sha256(onelife_save(s))))
    end
    write(out, JSON.json(Dict("pid" => getpid(), "cwd" => pwd(), "chain" => bytes2hex(h))))
end

if abspath(PROGRAM_FILE) == @__FILE__
    if ARGS[1] == "resume"
        ol_resume(ARGS[2], ARGS[3])
    elseif ARGS[1] == "straight"
        ol_straight(parse(Int, ARGS[2]), ARGS[3], ARGS[4], parse(Int, ARGS[5]), parse(Int, ARGS[6]), ARGS[7])
    else
        error("usage: resume <manifest> <out> | straight <seed> <law> <drive> <N> <rngseed> <out>")
    end
end
