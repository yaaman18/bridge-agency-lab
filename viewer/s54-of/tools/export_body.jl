# S54 garden: export of the body and circuit values (viewer/s54-of/tools/export-spec.md r1).
# An observation tool: recomputes the two S54 lives (seed 669, L2 and L2SF) from birth with Julia core/, checks the
# SHA-256 of every step's save against the reference, and writes the thinned frames (n % 6 == 0, and dead_at).
# Nothing is written back to the lives; core/ and experiments/ are read only.
# Usage: cd experiments && julia --project=.. ../viewer/s54-of/tools/export_body.jl [--max-steps N] [--ref FILE] [OUTDIR]
#   --max-steps N  stop after N steps (for short checks; the death step is then checked only if it is reached)
#   --ref FILE     a reference file named ref-669-<tag>.sha; only the life of that tag is run, against FILE
# Output (OUTDIR, default viewer/s54-of/data): body-669-<tag>.json and body-669-<tag>.bin per life. Files are
# written into this run's work directory OUTDIR/.export-XXXX and published only when every check passed (see
# publish); on any failure the existing files are left as they were and the exit code is nonzero.
# Scope of that guarantee: a single run and exceptions that can be caught; a forced kill, power loss or concurrent
# runs are not covered (then run the export again: the data is rebuilt from birth).
const LAB = normpath(joinpath(@__DIR__, "..", "..", ".."))
include(joinpath(LAB, "experiments", "one_life_resume.jl"))
using SHA

const SEED = 669
const NDR = 60480
const EVERY = 6
const WW = 24
const HH = 24
const TRIAL = joinpath(LAB, "experiments", "trial-data")
# The death steps to match (E2), read from make_trial.json without a JSON package.
function expect_dead(tag)
    js = read(joinpath(TRIAL, "make_trial.json"), String)
    m = match(Regex("\"$tag\":\\{\"dead_at\":(null|[0-9]+)"), js)
    m === nothing && error("make_trial.json: no $tag dead_at")
    return m[1] == "null" ? nothing : parse(Int, m[1])
end
const LAWS = [("L2", LawL2, LAW_L2), ("L2SF", LawL2SF, LAW_L2SF)]

function parse_args(a)
    maxs = NDR; ref = nothing; out = joinpath(LAB, "viewer", "s54-of", "data"); i = 1
    while i <= length(a)
        if a[i] == "--max-steps"
            maxs = parse(Int, a[i+1]); i += 2
        elseif a[i] == "--ref"
            ref = a[i+1]; i += 2
        else
            out = a[i]; i += 1
        end
    end
    return (maxs = min(maxs, NDR), ref = ref, out = out)
end

read_drives(f) = [Tuple(parse.(Int, split(l))) for l in eachline(f)]
function read_ref(f)
    v = String[]
    for (k, l) in enumerate(eachline(f))
        p = split(l)
        parse(Int, p[1]) == k - 1 || error("ref $f: line $k has n = $(p[1])")
        push!(v, p[2])
    end
    return v
end
filesha(f) = bytes2hex(open(sha256, f))

function check_circuit(s, b0, NU, NE)
    length(s.circuit.active) == NU || error("active length $(length(s.circuit.active)) != NU $NU at t $(s.t)")
    for (nm, x) in (("q", s.circuit.q), ("sg", s.circuit.sg), ("h", s.circuit.h))
        length(x) == NE || error("spec question: $nm length $(length(x)) != NE $NE (q0) at t $(s.t)")
    end
    (s.b.edges == b0.edges && s.b.names == b0.names && s.b.kind == b0.kind && s.b.patch == b0.patch) || error("circuit structure changed at t $(s.t)")
    return nothing
end

function write_frame(io, n, h, s)
    length(s.w.C) == WW * HH || error("C length $(length(s.w.C))")
    acts = onelife_acts(s)
    write(io, htol(Int32(n)))
    write(io, h)
    write(io, htol(Float32(s.w.port.reservoir)))
    write(io, htol.(Float32.(s.pool)))
    write(io, htol(Int32(s.w.born)), htol(Int32(s.w.died)))
    write(io, UInt8(s.dead ? 0 : 1))
    write(io, s.w.C)
    write(io, htol.(Float16.(s.w.B)))
    write(io, htol.(Float16.(s.w.A)))
    write(io, UInt8.(s.circuit.active))
    write(io, htol.(Int32.(s.circuit.q)), htol.(Int32.(s.circuit.sg)), htol.(Int32.(s.circuit.h)))
    write(io, UInt8(1 in acts), UInt8(2 in acts))
    return nothing
end

jstr(x::AbstractString) = "\"" * replace(x, "\\" => "\\\\", "\"" => "\\\"") * "\""
jarr(v) = "[" * join(v, ",") * "]"

function run_life(tag, L, lawstr, dv, reffile, maxs, out)
    ref = read_ref(reffile)
    s = onelife_birth(SEED, L); b0 = deepcopy(s.b)
    NU = length(b0.names); NE = length(b0.q0)
    fbytes = 4 + 32 + 4 + 8 + 8 + 1 + WW * HH + 2 * WW * HH * 2 + NU + 3 * 4 * NE + 2
    tbin = joinpath(out, "body-669-$tag.bin"); tjs = joinpath(out, "body-669-$tag.json")
    deadat = nothing; nf = 0; last = 0; f16max = 0.0
    open(tbin, "w") do io
        for n in 0:maxs
            if n > 0
                s, e = onelife_step(s, dv[n])
                e && error("$tag: step error at n $n")
            end
            h = sha256(onelife_save(s))
            bytes2hex(h) == ref[n+1] || error("E1 $tag: sha mismatch at n $n")
            (s.dead && deadat === nothing) && (deadat = n)
            last = n
            if n % EVERY == 0 || n === deadat
                check_circuit(s, b0, NU, NE)
                f16max = max(f16max, maximum(abs, s.w.A), maximum(abs, s.w.B))
                write_frame(io, n, h, s); nf += 1
            end
            deadat === nothing || break
        end
    end
    filesize(tbin) == nf * fbytes || error("$tag: bin size $(filesize(tbin)) != $nf * $fbytes")
    f16max <= floatmax(Float16) || error("$tag: A/B value $f16max exceeds Float16")
    ex = expect_dead(tag)
    if deadat !== nothing || ex === nothing || maxs >= ex
        deadat == ex || error("E2 $tag: dead_at $deadat != $ex")
    end
    b = b0
    layout = [("n", "Int32", 1), ("sha", "UInt8", 32), ("reservoir", "Float32", 1), ("pool", "Float32", 2),
              ("born", "Int32", 1), ("died", "Int32", 1), ("alive", "UInt8", 1), ("C", "UInt8", WW * HH),
              ("B", "Float16", WW * HH), ("A", "Float16", WW * HH), ("active", "UInt8", NU),
              ("q", "Int32", NE), ("sg", "Int32", NE), ("h", "Int32", NE), ("acts", "UInt8", 2)]
    srcs = [("drives-669.txt", filesha(joinpath(TRIAL, "drives-669.txt"))), (basename(reffile), filesha(reffile))]
    for f in sort(filter(x -> endswith(x, ".jl"), readdir(joinpath(LAB, "core"))))
        push!(srcs, ("core/" * f, filesha(joinpath(LAB, "core", f))))
    end
    push!(srcs, ("viewer/s54-of/tools/export_body.jl", filesha(@__FILE__)))
    js = IOBuffer()
    println(js, "{")
    println(js, "\"format\": 1, \"seed\": $SEED, \"tag\": $(jstr(tag)), \"law\": $(jstr(lawstr)),")
    println(js, "\"W\": $WW, \"H\": $HH, \"every\": $EVERY,")
    println(js, "\"nframes\": $nf, \"frame_bytes\": $fbytes, \"dead_at\": $(deadat === nothing ? "null" : deadat), \"death\": $(s.death === nothing ? "null" : s.death), \"last_n\": $last,")
    println(js, "\"note\": \"little-endian, fixed length, no padding. B and A are Float16 roundings of Float64 for display only; a positive value is not the exact value. reservoir and pool are Float32 roundings. acts = [1 in onelife_acts(s), 2 in onelife_acts(s)], computed from the active units of the state after that step (n = 0: the initial units of the birth); it is distinct from whether the patch acted in the preceding transition. last_n = the last step walked.\",")
    println(js, "\"layout\": [", join(["{\"name\": $(jstr(a)), \"type\": $(jstr(t)), \"count\": $c}" for (a, t, c) in layout], ", "), "],")
    println(js, "\"circuit\": {\"names\": ", jarr(jstr.(b.names)), ", \"kind\": ", jarr(jstr.(string.(b.kind))),
            ", \"feat\": ", jarr(b.feat), ", \"theta\": ", jarr(b.theta), ", \"patch\": ", jarr(b.patch),
            ", \"edges\": ", jarr([jarr(collect(e)) for e in b.edges]), ", \"initial\": ", jarr(b.initial), "},")
    println(js, "\"sources\": {", join(["$(jstr(k)): $(jstr(v))" for (k, v) in srcs], ", "), "},")
    println(js, "\"site_index\": \"site i (1-based) = (y, x), i - 1 = y*W + x\"")
    println(js, "}")
    write(tjs, take!(js))
    return (tag = tag, tbin = tbin, tjs = tjs, nf = nf, deadat = deadat, last = last, f16max = f16max)
end

# Publish the new pair(s) from the run's work directory: existing files are moved aside into the work directory,
# the new files moved in; on any failure the new files placed so far are taken out and the old ones moved back.
# S54_EXPORT_FAIL_AT (off by default): publish_json injects a failure after the first .bin is placed (gate N4);
# restore_placed does the same and also fails taking back the placed files (gate N5). Every old file is still tried.
function publish(res, out, work)
    old = joinpath(work, "old"); mkdir(old)
    names = [("body-669-$(r.tag)" * x, r.tag) for r in res for x in (".bin", ".json")]
    moved = String[]; placed = String[]
    try
        for (f, _) in names
            isfile(joinpath(out, f)) || continue
            mv(joinpath(out, f), joinpath(old, f)); push!(moved, f)
        end
        for (f, _) in names
            if endswith(f, ".json") && get(ENV, "S54_EXPORT_FAIL_AT", "") in ("publish_json", "restore_placed")
                error("injected failure at publish_json (placed: $(join(placed, ", ")))")
            end
            mv(joinpath(work, f), joinpath(out, f)); push!(placed, f)
        end
    catch
        for f in placed
            try
                get(ENV, "S54_EXPORT_FAIL_AT", "") == "restore_placed" && error("injected failure at restore_placed")
                mv(joinpath(out, f), joinpath(work, f))
            catch e2
                println(stderr, "could not take back $f: ", sprint(showerror, e2))
            end
        end
        for f in moved
            try
                mv(joinpath(old, f), joinpath(out, f); force = true)
            catch e2
                println(stderr, "could not restore $f: ", sprint(showerror, e2))
            end
        end
        rethrow()
    end
    return nothing
end

function main()
    a = parse_args(ARGS)
    mkpath(a.out)
    dv = read_drives(joinpath(TRIAL, "drives-669.txt"))
    length(dv) == NDR || error("drives: $(length(dv)) lines")
    lives = a.ref === nothing ? LAWS : filter(l -> basename(a.ref) == "ref-669-$(l[1]).sha", LAWS)
    isempty(lives) && error("--ref must be named ref-669-<tag>.sha")
    work = mktempdir(a.out; prefix = ".export-", cleanup = false)
    try
        res = []
        for (tag, L, lawstr) in lives
            reffile = a.ref === nothing ? joinpath(TRIAL, "ref-669-$tag.sha") : a.ref
            t0 = time()
            r = run_life(tag, L, lawstr, dv, reffile, a.maxs, work)
            push!(res, r)
            println("ok $tag frames $(r.nf) dead_at $(r.deadat) last_n $(r.last) maxAB $(r.f16max) time $(round(time() - t0; digits = 1)) s")
        end
        publish(res, a.out, work)
    catch err
        old = joinpath(work, "old")
        if isdir(old) && !isempty(readdir(old))
            println(stderr, "restore incomplete; the old files are kept in $old")
        else
            rm(work; recursive = true)
        end
        println(stderr, "FAIL: ", sprint(showerror, err))
        exit(1)
    end
    rm(work; recursive = true)
    println("export ok")
end

main()
