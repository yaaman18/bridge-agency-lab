# Item 80 (user 2026-11-02 "今の時点で身体がどのような挙動をするのかグラフィカルインターフェースで描画できるようにして"):
# runs body_org with the canonical Julia rules (core/body_org.jl, read-only observer ON_STEP) and writes the trajectory
# into viewer/body.html (from viewer/body.template.html). The page only draws what is recorded here: no rule is written in
# JavaScript (CLAUDE.md). Usage: julia --project=. viewer/export_body.jl
include(joinpath(@__DIR__, "..", "core", "LabCore.jl"))
using .LabCore, JSON, Base64
const LC = LabCore
const LAB = normpath(joinpath(@__DIR__, ".."))
const STEPS = 3000; const EVERY = 3; const AMAX = 0.25
base = (U = 0.02, MCOST = 0.004, STEPS = STEPS)
L2 = (CONTRAST = "bin3", IDLE = true, GATE = true)
scenarios = [
    ("l2-seasons", "L2 の系の規則・凍結の季節", "ORG", merge(base, L2)),
    ("l2-random", "L2 の系の規則・無作為の世界", "ORG", merge(base, L2, (SCHED = "random", SCHEDSEED = 1))),
    ("stage42", "段42 の規則・凍結の季節", "ORG", base),
    ("none", "行為しない身体・凍結の季節", "NONE", base),
]
fname(b, u) = b.kind[u] == 'R' ? LC.FEATURES[b.perm[b.feat[u]]][1] : b.names[u]
out = Any[]
for (id, label, cond, o) in scenarios
    io = IOBuffer(); steps = IOBuffer(); meta = Dict{String,Any}("id" => id, "label" => label, "steps" => STEPS, "every" => EVERY,
        "W" => 24, "H" => 24, "amax" => AMAX)
    first = Ref(true)
    obs = s -> begin
        if first[]
            first[] = false
            if s.b !== nothing
                b = s.b
                meta["units"] = [Dict("name" => b.names[u], "kind" => string(b.kind[u]), "label" => fname(b, u)) for u in eachindex(b.names)]
                meta["edges"] = [[e[1] - 1, e[2] - 1] for e in b.edges]
            else
                meta["units"] = Any[]; meta["edges"] = Any[]
            end
        end
        nb = count(!=(0), s.w.C)
        write(steps, UInt8(s.y[1]), UInt8(s.y[2]), UInt8(round(Int, s.g[1])), UInt8(round(Int, s.g[2])))
        a = UInt8(0); ans = UInt8(0)
        for p in s.acting; a |= UInt8(1 << (p - 1)); s.d[p] > 0 && (ans |= UInt8(1 << (p - 1))); end
        write(steps, a, ans, UInt16(nb))
        if s.circuit !== nothing
            bits = UInt16(0); for (u, x) in enumerate(s.circuit.active); x && (bits |= UInt16(1) << (u - 1)); end
            write(steps, bits); write(steps, UInt8.(s.circuit.q)); write(steps, UInt8.(s.circuit.sg))
        end
        if s.t % EVERY == 0
            write(io, UInt8[round(UInt8, 255 * min(1.0, x / AMAX)) for x in s.w.A])
            write(io, UInt8[round(UInt8, 255 * clamp(x, 0.0, 1.0)) for x in s.w.B])
            c = falses(length(s.w.C)); for i in eachindex(s.w.C); c[i] = s.w.C[i] != 0; end
            bytes = zeros(UInt8, cld(length(c), 8)); for i in eachindex(c); c[i] && (bytes[(i-1)÷8+1] |= UInt8(1 << ((i - 1) % 8))); end
            write(io, bytes)
        end
    end
    r = body_org_run(cond, 1, merge(o, (ON_STEP = obs,)))
    meta["death"] = r["death"]; meta["meanCount"] = r["meanCount"]; meta["answered"] = r["answered"]
    meta["stepBytes"] = 8 + (isempty(meta["edges"]) ? 0 : 2 + 2 * length(meta["edges"]))
    meta["frameBytes"] = 24 * 24 * 2 + 72
    raw = vcat(take!(steps), take!(io))
    tmp = tempname(); write(tmp, raw); run(`gzip -9 -n $tmp`)
    meta["data"] = base64encode(read(tmp * ".gz")); rm(tmp * ".gz")
    meta["stepsLen"] = STEPS * meta["stepBytes"]
    push!(out, meta)
    println(rpad(id, 12), " death ", r["death"], " mean body ", round(r["meanCount"]; digits = 1), " raw ", length(raw) ÷ 1024, " KiB, gz+b64 ", length(meta["data"]) ÷ 1024, " KiB")
end
tpl = read(joinpath(@__DIR__, "body.template.html"), String)
html = replace(tpl, "__BODY_DATA__" => JSON.json(out))
write(joinpath(@__DIR__, "body.html"), html)
println("written viewer/body.html (", length(html) ÷ 1024, " KiB)")
