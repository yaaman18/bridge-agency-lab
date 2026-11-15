# S55 judgment (discussion/specs/S55-draw.md r3 §4-§6, §8; predictions-draw.md r2 PA1-PA4; freeze-draw.txt freeze 2).
# Usage (from experiments/):
#   julia --project=.. check_draw.jl pilot   PA1 from results-draw-pilot.json  -> results-draw-pilot-check.json / .out
#   julia --project=.. check_draw.jl main    PA2-PA4 from results-draw-main.json -> results-draw-main-check.json / .out
# The module DrawJudge holds the judging rules; draw_grid.jl includes this file for gate D5 (same rule, lower bound 100)
# and for the replay of gate D3 (the draw is re-implemented here, independently of draw_grid.jl's Drawer).
# Alive at T0 + x: death === nothing or death > T0 + x (as check_stake.jl).
module DrawJudge
using JSON

const T0 = 800
const NBITS = 400_000
const FIXW = Dict(1 => 5, 2 => 3, 4 => 2)   # FIXP weights by patch (frozen in the spec §2)

# ---------------- bits ----------------
function load_bits(path)
    v = read(path)
    length(v) == NBITS || error("bit file $path: length $(length(v)) != $NBITS")
    all(c -> c == UInt8('0') || c == UInt8('1'), v) || error("bit file $path: a byte is not 0 or 1")
    return v .- UInt8('0')
end

# ---------------- the draw (re-implemented; spec §2) ----------------
draw_weights(arm, pats) = arm == "UNI" ? fill(1, length(pats)) : arm == "FIXP" ? [FIXW[p] for p in pats] : error("no weights for $arm")
function nbits_for(W)
    nb = 0
    while (1 << nb) < W
        nb += 1
    end
    return nb
end
# Draw at position pos (0-based count of bits already used) with integer weights w. Returns (index, bits used, rejections).
function redraw(bits, pos, w)
    W = sum(w); nb = nbits_for(W); p = pos; rej = 0; r = 0
    while true
        p + nb <= length(bits) || return (0, p - pos, rej)
        r = 0
        for i in 1:nb
            r = 2 * r + Int(bits[p+i])
        end
        p += nb
        r < W && break
        rej += 1
    end
    acc = 0
    for i in eachindex(w)
        acc += w[i]
        r < acc && return (i, p - pos, rej)
    end
    error("redraw: unreachable")
end

# ---------------- chi-square (regularized upper incomplete gamma) ----------------
function lgamma_half(a)
    # log Γ(a) for a a positive multiple of 1/2
    k = round(Int, 2a); k == 2a && k >= 1 || error("lgamma_half: $a")
    s = isodd(k) ? 0.5 * log(pi) : 0.0
    x = isodd(k) ? 0.5 : 1.0
    while x < a
        s += log(x); x += 1.0
    end
    return s
end
function gammq(a, x)
    x <= 0 && return 1.0
    lg = lgamma_half(a)
    if x < a + 1
        ap = a; del = 1.0 / a; s = del
        for _ in 1:100000
            ap += 1; del *= x / ap; s += del
            abs(del) < abs(s) * 1e-16 && break
        end
        return max(0.0, 1.0 - s * exp(-x + a * log(x) - lg))
    end
    tiny = 1e-300
    b = x + 1 - a; c = 1 / tiny; d = 1 / b; h = d
    for i in 1:100000
        an = -i * (i - a); b += 2
        d = an * d + b; abs(d) < tiny && (d = tiny)
        c = b + an / c; abs(c) < tiny && (c = tiny)
        d = 1 / d; del = d * c; h *= del
        abs(del - 1) < 1e-16 && break
    end
    return exp(-x + a * log(x) - lg) * h
end
chi2p(x, df) = gammq(df / 2, x / 2)

# ---------------- PA2 rule ----------------
# recs: vector of (cs patches, chosen patch). Candidate sets with at least minn draws are judged: chi-square against the
# specified probabilities, Holm over the judged sets at alpha, and every chosen share within band of the specified one.
function judge_sets(recs, arm; minn = 400, alpha = 0.01, band = 0.05)
    groups = Dict{Vector{Int},Vector{Int}}()
    for (cs, ch) in recs
        v = get!(groups, cs, zeros(Int, length(cs)))
        i = findfirst(==(ch), cs); i === nothing && error("chosen $ch not in $cs")
        v[i] += 1
    end
    rows = Any[]
    for cs in sort(collect(keys(groups)))
        o = groups[cs]; n = sum(o); w = draw_weights(arm, cs); pr = w ./ sum(w)
        e = n .* pr; x = sum((o .- e) .^ 2 ./ e); df = length(cs) - 1
        sh = o ./ n; dev = maximum(abs.(sh .- pr))
        push!(rows, Dict{String,Any}("cs" => cs, "n" => n, "counts" => o, "spec" => pr, "share" => sh, "maxDev" => dev,
            "chi2" => x, "df" => df, "p" => chi2p(x, df), "judged" => n >= minn, "withinBand" => dev <= band))
    end
    J = [r for r in rows if r["judged"]]
    m = length(J)
    for r in rows; r["holmReject"] = false; end
    if m > 0
        ord = sortperm([r["p"] for r in J])
        for (i, j) in enumerate(ord)
            thr = alpha / (m - i + 1)
            J[j]["holmThreshold"] = thr
            if J[j]["p"] <= thr
                J[j]["holmReject"] = true
            else
                break
            end
        end
    end
    for r in J
        r["matches"] = !r["holmReject"] && r["withinBand"]
    end
    verdict = m == 0 ? "undetectable" : all(r -> r["matches"], J) ? "holds" : "miss"
    return Dict{String,Any}("rows" => rows, "nJudged" => m, "verdict" => verdict, "minn" => minn, "alpha" => alpha, "band" => band)
end

# records of a run (as stored by draw_grid.jl): drawn = two or more in the choosing set, at or after T0
drawn_idx(dr) = [i for i in eachindex(dr["t"]) if length(dr["cs"][i]) >= 2 && dr["t"][i] >= T0]
recs_of(dr) = [(Vector{Int}(dr["cs"][i]), Int(dr["chosen"][i])) for i in drawn_idx(dr)]

# PA3 replay of one run's records from the bit file
function replay(dr, bits, arm)
    ok = 0; bad = 0
    for i in eachindex(dr["t"])
        cs = Vector{Int}(dr["cs"][i])
        if length(cs) < 2 || arm == "DET"
            good = dr["chosen"][i] == dr["det"][i] && dr["nb"][i] == 0 && (length(cs) >= 2 || dr["chosen"][i] == cs[1])
        else
            k, used, rej = redraw(bits, dr["pos"][i], draw_weights(arm, cs))
            good = k > 0 && cs[k] == dr["chosen"][i] && rej == dr["rej"][i] && used == dr["nb"][i] * (1 + dr["rej"][i])
        end
        good ? (ok += 1) : (bad += 1)
    end
    return ok, bad
end

alive(death, x) = death === nothing || death > T0 + x
end # module DrawJudge

if abspath(PROGRAM_FILE) == @__FILE__
using .DrawJudge, JSON
const DJ = DrawJudge
const LAB = normpath(joinpath(@__DIR__, ".."))
const MODE = length(ARGS) >= 1 ? ARGS[1] : error("mode pilot | main")
const LAWS = ("L2", "L2+SF"); const ARMS = ("DET", "UNI", "FIXP")
const L = String[]
say(x...) = (s = string(x...); println(s); push!(L, s))
r3(x) = x === nothing ? nothing : round(x; digits = 3)
mean(v) = isempty(v) ? NaN : sum(v) / length(v)
out = Dict{String,Any}()
const NOTES = "Decisions accepted by the coordinator (2026-11-15): PA4 state = world (A, B, C, port, counters), pools, circuit state, " *
    "noise RNG; the draw mechanism and the records are excluded. D5 second stream Mulberry(1000003u+56) < 0.2, judged per law. " *
    "Bit files ASCII '0'/'1'. Spec r3 §8: no m0; candidate set {m1, m2}; specified probabilities UNI 1/2:1/2, FIXP 5/8:3/8; " *
    "no rejection occurs in a life (W = 2 and 8)."
say(NOTES); out["notes"] = NOTES

if MODE == "pilot"
    P = JSON.parsefile(joinpath(LAB, "experiments", "results-draw-pilot.json"))
    us = string.(P["windows"])
    adm = Dict{String,Any}()
    for law in LAWS
        o = Dict{String,Any}(); out[law] = o; okLaw = true
        for arm in ARMS
            runs = [P["runs"][law][arm][u] for u in us]
            nal = count(r -> DJ.alive(r["death"], 2000), runs)
            nd = [length(DJ.drawn_idx(r["draws"])) for r in runs]
            ok = nal >= 3 && minimum(nd) >= 200
            okLaw = okLaw && ok
            o[arm] = Dict("alive2000" => nal, "drawSteps" => nd, "minDrawSteps" => minimum(nd), "meets" => ok)
            say("PA1 ", law, " ", rpad(arm, 4), ": alive at T0+2000 ", nal, "/", length(us), ", drawing steps after T0 per window ",
                join(nd, " "), " (min ", minimum(nd), ") -> ", ok ? "meets" : "does not meet")
        end
        o["admit"] = okLaw; adm[law] = okLaw
        agree = P["admit"][law] == okLaw
        o["agreesWithGrid"] = agree
        say("PA1 verdict ", law, ": ", okLaw ? "holds" : "miss", " -> ", okLaw ? "admitted to the evaluation windows (all three arms)" :
            "not admitted (cannot be measured; none of the three arms is run)", "; grid decision agrees: ", agree)
    end
    out["admit"] = adm
    out["PA1"] = all(values(adm))
    say("PA1 overall (both laws, all arms): ", out["PA1"] ? "holds" : "miss")
elseif MODE == "main"
    recs = Dict{String,Any}()
    for l in eachline(joinpath(LAB, "experiments", "results-draw-main.json"))
        d = try JSON.parse(l) catch; nothing end
        d === nothing || (recs[d["key"]] = d)
    end
    P = JSON.parsefile(joinpath(LAB, "experiments", "results-draw-pilot.json"))
    bitcache = Dict{Int,Any}()
    bitsof(u) = get!(() -> DJ.load_bits(joinpath(LAB, "experiments", "draw-bits", "u$(u).bits")), bitcache, u)
    for law in LAWS
        o = Dict{String,Any}(); out[law] = o
        if !P["admit"][law]
            say("==== law ", law, ": not admitted by the pilot -> PA2, PA3, PA4 cannot be measured (no evaluation run)")
            o["admitted"] = false
            continue
        end
        o["admitted"] = true
        ks = sort([k for k in keys(recs) if recs[k]["law"] == law]; by = k -> recs[k]["u"])
        us = [recs[k]["u"] for k in ks]
        say("==== law ", law, "  (windows ", join(us, ","), ", n = ", length(us), ")")
        R(arm, k) = recs[k]["arms"][arm]
        # reported without prediction
        for arm in ARMS
            dth = [R(arm, k)["death"] for k in ks]
            say("   ", rpad(arm, 4), " alive T0+500 ", count(d -> DJ.alive(d, 500), dth), "/", length(ks),
                ", T0+2000 ", count(d -> DJ.alive(d, 2000), dth), "/", length(ks), ", horizon ", count(d -> d === nothing, dth), "/", length(ks),
                " | death steps: ", join([d === nothing ? "-" : d for d in dth], " "))
            say("        body (countAt T0+500, T0+2000, 9200): ", join([join(R(arm, k)["countAt"], "/") for k in ks], " "))
            say("        answered share of acts from T0: ", join(r3.([R(arm, k)["answered"] for k in ks]), " "))
            say("        drawing steps: ", join([R(arm, k)["drawSteps"] for k in ks], " "), " | agreement with DET's choice: ",
                join(r3.([R(arm, k)["agreeDET"] for k in ks]), " "), " (mean ", r3(mean(filter(!isnan, Float64[something(R(arm, k)["agreeDET"], NaN) for k in ks]))), ")",
                " | rejected share of bit groups: ", join(r3.([R(arm, k)["rejShare"] for k in ks]), " "))
            o[arm] = Dict("death" => dth, "alive500" => count(d -> DJ.alive(d, 500), dth), "alive2000" => count(d -> DJ.alive(d, 2000), dth),
                "aliveEnd" => count(d -> d === nothing, dth), "countAt" => [R(arm, k)["countAt"] for k in ks],
                "answered" => [R(arm, k)["answered"] for k in ks], "drawSteps" => [R(arm, k)["drawSteps"] for k in ks],
                "agreeDET" => [R(arm, k)["agreeDET"] for k in ks], "rejShare" => [R(arm, k)["rejShare"] for k in ks])
        end
        # PA2
        for arm in ("UNI", "FIXP")
            rs = reduce(vcat, [DJ.recs_of(R(arm, k)["draws"]) for k in ks])
            j = DJ.judge_sets(rs, arm; minn = 400)
            for r in j["rows"]
                say("   PA2 ", arm, " set ", r["cs"], ": n ", r["n"], ", counts ", r["counts"], ", shares ", r3.(r["share"]), " vs specified ", r3.(r["spec"]),
                    ", max dev ", r3(r["maxDev"]), ", chi2 ", r3(r["chi2"]), " (df ", r["df"], "), uncorrected p ", r3(r["p"]),
                    r["judged"] ? string(", Holm reject at 1 %: ", r["holmReject"], ", within 0.05: ", r["withinBand"]) : " (fewer than 400 draws: reported, not judged)")
            end
            o["PA2 " * arm] = j
            say("PA2 verdict ", law, " ", arm, ": ", j["verdict"], " (", j["nJudged"], " candidate set(s) judged)")
        end
        # PA3
        tot = 0; bad = 0; rer = true
        for arm in ARMS, k in ks
            okn, badn = DJ.replay(R(arm, k)["draws"], bitsof(recs[k]["u"]), arm)
            tot += okn + badn; bad += badn
            rer = rer && R(arm, k)["rerunIdentical"] == true
        end
        pa3 = bad == 0 && rer
        o["PA3"] = Dict("records" => tot, "notReproduced" => bad, "rerunIdentical" => rer, "holds" => pa3)
        say("PA3 verdict ", law, ": ", pa3 ? "holds" : "miss", " (records replayed from the bit files: ", tot - bad, "/", tot,
            "; second run bit-identical at every step for all ", 3 * length(ks), " runs: ", rer, ")")
        # PA4
        for arm in ("UNI", "FIXP")
            dif = [R(arm, k)["stateAt"] != R("DET", k)["stateAt"] for k in ks]
            nd = count(dif); h = nd >= 10
            o["PA4 " * arm] = Dict("differ" => dif, "nDiffer" => nd, "holds" => h)
            say("PA4 verdict ", law, " ", arm, ": ", h ? "holds" : "miss", " (state at T0+2000 differs from DET in ", nd, "/", length(ks), " windows; predicted >= 10)")
        end
    end
else
    error("mode pilot | main")
end
write(joinpath(LAB, "experiments", "results-draw-$(MODE)-check.out"), join(L, "\n") * "\n")
write(joinpath(LAB, "experiments", "results-draw-$(MODE)-check.json"), JSON.json(out, 2))
end
