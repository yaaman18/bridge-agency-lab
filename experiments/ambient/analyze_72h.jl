# S52 design period (first 72 h of summed uptime): slicer + analysis. Spec ../../discussion/specs/S52-ambient-log.md (r2),
# predictions ../predictions-ambient-log.md (r2, PS1-PS5), clock/moves log ../s52-moves.txt. Request: neon-lab 2026-11-23.
# Blinding: the source copy is read line by line from the top and closed at the first line whose summed uptime would exceed
# 259200 s; of that line only the boot id and uptime_s are parsed, nothing of it is written or kept. Every later step reads
# only design_72h.tsv. Usage: julia --project=../.. analyze_72h.jl [outdir under out-72h, default "."]
using SHA

const HERE = @__DIR__
const ROOT = normpath(joinpath(HERE, "..", ".."))
const EXP = joinpath(ROOT, "experiments")
const OUT = normpath(joinpath(HERE, "out-72h", length(ARGS) >= 1 ? ARGS[1] : "."))
mkpath(OUT)
const LOG = String[]
say(xs...) = (s = string(xs...); push!(LOG, s); println(s))
sha(f) = bytes2hex(open(sha256, f))

include(joinpath(ROOT, "core", "LabCore.jl")); using .LabCore: Mulberry

const SRC = joinpath(HERE, "copies", "ambient-20261123.tsv")
const SRC_SHA = "47a5084dc943e46cff33d712d5359ce057ace094fcd4d375e16e4dfb0b759c7a"
const LIMIT = 259200.0
const HEADER = "pi_s\tboot\tuptime_s\tt_mc\tw_n\tw_max\tw_sum\tw_24\tw_5\tw_h1\tw_h2\tw_h3\tw_h4\tw_h5\tb_n\tb_max\tb_r\tb_h1\tb_h2\tb_h3\tb_h4\tw_ms\tb_ms\tfail"
const COLS = split(HEADER, '\t')
col(name) = findfirst(==(name), COLS)

# ---------------- G-F ----------------
function gate_f()
    fz = readlines(joinpath(EXP, "freeze-ambient-log.txt"))
    i = findfirst(l -> startswith(l, "# S52 freeze 1"), fz)
    ok = true
    for l in fz[i+1:i+2]
        h, f = split(l)
        got = sha(normpath(joinpath(EXP, f)))
        say("G-F ", f, ": frozen ", h[1:12], " now ", got[1:12], got == h ? " ok" : " DIFFERS")
        ok &= got == h
    end
    return ok
end

# ---------------- slicer (the only reader of the source copy) ----------------
function slice(dst)
    sha(SRC) == SRC_SHA || error("source sha differs")
    nkept = 0; cum = 0.0; base = 0.0; curboot = ""; u0 = 0.0; stopped = false
    open(SRC) do io
        readline(io) == HEADER || error("source header differs")
        open(dst, "w") do o
            println(o, HEADER)
            while !eof(io)
                l = readline(io)
                f = split(l, '\t'; limit = 4)
                b = String(f[2]); u = parse(Float64, f[3])
                if b != curboot; curboot = b; u0 = u; base = cum; end
                c = base + (u - u0)
                if c > LIMIT; stopped = true; break; end   # boundary line: discarded, nothing of it is kept
                println(o, l); nkept += 1; cum = c
            end
        end
    end
    return (rows = nkept, cum = cum, stopped = stopped)
end

# ---------------- reading the design file ----------------
struct Row; v::Vector{Float64}; boot::String; end
getv(r::Row, name) = r.v[col(name)]
function readdesign(f)
    ls = readlines(f); ls[1] == HEADER || error("design header")
    rows = Row[]
    for l in ls[2:end]
        x = split(l, '\t'); length(x) == 24 || error("design: ", length(x), " columns")
        v = [i == 2 ? NaN : (x[i] == "NA" ? NaN : parse(Float64, x[i])) for i in 1:24]
        push!(rows, Row(v, String(x[2])))
    end
    return rows
end

# ---------------- statistics (no tests; S52 section 3) ----------------
function qtl(xs, p)   # type 7
    s = sort(xs); n = length(s); h = (n - 1) * p + 1; lo = floor(Int, h); hi = min(lo + 1, n)
    return s[lo] + (h - lo) * (s[hi] - s[lo])
end
med(xs) = qtl(xs, 0.5)
function pearson(x, y)
    n = length(x); n < 3 && return NaN
    mx = sum(x) / n; my = sum(y) / n
    sxy = sum((x .- mx) .* (y .- my)); sxx = sum((x .- mx) .^ 2); syy = sum((y .- my) .^ 2)
    return (sxx == 0 || syy == 0) ? NaN : sxy / sqrt(sxx * syy)
end
jstdate(d) = (t = d * 86400; y = 1970; while (yl = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 366 : 365; t >= yl * 86400); t -= yl * 86400; y += 1; end;
    ml = [31, (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]; m = 1; while t >= ml[m] * 86400; t -= ml[m] * 86400; m += 1; end;
    string(y, "-", lpad(m, 2, "0"), "-", lpad(t ÷ 86400 + 1, 2, "0")))
r6(x) = isnan(x) ? "NaN" : string(round(x; digits = 6))

# ---------------- clock correction (spec section 2; s52-moves.txt) ----------------
# Transcribed from s52-moves.txt (sha checked): the only recorded correction. No entry records a change of place.
const MOVES_SHA = "935cbc2665e4ff779ad07e823048993285334da0588925a17b82953d0350c35e"
const CORR = Dict("7c24432f" => (upto = 42.97, add = 122.0))
const PHYSICAL_MOVES = Tuple{String,Int}[]   # (JST, epoch) of recorded changes of place: none in s52-moves.txt

function main()
    say("S52 72h design-period analysis")
    gf = gate_f()
    mv = joinpath(EXP, "s52-moves.txt"); mvsha = sha(mv)
    mvsha == MOVES_SHA || error("s52-moves.txt changed since the transcription: re-read it")
    mvtxt = read(mv, String)
    nentries = count(l -> occursin(r"^\d{4}-\d\d-\d\d", l), split(mvtxt, '\n'))
    nsame = count(l -> occursin("場所は変えていない", l), split(mvtxt, '\n'))
    say("s52-moves.txt sha ", mvsha[1:12], ": ", nentries, " entries, ", nsame, " say the place was not changed, recorded changes of place ", length(PHYSICAL_MOVES))

    dst = joinpath(OUT, "design_72h.tsv")
    sl = slice(dst)
    say("slicer: kept ", sl.rows, " rows, summed uptime at the last kept row ", r6(sl.cum), " s, stopped at the boundary: ", sl.stopped)
    gblind = sl.stopped && sl.cum <= LIMIT
    # G-A0 on the design file only
    a0 = read(ignorestatus(`sh $(joinpath(HERE, "check_ambient.sh")) a0 $dst`), String) |> strip
    say("G-A0: ", a0); ga0 = startswith(a0, "A0 PASS")

    R = readdesign(dst); N = length(R)
    up = [getv(r, "uptime_s") for r in R]; pis = [getv(r, "pi_s") for r in R]; fl = [getv(r, "fail") for r in R]
    valid = fl .== 0
    # summed uptime recomputed from the design file
    # same formula as the slicer: base of the boot + (u - first u of the boot)
    cum = zeros(N); base = 0.0; u0 = up[1]
    for i in 2:N
        R[i].boot != R[i-1].boot && (base = cum[i-1]; u0 = up[i])
        cum[i] = base + (up[i] - u0)
    end
    say("G-BLIND: design rows ", N, ", summed uptime at the last row ", r6(cum[end]), " s (<= ", LIMIT, "): ", cum[end] <= LIMIT)
    gblind &= cum[end] <= LIMIT && cum[end] == sl.cum

    # boots
    boots = String[]; for r in R; (isempty(boots) || boots[end] != r.boot) && push!(boots, r.boot); end
    length(unique(boots)) == length(boots) || error("a boot id appears in two separate runs")
    corr = [haskey(CORR, R[i].boot) && up[i] <= CORR[R[i].boot].upto ? CORR[R[i].boot].add : 0.0 for i in 1:N]
    pic = pis .+ corr
    btab = Dict{String,Any}[]; timeok = Dict{String,Bool}()
    say("boot table (pi_s raw; corr = correction from s52-moves.txt; back = clock earlier than the previous row; ",
        "lag = the clock advanced less than the new boot's uptime since the previous row, i.e. it must be behind; jump = max |dpi_s - duptime| within the boot):")
    say("  boot      rows  valid  pi_first    pi_last     up_first   up_last     sum_start   sum_end     dpi_prev  back  lag   record      jump_raw  jump_corr  time_used")
    for (j, b) in enumerate(boots)
        ix = findall(r -> r.boot == b, R); i1 = ix[1]; i2 = ix[end]
        dprev = j == 1 ? NaN : pis[i1] - pis[i1-1]
        back = j > 1 && pis[i1] < pis[i1-1]
        lag = j > 1 && (pic[i1] - pic[i1-1]) < up[i1]
        rec = haskey(CORR, b)
        jr = maximum([abs((pis[i] - pis[i-1]) - (up[i] - up[i-1])) for i in ix[2:end]]; init = 0.0)
        jc = maximum([abs((pic[i] - pic[i-1]) - (up[i] - up[i-1])) for i in ix[2:end]]; init = 0.0)
        ok = !(back || lag) || rec
        lag_after = j > 1 && (pic[i1] - pic[i1-1]) < up[i1]
        ok = ok && !lag_after && jc <= 2.0
        timeok[b] = ok
        push!(btab, Dict("boot" => b, "rows" => length(ix), "valid" => count(valid[ix]), "pi_first" => pis[i1], "pi_last" => pis[i2],
            "uptime_first" => up[i1], "uptime_last" => up[i2], "sum_start" => cum[i1], "sum_end" => cum[i2], "dpi_from_prev_row" => dprev,
            "clock_back" => back, "clock_lag" => lag, "correction_record" => rec, "max_jump_raw" => jr, "max_jump_corrected" => jc, "time_used_PS2_PS3" => ok))
        say("  ", rpad(b, 9), lpad(length(ix), 5), lpad(count(valid[ix]), 7), "  ", rpad(Int(pis[i1]), 11), " ", rpad(Int(pis[i2]), 11), " ",
            rpad(up[i1], 10), " ", rpad(up[i2], 11), " ", rpad(round(cum[i1]; digits = 2), 11), " ", rpad(round(cum[i2]; digits = 2), 11), " ",
            rpad(isnan(dprev) ? "-" : string(Int(dprev)), 9), " ", rpad(back, 5), " ", rpad(lag, 5), " ", rpad(rec ? "+122(<=42.97)" : "-", 11), " ",
            rpad(round(jr; digits = 2), 9), " ", rpad(round(jc; digits = 2), 10), " ", ok)
    end
    tused = [timeok[r.boot] for r in R]

    # ---------------- PS1-PS5 ----------------
    V(name) = [getv(R[i], name) for i in 1:N if valid[i]]
    nws = length(unique(V("w_sum"))); nbn = length(unique(V("b_n")))
    ps1 = nws >= 5 && nbn >= 3
    say("PS1: distinct w_sum ", nws, " (>= 5), distinct b_n ", nbn, " (>= 3): ", ps1 ? "holds" : "miss")

    jst = pic .+ 9 * 3600; day = floor.(Int, jst ./ 86400); hr = floor.(Int, mod.(jst, 86400) ./ 3600)
    function ps2(use, tag)
        days = sort(unique(day[[i for i in 1:N if use[i] && valid[i]]]))
        ps2rows = Dict{String,Any}[]; nus = 0; bhold = 0; whold = 0
        say("PS2 days ", tag, ":")
        for d in days
            A = [i for i in 1:N if use[i] && valid[i] && day[i] == d && 1 <= hr[i] < 5]
            B = [i for i in 1:N if use[i] && valid[i] && day[i] == d && 19 <= hr[i] < 23]
            usable = length(A) >= 120 && length(B) >= 120
            rec = Dict{String,Any}("day_jst" => jstdate(d), "n_01_05" => length(A), "n_19_23" => length(B), "usable" => usable)
            line = "  day " * jstdate(d) * ": n(01-05) " * string(length(A)) * ", n(19-23) " * string(length(B))
            if usable
                nus += 1
                bA = med([getv(R[i], "b_n") for i in A]); bB = med([getv(R[i], "b_n") for i in B])
                wA = med([getv(R[i], "w_n") for i in A]); wB = med([getv(R[i], "w_n") for i in B])
                bh = bA < bB; wh = abs(wA - wB) <= 1; bhold += bh; whold += wh
                merge!(rec, Dict("b_med_01_05" => bA, "b_med_19_23" => bB, "bt_lower_at_night" => bh, "w_med_01_05" => wA, "w_med_19_23" => wB, "wifi_within_1" => wh))
                line *= ", usable: median b_n " * string(bA) * " vs " * string(bB) * " (" * string(bh) * "), median w_n " * string(wA) * " vs " * string(wB) * " (" * string(wh) * ")"
            else
                line *= ", not usable"
            end
            push!(ps2rows, rec); say(line)
    end
    ps2b = nus < 2 ? "not testable" : (bhold >= 2 ? "holds" : "miss")
    ps2w = nus < 2 ? "not testable" : (whold >= 2 ? "holds" : "miss")
    return (rows = ps2rows, nus = nus, bhold = bhold, whold = whold, b = ps2b, w = ps2w)
    end
    P2 = ps2(tused, "(JST of the corrected clock; rows of boots with time_used, spec section 2 rule)")
    ps2rows, nus, bhold, whold, ps2b, ps2w = P2.rows, P2.nus, P2.bhold, P2.whold, P2.b, P2.w
    say("PS2: usable days ", nus, "; Bluetooth half ", ps2b, " (", bhold, " days); Wi-Fi half ", ps2w, " (", whold, " days)")
    # diagnostic, not the verdict: boots after a power-up whose clock is not backed by a record (the first boot was set from the
    # Mac before the start; 9d4d0aea was a reboot without power loss; 7c24432f has the recorded +122 s). 7c24432f passed the
    # back/lag tests while 122 s behind, so these tests cannot see a small lag.
    recd = Dict(b => (j == 1 || haskey(CORR, b) || b == "9d4d0aea") for (j, b) in enumerate(boots))
    P2s = ps2([tused[i] && recd[R[i].boot] for i in 1:N], "(sensitivity: only boots whose clock is backed by a record)")
    say("PS2 sensitivity (diagnostic): usable days ", P2s.nus, "; Bluetooth ", P2s.b, " (", P2s.bhold, " days); Wi-Fi ", P2s.w, " (", P2s.whold, " days); boots without a record: ",
        join([b for b in boots if !recd[b]], ","))

    ps3 = length(PHYSICAL_MOVES) >= 2 ? error("moves present: PS3 not implemented for moves") : "not testable"
    say("PS3: recorded changes of place in the design period ", length(PHYSICAL_MOVES), " (< 2 qualifying moves): ", ps3)

    lx = Float64[]; ly = Float64[]
    for i in 2:N
        (R[i].boot == R[i-1].boot && up[i] - up[i-1] <= 120 && valid[i] && valid[i-1]) || continue
        push!(lx, getv(R[i-1], "t_mc")); push!(ly, getv(R[i], "t_mc"))
    end
    ac1 = pearson(lx, ly)
    ctw = pearson(V("t_mc"), V("w_sum"))
    ps4a = ac1 > 0.9 ? "holds" : "miss"; ps4b = -0.3 <= ctw <= 0.3 ? "holds" : "miss"
    say("PS4: lag-1 autocorrelation of t_mc ", r6(ac1), " over ", length(lx), " pairs (> 0.9): ", ps4a, "; corr(t_mc, w_sum) ", r6(ctw), " ([-0.3, 0.3]): ", ps4b)

    nfail = count(fl .> 0)
    gaps = [up[i] - up[i-1] for i in 2:N if R[i].boot == R[i-1].boot]
    mg = maximum(gaps); ffrac = nfail / N
    ps5a = ffrac < 0.02; ps5b = mg <= 120
    ps5 = ps5a && ps5b ? "holds" : "miss"
    say("PS5: failed rows ", nfail, "/", N, " = ", r6(100 * ffrac), " % (< 2 %): ", ps5a, "; max gap within a boot ", r6(mg), " s (<= 120): ", ps5b, " -> ", ps5)
    say("  failed rows by mark: ", Dict(string(Int(k)) => count(==(k), fl) for k in sort(unique(fl)) if k > 0))

    # ---------------- descriptive ----------------
    vars = ["w_n", "w_max", "w_sum", "w_24", "w_5", "b_n", "b_max", "b_r", "t_mc"]
    desc = Dict{String,Any}()
    say("distribution over valid rows (min q25 median q75 max distinct n):")
    for v in vars
        x = filter(!isnan, V(v))
        desc[v] = Dict("min" => minimum(x), "q25" => qtl(x, 0.25), "median" => med(x), "q75" => qtl(x, 0.75), "max" => maximum(x), "distinct" => length(unique(x)), "n" => length(x))
        say("  ", rpad(v, 6), " ", join([r6(desc[v][k]) for k in ("min", "q25", "median", "q75", "max")], " "), "  distinct ", desc[v]["distinct"], "  n ", length(x))
    end
    hourly = Dict{String,Any}()
    say("median by JST hour (time_used valid rows): hour n w_sum w_n b_n t_mc")
    for h in 0:23
        ix = [i for i in 1:N if tused[i] && valid[i] && hr[i] == h]
        if isempty(ix); hourly[lpad(h, 2, '0')] = Dict("n" => 0); say("  ", lpad(h, 2, '0'), " 0"); continue; end
        m = Dict(v => med([getv(R[i], v) for i in ix]) for v in ("w_sum", "w_n", "b_n", "t_mc"))
        hourly[lpad(h, 2, '0')] = merge(Dict{String,Any}("n" => length(ix)), m)
        say("  ", lpad(h, 2, '0'), " ", lpad(length(ix), 5), " ", join([r6(m[v]) for v in ("w_sum", "w_n", "b_n", "t_mc")], " "))
    end
    lags = [1, 2, 10, 30, 120, 720, 1440, 2880]
    acs = Dict{String,Any}()
    say("autocorrelation within one boot at a lag of k rows (both rows valid): k w_sum w_n b_n t_mc (pairs)")
    for k in lags
        pr = [(i, i + k) for i in 1:N-k if R[i].boot == R[i+k].boot && valid[i] && valid[i+k]]
        a = Dict{String,Any}(v => pearson([getv(R[i], v) for (i, _) in pr], [getv(R[j], v) for (_, j) in pr]) for v in ("w_sum", "w_n", "b_n", "t_mc"))
        a["pairs"] = length(pr)
        a["median_span_s"] = isempty(pr) ? NaN : med([up[j] - up[i] for (i, j) in pr])
        acs[string(k)] = a
        say("  ", lpad(k, 4), " ", join([r6(a[v]) for v in ("w_sum", "w_n", "b_n", "t_mc")], " "), " (", length(pr), " pairs, median span ", r6(a["median_span_s"]), " s)")
    end
    cc = [getv(R[i], "w_max") / getv(R[i], "w_sum") for i in 1:N if valid[i] && getv(R[i], "w_sum") > 0]
    conc = Dict("min" => minimum(cc), "q25" => qtl(cc, 0.25), "median" => med(cc), "q75" => qtl(cc, 0.75), "max" => maximum(cc), "n" => length(cc))
    say("w_max / w_sum: ", join([r6(conc[k]) for k in ("min", "q25", "median", "q75", "max")], " "), " (n ", length(cc), ")")
    c245 = pearson(V("w_24"), V("w_5")); cwb = pearson(V("w_sum"), V("b_n"))
    say("corr(w_24, w_5) ", r6(c245), "; corr(w_sum, b_n) ", r6(cwb))

    # ---------------- section 4: conversion candidates, exploration only ----------------
    ex = explore(R, valid)

    gates = Dict("G-F" => gf, "G-A0" => ga0, "G-BLIND" => gblind)
    say("gates: ", join(["$k " * (gates[k] ? "PASS" : "FAIL") for k in sort(collect(keys(gates)))], ", "), " (G-DET is checked by running twice)")
    S = Dict{String,Any}(
        "source" => Dict("file" => "copies/ambient-20261123.tsv", "sha256" => SRC_SHA, "read_up_to" => "first line whose summed uptime exceeds 259200 s (only boot and uptime_s parsed, discarded)"),
        "design" => Dict("rows" => N, "valid_rows" => count(valid), "summed_uptime_last_row" => cum[end], "sha256" => sha(dst)),
        "moves_file_sha256" => mvsha, "moves_entries" => nentries, "moves_place_unchanged" => nsame, "physical_moves" => length(PHYSICAL_MOVES),
        "gates" => gates, "a0" => a0, "boots" => btab,
        "PS1" => Dict("distinct_w_sum" => nws, "distinct_b_n" => nbn, "verdict" => ps1 ? "holds" : "miss"),
        "PS2" => Dict("days" => ps2rows, "usable_days" => nus, "bt_days" => bhold, "wifi_days" => whold, "bluetooth" => ps2b, "wifi" => ps2w,
            "sensitivity_recorded_clock_only" => Dict("days" => P2s.rows, "usable_days" => P2s.nus, "bluetooth" => P2s.b, "wifi" => P2s.w, "bt_days" => P2s.bhold, "wifi_days" => P2s.whold)),
        "PS3" => Dict("verdict" => ps3, "reason" => "no recorded change of place in s52-moves.txt (3 entries: reboot, power pull, clock reset; place unchanged)"),
        "PS4" => Dict("lag1_t_mc" => ac1, "lag1_pairs" => length(lx), "corr_t_mc_w_sum" => ctw, "first" => ps4a, "second" => ps4b),
        "PS5" => Dict("failed" => nfail, "rows" => N, "fail_pct" => 100 * ffrac, "max_gap_s" => mg, "fail_lt_2pct" => ps5a, "gap_le_120" => ps5b, "verdict" => ps5),
        "describe" => desc, "hourly_median" => hourly, "autocorr" => acs, "concentration" => conc, "corr_w24_w5" => c245, "corr_wsum_bn" => cwb,
        "explore" => ex)
    open(joinpath(OUT, "summary.json"), "w") do o; tojson(o, S); println(o); end
    say("summary.json sha ", sha(joinpath(OUT, "summary.json")), "; design_72h.tsv sha ", sha(dst))
    open(joinpath(OUT, "results.out"), "w") do o; foreach(l -> println(o, l), LOG); end
end

# deterministic JSON (sorted keys, shortest-roundtrip floats)
tojson(o, x::AbstractDict) = (print(o, "{"); ks = sort(collect(keys(x))); for (i, k) in enumerate(ks); i > 1 && print(o, ","); tojson(o, string(k)); print(o, ":"); tojson(o, x[k]); end; print(o, "}"))
tojson(o, x::AbstractVector) = (print(o, "["); for (i, v) in enumerate(x); i > 1 && print(o, ","); tojson(o, v); end; print(o, "]"))
tojson(o, x::AbstractString) = print(o, '"', escape_string(x), '"')
tojson(o, x::Bool) = print(o, x ? "true" : "false")
tojson(o, x::Integer) = print(o, x)
tojson(o, x::AbstractFloat) = isfinite(x) ? print(o, isinteger(x) && abs(x) < 1e15 ? string(Int(x)) : repr(Float64(x))) : print(o, "null")
tojson(o, x::Tuple) = tojson(o, collect(x))

# ---------------- predictors (same definitions as headroom_audit/audit.jl: RATE, B1, TAB4, LEAK) ----------------
const LO = 1 / 200; const HI = 199 / 200; const KDEC = 8; const W4 = 4; const ALPHA = 1.0; const ACTSEED = 520001
clip(p) = clamp(p, LO, HI)
code(act, Y, j) = j < 1 ? 0 : 2 * (act[j] - 1) + Int(Y[j]) + 1
function tabkey(act, Y, s, a)
    k = 0
    for j in s-W4:s-1; k = 5 * k + code(act, Y, j); end
    return 2 * k + a
end
# Y2: n x 2 Bool (the two compartments), split: 1..ntr train, ntr+1..n design-val
function score(Y2, ntr)
    n = size(Y2, 1); r = Mulberry(ACTSEED)
    act = [r() < 0.5 ? 1 : 2 for _ in 1:n]
    Y = [Y2[s, act[s]] for s in 1:n]
    cnt = [0, 0]; c1 = [0, 0]; tn = zeros(Int, 2 * 5^W4); tn1 = zeros(Int, 2 * 5^W4)
    for s in 1:ntr
        a = act[s]; cnt[a] += 1; c1[a] += Y[s]; k = tabkey(act, Y, s, a); tn[k] += 1; tn1[k] += Y[s]
    end
    rate = [(c1[a] + 1) / (cnt[a] + 2) for a in 1:2]
    names = ("RATE", "B1", "TAB4", "LEAK"); L = Dict(k => [0.0, 0.0] for k in names); na = [0, 0]
    m = [0.5, 0.5]
    for s in 1:n
        a = act[s]
        if s > ntr
            k = tabkey(act, Y, s, a)
            p = Dict("RATE" => clip(rate[a]), "B1" => clip(m[a]), "TAB4" => clip((tn1[k] + ALPHA * rate[a]) / (tn[k] + ALPHA)), "LEAK" => clip(Y[s] ? 1.0 : 0.0))
            na[a] += 1
            for kk in names; L[kk][a] += Y[s] ? -log(p[kk]) : -log(1 - p[kk]); end
        end
        m[a] += ((Y[s] ? 1.0 : 0.0) - m[a]) / KDEC
    end
    sc = Dict(k => (na[1] == 0 || na[2] == 0) ? NaN : (L[k][1] / na[1] + L[k][2] / na[2]) / 2 for k in names)
    return (sc = sc, na = na, rate_tr = [sum(Y2[1:ntr, k]) / ntr for k in 1:2], rate_val = [sum(Y2[ntr+1:n, k]) / (n - ntr) for k in 1:2],
            yrate_val = sum(Y[ntr+1:n]) / (n - ntr), act_frac1 = count(==(1), act) / n)
end

function explore(R, valid)
    # stream = valid rows in time order, the first dropped (C3 needs t-1) so all candidates share one split
    iv = findall(valid); g(name) = [getv(R[i], name) for i in iv]
    w24 = g("w_24"); w5 = g("w_5"); ws = g("w_sum"); bn = g("b_n"); rowidx = iv .- 1
    n0 = length(iv); n = n0 - 1; ntr = div(2 * n, 3)
    S = 2:n0                          # positions in the valid list used by the stream
    T = S[1:ntr]                      # train positions
    say("explore: stream ", n, " valid rows (first valid row dropped for C3), train ", ntr, ", design-val ", n - ntr,
        " (train summed-uptime share ~2/3 by row count; thresholds from train only)")
    thr(x, T) = med(x[T])
    function pick(x, T)   # '>' or '>=' the train median, whichever gives a train rate closer to 0.5
        m = thr(x, T); rg = sum(x[T] .> m) / length(T); re = sum(x[T] .>= m) / length(T)
        return abs(rg - 0.5) <= abs(re - 0.5) ? (m, ">", v -> v > m) : (m, ">=", v -> v >= m)
    end
    cands = Dict{String,Any}(); rows = []
    # C1
    c1note = ""
    if length(unique(w24[T])) > 1 && length(unique(w5[T])) > 1
        m1, o1, f1 = pick(w24, T); m2, o2, f2 = pick(w5, T)
        Y1 = hcat(f1.(w24[S]), f2.(w5[S])); c1note = "w_24 $o1 $m1, w_5 $o2 $m2 (train medians)"
    else
        hs = g("w_h4") .+ g("w_h5"); m1, o1, f1 = pick(ws, T); m2, o2, f2 = pick(hs, T)
        Y1 = hcat(f1.(ws[S]), f2.(hs[S]))
        c1note = "fallback (a band is constant in train: distinct w_24 $(length(unique(w24[T]))), w_5 $(length(unique(w5[T])))): w_sum $o1 $m1, strong-bin count w_h4+w_h5 $o2 $m2"
    end
    # C2 (as specified: '>' the train median)
    m3 = thr(ws, T); m4 = thr(bn, T)
    Y2 = hcat(ws[S] .> m3, bn[S] .> m4)
    # C3
    Y3 = hcat([ws[i] >= ws[i-1] for i in S], [bn[i] >= bn[i-1] for i in S])
    # C4: 2.5 + 2.5 sin(2 pi s / 1000 + phi_k) + 1.0 z_k > 0.5, s = 3 * (row index in the design file), phi = (0, pi)
    mu(x) = sum(x[T]) / length(T); sd(x) = sqrt(sum((x[T] .- mu(x)) .^ 2) / (length(T) - 1))
    z1 = (ws .- mu(ws)) ./ sd(ws); z2 = (bn .- mu(bn)) ./ sd(bn)
    sx(i, k, z) = 2.5 + 2.5 * sin(2pi * (3 * rowidx[i]) / 1000 + (k == 1 ? 0.0 : pi)) + 1.0 * z[i]
    Y4 = hcat([sx(i, 1, z1) > 0.5 for i in S], [sx(i, 2, z2) > 0.5 for i in S])
    defs = [("C1", Y1, c1note), ("C2", Y2, "w_sum > $m3, b_n > $m4 (train medians)"), ("C3", Y3, "w_sum(t) >= w_sum(t-1), b_n(t) >= b_n(t-1) (previous valid row)"),
            ("C4", Y4, "2.5+2.5 sin(2pi*3row/1000 + (0,pi)) + 1.0*z > 0.5, z from train mean $(r6(mu(ws)))/sd $(r6(sd(ws))) (w_sum), $(r6(mu(bn)))/$(r6(sd(bn))) (b_n)")]
    say("explore (design-val log loss, nat, mean over the two actions; exploration only, no claim): cand  P(Y1) P(Y2) train | val  P(Y obs) val  RATE  B1  TAB4  LEAK  RATE-B1  B1-TAB4")
    for (nm, Y, note) in defs
        r = score(Y, ntr)
        d1 = r.sc["RATE"] - r.sc["B1"]; d2 = r.sc["B1"] - r.sc["TAB4"]
        cands[nm] = Dict("definition" => note, "rate_train" => r.rate_tr, "rate_val" => r.rate_val, "yrate_val" => r.yrate_val, "n_val_by_action" => r.na,
            "loss" => r.sc, "RATE_minus_B1" => d1, "B1_minus_TAB4" => d2, "leak_lowest" => r.sc["LEAK"] < minimum(r.sc[k] for k in ("RATE", "B1", "TAB4")))
        say("  ", nm, ": ", note)
        say("      train ", r6.(r.rate_tr), " | val ", r6.(r.rate_val), "  obs ", r6(r.yrate_val), "  ", join([r6(r.sc[k]) for k in ("RATE", "B1", "TAB4", "LEAK")], " "),
            "  ", r6(d1), " ", r6(d2), "  (val n by action ", r.na, ", action-1 share ", r6(r.act_frac1), ")")
    end
    return Dict("n_stream" => n, "n_train" => ntr, "n_val" => n - ntr, "action_seed" => ACTSEED, "candidates" => cands)
end

main()
