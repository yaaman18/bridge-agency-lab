# S48b helper (discussion/specs/S48b-death-drive.md r1): the drives D3 / D4, and the other process of PD4.
# Included by one_life_death.jl for the drives; run as a script:
#   julia --project=.. one_life_death_resume.jl resume <manifest.json> <out.json>
#     for each listed save (taken from the straight run after n drives), loads it, continues to N, and compares the
#     SHA-256 of the save after every drive with the straight run's (the hash file: 32 bytes for each n = 0..N).
#     The manifest may name one point and one drive index to leave out (the negative control of H2).
include(joinpath(@__DIR__, "one_life_resume.jl"))
using JSON, SHA

# The drives are functions of the drive index n only (H1). D3: D1 for n < 2000 (the same construction), then (0,0),
# then (5,5) from 6000. D4: (0,0), then (5,5) from 6000.
drive_D3(n::Int) = n < 2000 ? ol_drive("D1", n) : n < 6000 ? (0, 0) : (5, 5)
drive_D4(n::Int) = n < 6000 ? (0, 0) : (5, 5)
death_drive(kind::String, n::Int) = kind == "D3" ? drive_D3(n) : kind == "D4" ? drive_D4(n) : error("drive $kind")

function od_resume(manifest::String, out::String)
    m = JSON.parsefile(manifest); L = ol_law(m["law"]); kind = m["drive"]; N = m["N"]
    H = read(m["hashes"]); length(H) == 32 * (N + 1) || error("hash file length")
    href(n) = H[32*n+1:32*n+32]
    skip = get(m, "skip", nothing); rows = Any[]
    for (i, p) in enumerate(m["points"])
        n0 = p["n"]; s = ol_load(L, read(p["file"])); err = false
        load_same = sha256(onelife_save(s)) == href(n0)
        first_bad = nothing; nbad = 0
        for n in n0:N-1
            leave = skip !== nothing && skip["point"] == i && skip["at"] == n
            if !leave
                s, e = onelife_step(s, death_drive(kind, n)); err |= e
            end
            if sha256(onelife_save(s)) != href(n + 1)
                nbad += 1; first_bad === nothing && (first_bad = n + 1)
            end
        end
        push!(rows, Dict("from" => n0, "load_same" => load_same, "first_bad" => first_bad, "nbad" => nbad, "error" => err,
                         "steps" => N - n0))
    end
    write(out, JSON.json(Dict("pid" => getpid(), "rows" => rows)))
end

if abspath(PROGRAM_FILE) == @__FILE__
    ARGS[1] == "resume" || error("usage: resume <manifest> <out>")
    od_resume(ARGS[2], ARGS[3])
end
