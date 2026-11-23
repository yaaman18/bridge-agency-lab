# S65: the frozen C4 conversion (synthetic period + real radio perturbation) applied without refit to the confirmation period
# (second 72 h of summed uptime, 259200 s < c <= 518400 s). Spec ../../discussion/specs/S65-radio-conversion-confirm.md (r3),
# constants and predictions predictions.toml (frozen in ../freeze-radio-conversion.txt). Request: neon-lab 2026-11-23.
# Blinding: the source copy is read line by line from the top with the summed-uptime formula of analyze_72h.jl:41-60; the rows
# with c <= 259200 s are only hashed (must equal out-72h/design_72h.tsv), the rows with 259200 s < c <= 518400 s are written
# as they are to confirm_72h.tsv, and at the first line with c > 518400 s only boot and uptime_s are parsed, the line is
# discarded and the file is closed. Every later step reads only design_72h.tsv and confirm_72h.tsv.
# Usage: julia --project=../.. confirm_c4.jl out | out-rerun      (gates G-F G-A0 G-BLIND G-DESIGN G-LEAK, evaluation)
#        julia --project=../.. confirm_c4.jl final               (G-DET out vs out-rerun, G-CORE, final verdicts)
using SHA, TOML

const HERE = @__DIR__
const ROOT = normpath(joinpath(HERE, "..", ".."))
const EXP = joinpath(ROOT, "experiments")
const LOG = String[]
say(xs...) = (s = string(xs...); push!(LOG, s); println(s))
sha(f) = bytes2hex(open(sha256, f))

include(joinpath(ROOT, "core", "LabCore.jl")); using .LabCore: Mulberry

const PR = TOML.parsefile(joinpath(HERE, "predictions.toml"))
const SRC = joinpath(ROOT, PR["source"]["raw_copy"]); const SRC_SHA = PR["source"]["raw_copy_sha256"]
const DESIGN = joinpath(ROOT, PR["source"]["design_tsv"]); const DESIGN_SHA = PR["source"]["design_tsv_sha256"]
const LIMIT = PR["source"]["design_limit_s"]; const CLIMIT = PR["source"]["confirm_limit_s"]
const CV = PR["conversion_c4"]; const SEED = PR["rng_seeds"]; const EV = PR["evaluation"]
const MU_W = CV["mu_w"]; const SD_W = CV["sd_w"]; const MU_B = CV["mu_b"]; const SD_B = CV["sd_b"]
const LO = EV["clip_lo"]; const HI = EV["clip_hi"]; const KDEC = EV["b1_decay_k"]; const W4 = EV["tab4_window"]; const ALPHA = EV["tab4_alpha"]
const HEADER = "pi_s\tboot\tuptime_s\tt_mc\tw_n\tw_max\tw_sum\tw_24\tw_5\tw_h1\tw_h2\tw_h3\tw_h4\tw_h5\tb_n\tb_max\tb_r\tb_h1\tb_h2\tb_h3\tb_h4\tw_ms\tb_ms\tfail"
const COLS = split(HEADER, '\t')
col(name) = findfirst(==(name), COLS)
r6(x) = isnan(x) ? "NaN" : string(round(x; digits = 6))
r9(x) = isnan(x) ? "NaN" : string(round(x; digits = 9))
const SERIES = ("C4_full", "C4_noradio", "C4_zshuf", "C4_radio_only")
const PREDS = ("RATE", "B1", "TAB4", "LEAK")

# ---------------- G-F ----------------
function gate_f()
    ok = true
    for l in readlines(joinpath(EXP, "freeze-radio-conversion.txt"))
        h, f = split(l); got = sha(normpath(joinpath(EXP, f)))
        say("G-F ", f, ": frozen ", h[1:12], " now ", got[1:12], got == h ? " ok" : " DIFFERS"); ok &= got == h
    end
    fz = readlines(joinpath(EXP, "freeze-ambient-log.txt"))
    i = findfirst(l -> startswith(l, "# S52 freeze 1"), fz)
    for l in fz[i+1:i+2]
        h, f = split(l); got = sha(normpath(joinpath(EXP, f)))
        say("G-F (S52 freeze 1) ", f, ": frozen ", h[1:12], " now ", got[1:12], got == h ? " ok" : " DIFFERS"); ok &= got == h
    end
    return ok
end

# ---------------- scanner (the only reader of the source copy) ----------------
function scan(dst)
    sha(SRC) == SRC_SHA || error("source sha differs")
    dio = IOBuffer(); println(dio, HEADER)
    nd = 0; nc = 0; cum = 0.0; base = 0.0; curboot = ""; u0 = 0.0; uprev = 0.0
    reversals = 0; stopped = false; boundary = nothing; overlap = 0; lastc = NaN
    open(SRC) do io
        readline(io) == HEADER || error("source header differs")
        open(dst, "w") do o
            println(o, HEADER)
            while !eof(io)
                l = readline(io)
                f = split(l, '\t'; limit = 4)
                b = String(f[2]); u = parse(Float64, f[3])
                if b != curboot
                    curboot = b; u0 = u; base = cum
                elseif u < uprev
                    reversals += 1; break          # G-BLIND FAIL: stop at once, nothing of this line is kept
                end
                c = base + (u - u0)
                if c > CLIMIT; stopped = true; break; end   # first line beyond 144 h: only boot/uptime_s parsed, discarded
                if c <= LIMIT
                    boundary === nothing || (overlap += 1)
                    println(dio, l); nd += 1
                else
                    boundary === nothing && (boundary = (boot = b, uptime_s = u, cum = c))
                    println(o, l); nc += 1; lastc = c
                end
                cum = c; uprev = u
            end
        end
    end
    return (design_rows = nd, design_sha = bytes2hex(sha256(take!(dio))), confirm_rows = nc, boundary = boundary,
            last_cum = lastc, reversals = reversals, stopped = stopped, overlap = overlap)
end

# ---------------- reading the sliced files ----------------
struct Row; v::Vector{Float64}; boot::String; end
getv(r::Row, name) = r.v[col(name)]
function readrows(f)
    ls = readlines(f); ls[1] == HEADER || error("header of ", basename(f))
    rows = Row[]
    for l in ls[2:end]
        x = split(l, '\t'); length(x) == 24 || error(basename(f), ": ", length(x), " columns")
        push!(rows, Row([i == 2 ? NaN : (x[i] == "NA" ? NaN : parse(Float64, x[i])) for i in 1:24], String(x[2])))
    end
    return rows
end
isvalid(r::Row) = getv(r, "fail") == 0 && !isnan(getv(r, "w_sum")) && !isnan(getv(r, "b_n"))

# ---------------- statistics ----------------
function qtl(xs, p)   # type 7
    s = sort(xs); n = length(s); h = (n - 1) * p + 1; lo = floor(Int, h); hi = min(lo + 1, n)
    return s[lo] + (h - lo) * (s[hi] - s[lo])
end
mean(x) = sum(x) / length(x)
sdev(x) = (m = mean(x); sqrt(sum((x .- m) .^ 2) / (length(x) - 1)))

# ---------------- the C4 conversion and the four series (spec section 2, 3) ----------------
const PHI = (CV["phi_1"], CV["phi_2"])
synth(k, a) = CV["base_M"] + CV["amp_A"] * sin(2.0 * pi * (CV["steps_per_row"] * k) / CV["period_P"] + PHI[a])
yld(x) = clamp(round(x), CV["yield_min"], CV["yield_max"])
function fisher_yates(n, seed)
    r = Mulberry(seed); p = collect(1:n)
    for i in n:-1:2; j = floor(Int, r() * i) + 1; p[i], p[j] = p[j], p[i]; end
    return p
end
# ws, bn: valid rows of one period in time order; k = 0..n-1 is the valid-row number
function series(ws, bn, zseed)
    n = length(ws); z = hcat((ws .- MU_W) ./ SD_W, (bn .- MU_B) ./ SD_B); p = fisher_yates(n, zseed)
    g = Dict{String,Matrix{Float64}}()
    g["C4_full"] = [yld(synth(k - 1, a) + CV["sigma"] * z[k, a]) for k in 1:n, a in 1:2]
    g["C4_noradio"] = [yld(synth(k - 1, a)) for k in 1:n, a in 1:2]
    g["C4_zshuf"] = [yld(synth(k - 1, a) + CV["sigma"] * z[p[k], a]) for k in 1:n, a in 1:2]
    Y = Dict{String,Matrix{Bool}}(s => g[s] .> 0 for s in ("C4_full", "C4_noradio", "C4_zshuf"))
    Y["C4_radio_only"] = z .> 0
    return (Y = Y, g = g, z = z, perm = p)
end
actions(n, seed) = (r = Mulberry(seed); [r() < 0.5 ? 1 : 2 for _ in 1:n])

# ---------------- predictors (definitions of headroom_audit/audit.jl and analyze_72h.jl) ----------------
clip(p) = clamp(p, LO, HI)
code(act, Y, j) = j < 1 ? 0 : 2 * (act[j] - 1) + Int(Y[j]) + 1     # before the period's first row: 0
function tabkey(act, Y, s, a)
    k = 0
    for j in s-W4:s-1; k = 5 * k + code(act, Y, j); end
    return 2 * k + a
end
struct Trained; rate::Vector{Float64}; n::Vector{Int}; n1::Vector{Int}; tn::Vector{Int}; tn1::Vector{Int}; end
function train(act, Y)
    n = [0, 0]; n1 = [0, 0]; tn = zeros(Int, 2 * 5^W4); tn1 = zeros(Int, 2 * 5^W4)
    for s in eachindex(act)
        a = act[s]; n[a] += 1; n1[a] += Y[s]; k = tabkey(act, Y, s, a); tn[k] += 1; tn1[k] += Y[s]
    end
    return Trained([(n1[a] + 1) / (n[a] + 2) for a in 1:2], n, n1, tn, tn1)
end
# RATE and TAB4 frozen from the design period; B1 from m = [0.5, 0.5] at the first confirmation row
function predict(act, Y0, tr; flip = 0)
    Y = copy(Y0); flip > 0 && (Y[flip] = !Y[flip])
    n = length(act); p = Dict(k => zeros(n) for k in PREDS); l = Dict(k => zeros(n) for k in PREDS); mnext = zeros(n)
    m = [0.5, 0.5]
    for s in 1:n
        a = act[s]; k = tabkey(act, Y, s, a)
        p["RATE"][s] = clip(tr.rate[a]); p["B1"][s] = clip(m[a])
        p["TAB4"][s] = clip((tr.tn1[k] + ALPHA * tr.rate[a]) / (tr.tn[k] + ALPHA)); p["LEAK"][s] = clip(Y[s] ? 1.0 : 0.0)
        for kk in PREDS; l[kk][s] = Y[s] ? -log(p[kk][s]) : -log(1 - p[kk][s]); end
        m[a] += ((Y[s] ? 1.0 : 0.0) - m[a]) / KDEC; mnext[s] = m[a]
    end
    return (p = p, l = l, mnext = mnext)
end
# mean over the two actions of the mean loss of the rows of that action
score(l, act) = (sum(l[act .== 1]) / count(==(1), act) + sum(l[act .== 2]) / count(==(2), act)) / 2

# ---------------- block bootstrap (spec section 3) ----------------
# sums of the row losses per block and action, over the first nb*L rows (the rest dropped)
function blocksums(l, act, L, nb)
    S = zeros(nb, 2); C = zeros(Int, nb, 2)
    for b in 1:nb, s in (b-1)*L+1:b*L; S[b, act[s]] += l[s]; C[b, act[s]] += 1; end
    return (S = S, C = C)
end
function bootstrap(P, act, L)
    n = length(act); nb = n ÷ L; rest = n - nb * L
    bs = Dict((s, k) => blocksums(P[s].l[k], act, L, nb) for s in SERIES for k in ("RATE", "B1", "TAB4"))
    r = Mulberry(SEED["block_bootstrap"]); B = EV["bootstrap_B"]
    stats = ("D_full", "D_noradio", "D_zshuf", "D_radio_only", "D_shuf", "B1_zshuf_minus_full", "B1_minus_TAB4_full")
    out = Dict(k => zeros(B) for k in stats)
    idx = zeros(Int, nb)
    for rep in 1:B
        for i in 1:nb; idx[i] = floor(Int, r() * nb) + 1; end   # one draw per L, shared by every series and statistic
        Ls = Dict{Tuple{String,String},Float64}()
        for (key, v) in bs
            s1 = 0.0; s2 = 0.0; c1 = 0; c2 = 0
            for i in idx; s1 += v.S[i, 1]; s2 += v.S[i, 2]; c1 += v.C[i, 1]; c2 += v.C[i, 2]; end
            Ls[key] = (s1 / c1 + s2 / c2) / 2
        end
        d(s) = Ls[(s, "RATE")] - Ls[(s, "B1")]
        out["D_full"][rep] = d("C4_full"); out["D_noradio"][rep] = d("C4_noradio"); out["D_zshuf"][rep] = d("C4_zshuf")
        out["D_radio_only"][rep] = d("C4_radio_only"); out["D_shuf"][rep] = d("C4_full") - d("C4_zshuf")
        out["B1_zshuf_minus_full"][rep] = Ls[("C4_zshuf", "B1")] - Ls[("C4_full", "B1")]
        out["B1_minus_TAB4_full"][rep] = Ls[("C4_full", "B1")] - Ls[("C4_full", "TAB4")]
    end
    ci = Dict(k => Dict("lo" => qtl(out[k], 0.025), "hi" => qtl(out[k], 0.975)) for k in stats)
    return (L = L, blocks = nb, dropped_rows = rest, ci = ci)
end

# ---------------- run ----------------
function run(outname)
    OUT = joinpath(HERE, outname); mkpath(OUT)
    dst = joinpath(OUT, "confirm_72h.tsv")
    S = Dict{String,Any}("spec" => PR["meta"]["spec"] * " " * PR["meta"]["spec_rev"], "phenomenal_claim" => "not_certified")
    gates = Dict{String,Bool}()
    say("S65 C4 confirmation period (259200 s < summed uptime <= 518400 s), no refit")
    gates["G-F"] = gate_f()

    sc = scan(dst)
    say("scanner: design-slice rows ", sc.design_rows, " sha ", sc.design_sha[1:12], " (design_72h.tsv frozen ", DESIGN_SHA[1:12], ", file now ", sha(DESIGN)[1:12], ")")
    say("scanner: confirmation rows written ", sc.confirm_rows, ", summed uptime at the last written row ", r6(sc.last_cum),
        " s, uptime reversals within a boot ", sc.reversals, ", stopped at the first line beyond ", CLIMIT, " s: ", sc.stopped)
    sc.boundary === nothing || say("scanner: first line beyond ", LIMIT, " s (discarded by analyze_72h.jl): boot ", sc.boundary.boot, " uptime_s ", sc.boundary.uptime_s, " cum ", r6(sc.boundary.cum))
    S["scanner"] = Dict("design_rows" => sc.design_rows, "design_slice_sha256" => sc.design_sha, "confirm_rows" => sc.confirm_rows,
        "last_cum" => sc.last_cum, "reversals" => sc.reversals, "stopped_beyond_confirm_limit" => sc.stopped)
    if sc.reversals > 0
        gates["G-BLIND"] = false; say("G-BLIND FAIL: uptime reversal within a boot; stopped"); return finish(OUT, S, gates, nothing)
    end

    a0 = strip(read(ignorestatus(`sh $(joinpath(EXP, "ambient", "check_ambient.sh")) a0 $dst`), String))
    say("G-A0: ", a0); gates["G-A0"] = startswith(a0, "A0 PASS"); S["a0"] = a0

    D = readrows(DESIGN); C = readrows(dst)
    # summed uptime recomputed from the two files, same formula
    allr = vcat(D, C); N = length(allr); cum = zeros(N); base = 0.0; u0 = getv(allr[1], "uptime_s")
    for i in 2:N
        allr[i].boot != allr[i-1].boot && (base = cum[i-1]; u0 = getv(allr[i], "uptime_s"))
        cum[i] = base + (getv(allr[i], "uptime_s") - u0)
    end
    cd = cum[1:length(D)]; cc = cum[length(D)+1:end]
    dkeys = Set((r.boot, getv(r, "uptime_s")) for r in D); ckeys = [(r.boot, getv(r, "uptime_s")) for r in C]
    dfail0 = count(r -> getv(r, "fail") == 0, D)
    first_ok = sc.boundary !== nothing && !isempty(C) && C[1].boot == sc.boundary.boot && getv(C[1], "uptime_s") == sc.boundary.uptime_s && cc[1] == sc.boundary.cum
    b1 = sc.reversals == 0
    b2 = sc.design_sha == DESIGN_SHA && sha(DESIGN) == DESIGN_SHA && sc.design_rows == length(D) == 8643 && dfail0 == length(D) && first_ok
    b3 = !isempty(C) && cc[end] <= CLIMIT && sc.last_cum == cc[end] && all(>(LIMIT), cc) && cd[end] <= LIMIT && sc.overlap == 0 &&
         count(in(dkeys), ckeys) == 0 && sc.confirm_rows == length(C)
    say("G-BLIND (1) reversals 0: ", b1, "; (2) design slice sha == design_72h.tsv, 8643 rows, fail==0 ", dfail0, "/", length(D),
        ", boundary line == first confirmation row (boot, uptime_s, cum ", r6(isempty(cc) ? NaN : cc[1]), "): ", b2,
        "; (3) last cum ", r6(isempty(cc) ? NaN : cc[end]), " <= ", CLIMIT, ", all confirmation cum > ", LIMIT, ", shared (boot, uptime_s) with the design 0, nothing beyond ", CLIMIT, " written: ", b3)
    gates["G-BLIND"] = b1 && b2 && b3

    wsd = [getv(r, "w_sum") for r in D]; bnd = [getv(r, "b_n") for r in D]
    rec = (mean(wsd), sdev(wsd), mean(bnd), sdev(bnd)); frz = (MU_W, SD_W, MU_B, SD_B)
    dev = maximum(abs.(rec .- frz))
    say("G-DESIGN: recomputed mu_w ", repr(rec[1]), " sd_w ", repr(rec[2]), " mu_b ", repr(rec[3]), " sd_b ", repr(rec[4]), "; max |recomputed - frozen| ", dev, " (<= 1e-12)")
    gates["G-DESIGN"] = dev <= 1e-12
    S["design_recomputed"] = Dict("mu_w" => rec[1], "sd_w" => rec[2], "mu_b" => rec[3], "sd_b" => rec[4], "max_abs_dev" => dev)

    # ---------- series, training on the design period, prediction on the confirmation period ----------
    vc = [isvalid(r) for r in C]; CV_ = C[vc]; n = length(CV_)
    sd_ = series(wsd, bnd, SEED["zshuf_design"])
    sc_ = series([getv(r, "w_sum") for r in CV_], [getv(r, "b_n") for r in CV_], SEED["zshuf_confirm"])
    actd = actions(length(D), SEED["action_design"]); actc = actions(n, SEED["action_confirm"])
    obs(Y, act) = [Y[s, act[s]] for s in eachindex(act)]
    TR = Dict(s => train(actd, obs(sd_.Y[s], actd)) for s in SERIES)
    Yo = Dict(s => obs(sc_.Y[s], actc) for s in SERIES)
    P = Dict(s => predict(actc, Yo[s], TR[s]) for s in SERIES)
    L = Dict(s => Dict(k => score(P[s].l[k], actc) for k in PREDS) for s in SERIES)
    for s in SERIES
        say("train ", rpad(s, 13), " (design, ", length(D), " rows, action seed ", SEED["action_design"], "): examples ", TR[s].n, ", answered ", TR[s].n1,
            ", RATE ", r9.(TR[s].rate), ", TAB4 keys seen ", count(>(0), TR[s].tn), "/", length(TR[s].tn))
    end

    # ---------- G-LEAK ----------
    gl = true; target = -log(HI); fr = [div(j * n, EV["flip_check_rows"]) + 1 for j in 0:EV["flip_check_rows"]-1]
    S["leak"] = Dict{String,Any}("flip_rows_1based" => fr)
    for s in SERIES
        lk = L[s]["LEAK"]; e1 = abs(lk - target) <= EV["leak_tol"]; e2 = lk < minimum(L[s][k] for k in ("RATE", "B1", "TAB4"))
        same = 0; moved = 0
        for k in fr
            Q = predict(actc, Yo[s], TR[s]; flip = k)
            same += all(kk -> Q.p[kk][k] === P[s].p[kk][k], ("RATE", "B1", "TAB4")); moved += Q.mnext[k] != P[s].mnext[k]
        end
        ok = e1 && e2 && same == length(fr) && moved == length(fr); gl &= ok
        say("G-LEAK ", rpad(s, 13), ": L(LEAK) ", repr(lk), " |-(-log 0.995)| ", abs(lk - target), " (<= 1e-9) ", e1, ", lowest ", e2,
            "; flip ", length(fr), " rows: p_k unchanged (RATE B1 TAB4, bitwise) ", same, ", B1 next state moved ", moved, " -> ", ok)
        S["leak"][s] = Dict("L_LEAK" => lk, "dev" => abs(lk - target), "lowest" => e2, "p_unchanged" => same, "b1_moved" => moved, "pass" => ok)
    end
    gates["G-LEAK"] = gl
    if !all(values(gates))
        say("a gate failed: evaluation stopped, P-S65-2..5 UNDECIDED"); return finish(OUT, S, gates, nothing)
    end

    # ---------- descriptive ----------
    nraw = length(C); nex = nraw - n
    exr = Dict(string(Int(getv(r, "fail"))) => 0 for r in C if !isvalid(r))
    for r in C; isvalid(r) || (exr[string(Int(getv(r, "fail")))] += 1); end
    gap(rows) = maximum([getv(rows[i], "uptime_s") - getv(rows[i-1], "uptime_s") for i in 2:length(rows) if rows[i].boot == rows[i-1].boot]; init = 0.0)
    gall = gap(C); gval = gap(CV_)
    say("confirmation: rows ", nraw, ", valid ", n, ", excluded ", nex, " = ", r6(100 * nex / nraw), " % (by fail mark ", sort(collect(exr)), ")")
    say("confirmation: max interval within a boot, all rows ", r6(gall), " s, valid rows ", r6(gval), " s")
    boots = String[]; for r in C; (isempty(boots) || boots[end] != r.boot) && push!(boots, r.boot); end
    btab = Dict{String,Any}[]
    say("boots of the confirmation period: boot rows valid up_first up_last cum_first cum_last")
    for b in boots
        ix = findall(r -> r.boot == b, C)
        push!(btab, Dict("boot" => b, "rows" => length(ix), "valid" => count(vc[ix]), "uptime_first" => getv(C[ix[1]], "uptime_s"),
            "uptime_last" => getv(C[ix[end]], "uptime_s"), "cum_first" => cc[ix[1]], "cum_last" => cc[ix[end]]))
        say("  ", b, " ", length(ix), " ", count(vc[ix]), " ", getv(C[ix[1]], "uptime_s"), " ", getv(C[ix[end]], "uptime_s"), " ", r6(cc[ix[1]]), " ", r6(cc[ix[end]]))
    end
    wsc = [getv(r, "w_sum") for r in CV_]; bnc = [getv(r, "b_n") for r in CV_]
    shift = Dict("w_sum" => Dict("design_mean" => mean(wsd), "design_sd" => sdev(wsd), "confirm_mean" => mean(wsc), "confirm_sd" => sdev(wsc),
                                 "mean_shift_in_design_sd" => (mean(wsc) - mean(wsd)) / sdev(wsd)),
                 "b_n" => Dict("design_mean" => mean(bnd), "design_sd" => sdev(bnd), "confirm_mean" => mean(bnc), "confirm_sd" => sdev(bnc),
                               "mean_shift_in_design_sd" => (mean(bnc) - mean(bnd)) / sdev(bnd)))
    for v in ("w_sum", "b_n")
        x = shift[v]; say("shift ", v, ": design mean ", r6(x["design_mean"]), " sd ", r6(x["design_sd"]), " | confirmation mean ", r6(x["confirm_mean"]),
            " sd ", r6(x["confirm_sd"]), " | mean shift ", r6(x["mean_shift_in_design_sd"]), " design sd")
    end
    rates = Dict(s => [mean(sc_.Y[s][:, a]) for a in 1:2] for s in SERIES)
    for s in SERIES; say("response rate P(Y_a=1) over valid rows ", rpad(s, 13), ": ", r6.(rates[s]), " (design ", r6.([mean(sd_.Y[s][:, a]) for a in 1:2]), ")"); end
    gdist = [[count(==(Float64(v)), sc_.g["C4_full"][:, a]) for v in 0:5] for a in 1:2]
    distinct = [count(>(0), gdist[a]) for a in 1:2]
    say("C4_full yields g = 0..5 counts: compartment 1 ", gdist[1], ", compartment 2 ", gdist[2], "; distinct ", distinct)
    flip = [mean(sc_.Y["C4_full"][:, a] .!= sc_.Y["C4_noradio"][:, a]) for a in 1:2]
    gdiff = [mean(abs.(sc_.g["C4_full"][:, a] .- sc_.g["C4_noradio"][:, a])) for a in 1:2]
    say("radio_flip_rate (C4_full vs C4_noradio) ", r6.(flip), "; mean|g_full - g_noradio| ", r6.(gdiff))
    say("losses on the confirmation period (nat, mean over the two actions; actions ", count(==(1), actc), "/", count(==(2), actc), ", seed ", SEED["action_confirm"], "): series RATE B1 TAB4 LEAK | RATE-B1 B1-TAB4")
    for s in SERIES
        say("  ", rpad(s, 13), " ", join([r9(L[s][k]) for k in PREDS], " "), " | ", r9(L[s]["RATE"] - L[s]["B1"]), " ", r9(L[s]["B1"] - L[s]["TAB4"]))
    end
    dshuf = (L["C4_full"]["RATE"] - L["C4_full"]["B1"]) - (L["C4_zshuf"]["RATE"] - L["C4_zshuf"]["B1"])
    b1z = L["C4_zshuf"]["B1"] - L["C4_full"]["B1"]
    say("point: D_shuf ", r9(dshuf), ", L_B1(zshuf) - L_B1(full) ", r9(b1z))

    BS = [bootstrap(P, actc, Lb) for Lb in EV["block_lengths"]]
    say("block bootstrap (B ", EV["bootstrap_B"], ", seed ", SEED["block_bootstrap"], " fresh for every L, indices shared by all series; 95 % CI type 7): L blocks dropped | stat [lo, hi]")
    for b in BS
        say("  L ", b.L, ": ", b.blocks, " blocks, ", b.dropped_rows, " rows dropped")
        for k in sort(collect(keys(b.ci))); say("      ", rpad(k, 20), " [", r9(b.ci[k]["lo"]), ", ", r9(b.ci[k]["hi"]), "]"); end
    end
    minlo(k) = minimum(b.ci[k]["lo"] for b in BS)

    # ---------- verdicts ----------
    q1 = n >= EV["min_valid_rows"]; q2 = nex / nraw < EV["max_excl_frac"]; q3 = gall <= EV["max_gap_s"] && gval <= EV["max_gap_s"]
    quality = q1 && q2 && q3
    p2 = all(a -> EV["rate_lo"] <= rates["C4_full"][a] <= EV["rate_hi"] && distinct[a] >= EV["min_distinct_yields"], 1:2)
    p3 = all(>=(EV["min_radio_flip_rate"]), flip)
    p4a = minlo("D_full") > EV["min_delta_full_ci_lo"]; p4b = minlo("D_radio_only") > 0; p4c = minlo("D_shuf") > 0
    d5 = L["C4_full"]["B1"] - L["C4_full"]["TAB4"]
    v(x) = x ? "holds" : "miss"
    V = Dict("P_S65_1_quality" => Dict("valid_rows" => n, "valid_ge_7000" => q1, "excl_frac" => nex / nraw, "excl_lt_2pct" => q2,
                                       "max_gap_all_s" => gall, "max_gap_valid_s" => gval, "gap_le_120" => q3, "quality" => quality),
             "P_S65_2" => v(p2), "P_S65_3" => v(p3),
             "P_S65_4" => Dict("a_min_lo_D_full" => minlo("D_full"), "a" => v(p4a), "b_min_lo_D_radio_only" => minlo("D_radio_only"), "b" => v(p4b),
                               "c_min_lo_D_shuf" => minlo("D_shuf"), "c" => v(p4c), "verdict" => v(p4a && p4b && p4c),
                               "min_lo_D_noradio" => minlo("D_noradio"), "min_lo_B1_zshuf_minus_full" => minlo("B1_zshuf_minus_full")),
             "P_S65_5" => Dict("B1_minus_TAB4" => d5, "verdict" => d5 > 0 ? "holds" : (d5 < 0 ? "miss" : "tie")))
    say("P-S65-1 quality: valid ", n, " (>= 7000) ", q1, ", excluded ", r6(100 * nex / nraw), " % (< 2 %) ", q2, ", max interval all/valid ", r6(gall), "/", r6(gval), " s (<= 120) ", q3)
    say("P-S65-2: C4_full rates ", r6.(rates["C4_full"]), " in [0.15, 0.90], distinct yields ", distinct, " (>= 4): ", v(p2))
    say("P-S65-3: radio_flip_rate ", r6.(flip), " (>= 0.05 both): ", v(p3))
    say("P-S65-4: min over L of CI lo: (a) D_full ", r9(minlo("D_full")), " (> 0.05) ", v(p4a), "; (b) D_radio_only ", r9(minlo("D_radio_only")), " (> 0) ", v(p4b),
        "; (c) D_shuf ", r9(minlo("D_shuf")), " (> 0) ", v(p4c), " -> ", v(p4a && p4b && p4c))
    say("    alongside: min CI lo D_noradio ", r9(minlo("D_noradio")), ", L_B1(zshuf)-L_B1(full) ", r9(minlo("B1_zshuf_minus_full")))
    say("P-S65-5: L(B1) - L(TAB4) on C4_full (point) ", r9(d5), ": ", V["P_S65_5"]["verdict"])
    merge!(S, Dict("confirm" => Dict("rows" => nraw, "valid" => n, "excluded" => nex, "excluded_by_fail_mark" => exr, "max_gap_all_s" => gall,
                                     "max_gap_valid_s" => gval, "boots" => btab, "first_cum" => cc[1], "last_cum" => cc[end]),
                   "shift" => shift, "response_rate" => rates, "yield_counts_C4_full" => gdist, "distinct_yields_C4_full" => distinct,
                   "radio_flip_rate" => flip, "mean_abs_g_full_minus_noradio" => gdiff,
                   "train" => Dict(s => Dict("rate" => TR[s].rate, "n" => TR[s].n, "n1" => TR[s].n1, "tab4_keys_seen" => count(>(0), TR[s].tn)) for s in SERIES),
                   "loss" => L, "actions_confirm" => [count(==(1), actc), count(==(2), actc)], "D_shuf_point" => dshuf, "B1_zshuf_minus_full_point" => b1z,
                   "bootstrap" => [Dict("L" => b.L, "blocks" => b.blocks, "dropped_rows" => b.dropped_rows, "ci" => b.ci) for b in BS]))
    return finish(OUT, S, gates, V)
end

function finish(OUT, S, gates, V)
    for g in ("G-F", "G-A0", "G-BLIND", "G-DESIGN", "G-LEAK"); haskey(gates, g) || (gates[g] = false); end
    say("gates in this run: ", join(["$k " * (gates[k] ? "PASS" : "FAIL") for k in sort(collect(keys(gates)))], ", "), " (G-DET and G-CORE: confirm_c4.jl final)")
    S["gates"] = gates
    if V === nothing
        S["verdicts_if_det_core_pass"] = Dict("P_S65_1" => "miss", "P_S65_2" => "UNDECIDED", "P_S65_3" => "UNDECIDED", "P_S65_4" => "UNDECIDED", "P_S65_5" => "UNDECIDED")
    else
        S["verdicts_if_det_core_pass"] = V
    end
    open(joinpath(OUT, "summary.json"), "w") do o; tojson(o, S); println(o); end
    say("confirm_72h.tsv sha ", sha(joinpath(OUT, "confirm_72h.tsv")), "; summary.json sha ", sha(joinpath(OUT, "summary.json")))
    open(joinpath(OUT, "results.out"), "w") do o; foreach(l -> println(o, l), LOG); end
end

# ---------------- final: G-DET, G-CORE ----------------
function final()
    ok = true
    for f in ("confirm_72h.tsv", "summary.json", "results.out")
        a = sha(joinpath(HERE, "out", f)); b = sha(joinpath(HERE, "out-rerun", f)); ok &= a == b
        say("G-DET ", f, ": out ", a[1:16], " out-rerun ", b[1:16], a == b ? " same" : " DIFFERS")
    end
    say("G-DET ", ok ? "PASS" : "FAIL")
    core = success(pipeline(Cmd(`sh core/check/run.sh`; dir = ROOT); stdout = devnull, stderr = devnull))
    bp = expanduser("~/bridge-protocol")
    st = read(`git -C $bp status --porcelain`, String) * read(`git -C $bp diff`, String) * read(`git -C $bp rev-parse HEAD`, String)
    bpsha = bytes2hex(sha256(st)); before = length(ARGS) >= 2 ? ARGS[2] : ""
    say("G-CORE: core/check/run.sh exit 0 ", core, "; bridge-protocol status+diff+HEAD sha ", bpsha[1:16], " before ", isempty(before) ? "-" : before[1:16], " same ", bpsha == before)
    gc = core && bpsha == before; say("G-CORE ", gc ? "PASS" : "FAIL")
    rl = readlines(joinpath(HERE, "out", "results.out"))
    g5 = any(l -> startswith(l, "gates in this run:") && !occursin("FAIL", l), rl)
    say("all 7 gates: ", g5 && ok && gc ? "PASS" : "FAIL", " -> P-S65-2..5 ", g5 && ok && gc ? "decided by out/summary.json verdicts_if_det_core_pass" : "UNDECIDED")
    open(joinpath(HERE, "out", "final.out"), "w") do o; foreach(l -> println(o, l), LOG); end
end

tojson(o, x::AbstractDict) = (print(o, "{"); ks = sort(collect(keys(x)); by = string); for (i, k) in enumerate(ks); i > 1 && print(o, ","); tojson(o, string(k)); print(o, ":"); tojson(o, x[k]); end; print(o, "}"))
tojson(o, x::AbstractVector) = (print(o, "["); for (i, v) in enumerate(x); i > 1 && print(o, ","); tojson(o, v); end; print(o, "]"))
tojson(o, x::AbstractString) = print(o, '"', escape_string(x), '"')
tojson(o, x::Bool) = print(o, x ? "true" : "false")
tojson(o, x::Integer) = print(o, x)
tojson(o, x::AbstractFloat) = isfinite(x) ? print(o, isinteger(x) && abs(x) < 1e15 ? string(Int(x)) : repr(Float64(x))) : print(o, "null")
tojson(o, x::Tuple) = tojson(o, collect(x))
tojson(o, x::Pair) = tojson(o, [x.first, x.second])

length(ARGS) in (1, 2) || error("usage: confirm_c4.jl out | out-rerun | final")
ARGS[1] == "final" ? final() : (ARGS[1] in ("out", "out-rerun") ? run(ARGS[1]) : error("unknown target ", ARGS[1]))
