# S54 garden: read-back check of the exported body files (viewer/s54-of/tools/export-spec.md r1, gate E3).
# Reads body-669-<tag>.json and .bin and checks: file size = nframes * frame_bytes; the n sequence 0, 6, 12, ... and
# dead_at; every frame's sha equals the reference line; the frames with n <= 300 against the first 300 steps
# recomputed here from birth (C exact, Float16 fields equal Float16(x), circuit fields exact).
# Usage: cd experiments && julia --project=.. ../viewer/s54-of/tools/read_body.jl JSON...
# Exit code 0 when every file passes, 1 otherwise.
const LAB = normpath(joinpath(@__DIR__, "..", "..", ".."))
include(joinpath(LAB, "experiments", "one_life_resume.jl"))
using SHA

const TRIAL = joinpath(LAB, "experiments", "trial-data")
const NCHECK = 300

# Minimal reader of the header fields used here (the header is written by export_body.jl).
jint(s, k) = (m = match(Regex("\"$k\": (null|-?[0-9]+)"), s); m === nothing && error("header: no $k"); m[1] == "null" ? nothing : parse(Int, m[1]))
jstrf(s, k) = (m = match(Regex("\"$k\": \"([^\"]*)\""), s); m === nothing && error("header: no $k"); String(m[1]))
function jlayout(s)
    return [(String(m[1]), String(m[2]), parse(Int, m[3])) for m in eachmatch(r"\{\"name\": \"([^\"]+)\", \"type\": \"([^\"]+)\", \"count\": ([0-9]+)\}", s)]
end
const TSIZE = Dict("Int32" => 4, "UInt8" => 1, "Float32" => 4, "Float16" => 2)
const TTYPE = Dict("Int32" => Int32, "UInt8" => UInt8, "Float32" => Float32, "Float16" => Float16)

function decode_frame(bytes, layout)
    d = Dict{String,Vector}(); o = 0
    for (nm, t, c) in layout
        k = TSIZE[t] * c
        d[nm] = ltoh.(reinterpret(TTYPE[t], bytes[o+1:o+k])); o += k
    end
    o == length(bytes) || error("layout size $o != frame $(length(bytes))")
    return d
end

bits(x::AbstractVector{Float16}) = reinterpret(UInt16, collect(x))

function check(jsonf)
    hd = read(jsonf, String)
    tag = jstrf(hd, "tag"); nf = jint(hd, "nframes"); fb = jint(hd, "frame_bytes")
    deadat = jint(hd, "dead_at"); last = jint(hd, "last_n"); every = jint(hd, "every")
    layout = jlayout(hd)
    sum(TSIZE[t] * c for (_, t, c) in layout) == fb || error("$tag: layout sum != frame_bytes")
    binf = replace(jsonf, r"\.json$" => ".bin")
    filesize(binf) == nf * fb || error("E3 $tag: size $(filesize(binf)) != $nf * $fb")
    expn = collect(0:every:last)
    (deadat !== nothing && deadat % every != 0) && push!(expn, deadat)
    deadat === nothing || deadat == last || error("E3 $tag: dead_at $deadat != last_n $last")
    length(expn) == nf || error("E3 $tag: nframes $nf != expected $(length(expn))")
    ref = [split(l)[2] for l in eachline(joinpath(TRIAL, "ref-669-$tag.sha"))]
    L = tag == "L2" ? LawL2 : tag == "L2SF" ? LawL2SF : error("tag $tag")
    dv = [Tuple(parse.(Int, split(l))) for l in Iterators.take(eachline(joinpath(TRIAL, "drives-669.txt")), NCHECK)]
    s = onelife_birth(669, L); sn = 0
    bin = read(binf)
    ncmp = 0
    for k in 1:nf
        d = decode_frame(view(bin, (k-1)*fb+1:k*fb), layout)
        n = Int(d["n"][1])
        n == expn[k] || error("E3 $tag: frame $k has n $n, expected $(expn[k])")
        bytes2hex(UInt8.(d["sha"])) == ref[n+1] || error("E3 $tag: frame n $n sha != reference")
        n <= NCHECK || continue
        while sn < n
            s, e = onelife_step(s, dv[sn+1]); e && error("step error"); sn += 1
        end
        bytes2hex(sha256(onelife_save(s))) == ref[n+1] || error("E3 $tag: recomputed state n $n sha != reference")
        acts = onelife_acts(s)
        ok = d["C"] == s.w.C
        ok = ok && bits(d["B"]) == bits(Float16.(s.w.B))
        ok = ok && bits(d["A"]) == bits(Float16.(s.w.A))
        ok = ok && d["active"] == UInt8.(s.circuit.active)
        ok = ok && d["q"] == Int32.(s.circuit.q)
        ok = ok && d["sg"] == Int32.(s.circuit.sg)
        ok = ok && d["h"] == Int32.(s.circuit.h)
        ok = ok && d["acts"] == UInt8[1 in acts, 2 in acts]
        ok = ok && d["reservoir"] == Float32[s.w.port.reservoir]
        ok = ok && d["pool"] == Float32.(s.pool)
        ok = ok && d["born"] == Int32[s.w.born]
        ok = ok && d["died"] == Int32[s.w.died]
        ok = ok && d["alive"] == UInt8[s.dead ? 0 : 1]
        ok || error("E3 $tag: frame n $n differs from the recomputed state")
        ncmp += 1
    end
    println("E3 ok $tag frames $nf compared_with_recompute $ncmp last_n $last dead_at $deadat")
end

function main()
    isempty(ARGS) && error("usage: read_body.jl JSON...")
    try
        foreach(check, ARGS)
    catch err
        println(stderr, "FAIL: ", sprint(showerror, err))
        exit(1)
    end
end

main()
