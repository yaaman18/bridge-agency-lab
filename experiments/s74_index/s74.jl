# S74 dev (discussion/specs/S74-draft-context-index-dev.md): L-IDX = active cumulative table + sealed archive (predict only)
# + 500-example window challenger; split / return decided from forward losses with a refractory period of W examples.
# Includes S73 (which includes S72 r4) unchanged. usage: julia --project=. -t 8 experiments/s74_index/s74.jl run
include(joinpath(@__DIR__, "..", "s73_selfclock", "s73.jl"))

const OUT74 = joinpath(@__DIR__, "out"); mkpath(OUT74)
const WIDX = 500; const ETA_C = [0.005, 0.01, 0.02, 0.04]; const ETA = Ref(0.0)

mutable struct Tab; id::Int; n::Vector{Float64}; n1::Vector{Float64}; rn::Vector{Float64}; rn1::Vector{Float64}; lb::Vector{Float64}; end
mutable struct IdxL
    act::Tab; arch::Vector{Tab}
    cn::Vector{Float64}; cn1::Vector{Float64}; crn::Vector{Float64}; crn1::Vector{Float64}; cbuf::Vector{Tuple{Int,Int,Bool}}; clb::Vector{Float64}
    t::Int; last::Int; nextid::Int; eta::Float64; events::Vector{Tuple{Int,Symbol,Int}}
end
newtab(id) = Tab(id, zeros(2), zeros(2), zeros(130), zeros(130), Float64[])
newidx() = IdxL(newtab(1), Tab[], zeros(2), zeros(2), zeros(130), zeros(130), Tuple{Int,Int,Bool}[], Float64[], 0, 0, 2, ETA[], Tuple{Int,Symbol,Int}[])
new_learner4(kind, life) = kind == "IDX" ? newidx() :
    kind == "WIN" ? WinL(zeros(2), zeros(2), zeros(130), zeros(130), Tuple{Int,Int,Bool}[]) : new_learner(kind, life)
pcount(n, n1, rn, rn1, a, k) = clip((rn1[k] + ALPHA_R1 * ((n1[a] + 1) / (n[a] + 2))) / (rn[k] + ALPHA_R1))
ptab(T::Tab, a, k) = pcount(T.n, T.n1, T.rn, T.rn1, a, k)
pushlb!(v, x) = (push!(v, x); length(v) > WIDX && popfirst!(v))
function predict2(L::IdxL, lf::Life, idx, m::Enc)
    out = Float64[]
    for t in idx
        si, s = lf.ex[t]; st = lf.streams[si]; a = st.act[s+1]; push!(out, ptab(L.act, a, keyfor(st, s, a, m)))
    end
    return out
end
function update2!(L::IdxL, lf::Life, idx, m::Enc)
    for t in idx
        si, s = lf.ex[t]; st = lf.streams[si]; a = st.act[s+1]; y = st.Y[s+1]; k = keyfor(st, s, a, m)
        for X in (L.act, L.arch...); pushlb!(X.lb, loss(ptab(X, a, k), y)); end          # every table is scored before the update
        pushlb!(L.clb, loss(pcount(L.cn, L.cn1, L.crn, L.crn1, a, k), y))
        X = L.act; X.n[a] += 1; X.n1[a] += y; X.rn[k] += 1; X.rn1[k] += y
        push!(L.cbuf, (k, a, y)); L.cn[a] += 1; L.cn1[a] += y; L.crn[k] += 1; L.crn1[k] += y
        if length(L.cbuf) > WIDX
            k0, a0, y0 = popfirst!(L.cbuf); L.cn[a0] -= 1; L.cn1[a0] -= y0; L.crn[k0] -= 1; L.crn1[k0] -= y0
        end
    end
    L.t += length(idx)
    (L.t - L.last >= WIDX && length(L.act.lb) >= WIDX && length(L.clb) >= WIDX) || return
    la = mean(L.act.lb); lc = mean(L.clb)
    best = 0; lbest = Inf
    for (j, X) in enumerate(L.arch)   # archive candidates with a full loss record; ties -> earliest id
        length(X.lb) >= WIDX || continue
        v = mean(X.lb)
        if v < lbest || (v == lbest && X.id < L.arch[best].id); best = j; lbest = v; end
    end
    if best > 0 && la - lbest > L.eta && lbest <= lc
        R = L.arch[best]; deleteat!(L.arch, best); push!(L.arch, L.act); L.act = R
        push!(L.events, (L.t, :ret, R.id)); L.last = L.t
    elseif la - lc > L.eta
        push!(L.arch, L.act)
        L.act = Tab(L.nextid, copy(L.cn), copy(L.cn1), copy(L.crn), copy(L.crn1), copy(L.clb)); L.nextid += 1
        push!(L.events, (L.t, :split, L.act.id)); L.last = L.t
    end
end
statehash(L::IdxL) = bytes2hex(sha256(reinterpret(UInt8, vcat(
    [vcat(X.n, X.n1, X.rn, X.rn1, X.lb, Float64(X.id), Float64(length(X.lb))) for X in (L.act, L.arch...)]...,
    L.cn, L.cn1, L.crn, L.crn1, L.clb, Float64[x for e in L.cbuf for x in (e[1], e[2], e[3])], Float64(L.t), Float64(L.last), Float64(L.nextid), Float64(length(L.arch))))))

# ---- main stream alone (for the eta selection and the detection delays)
function mainrun(life)
    streams = Dict(u => stream2(u) for u in SEEDS_ST1)
    lf = make_life2(life, SEEDS_ST1, streams); maps, _ = life_maps(life)
    L = newidx(); P = Float64[]; bounds = vcat(0, TS, lf.N)
    for seg in 1:5; append!(P, span!(L, lf, bounds[seg] + 1, bounds[seg+1] + 1, maps[seg])[1]); end
    return L, P, lf.N
end
function routine_events(L, N)
    ws = [(first(tail) + w * SWIN, first(tail) + w * SWIN + SWIN - 1) for i in 0:4 for tail in [((last(rint(N, i)) - RTAIL + 1):last(rint(N, i)))] for w in 0:2]
    return count(e -> any(w -> w[1] <= e[1] <= w[2], ws), L.events)
end

# ---- S73 B with table identities (codex S-R P4)
function paired_idx(life)
    streams = Dict(u => stream2(u) for u in SEEDS_ST1)
    lf = make_life2(life, SEEDS_ST1, streams); maps, alts = life_maps(life)
    L = newidx(); p0, y0v = span!(L, lf, 1, TS[1] + 1, maps[1])
    out = Dict{String,Any}()
    for (nm, m2) in (("H", maps[2]), ("Hp", alts[1]))
        X = deepcopy(L); ps = copy(p0); ys = copy(y0v); idT2 = 0
        for (a, b, m) in ((TS[1], TS[2], m2), (TS[2], TS[3], maps[3]), (TS[3], TS[4], maps[4]), (TS[4], TS[4] + EVLEN, maps[2]))
            a == TS[2] && (idT2 = X.act.id)
            q, z = span!(X, lf, a + 1, b + 1, m); append!(ps, q); append!(ys, z)
        end
        ℓ = losses(ps, ys); T = TS[4]
        ev = [e for e in X.events if T < e[1] <= T + EVLEN]
        out[nm] = (P = ps, pre = mean(ℓ[T-SBASE+1:T]), post = mean(ℓ[T+1:T+SWIN]), idT2 = idT2, ev = ev,
                   reused = any(e -> e[2] == :ret && e[3] == idT2 && e[1] < T + EVLEN, ev), ntab = X.nextid - 1)
    end
    H = out["H"]; Hp = out["Hp"]
    return (D = (Hp.post - Hp.pre) - (H.post - H.pre), dpost = Hp.post - H.post, dpre = Hp.pre - H.pre, H = H, Hp = Hp)
end

function run74()
    io = IOBuffer(); w0 = TOML.parsefile(W0_R3)["w0"]
    println(io, "== eta selection: splits/returns inside the 15 routine windows per life (main stream)")
    sel = nothing
    for eta in ETA_C
        ETA[] = eta
        rs = tmapv(l -> (L = mainrun(l); routine_events(L[1], L[3])), collect(1:NLIFE))
        println(io, "  eta=$eta routine events per life $(rs)")
        sel === nothing && all(==(0), rs) && (sel = eta)
    end
    println(io, "Q1 (some eta has zero routine events in 4/4 lives): $(sel === nothing ? "miss" : "holds (eta=$sel)")")
    if sel === nothing
        println(io, "Q2-Q4: undecidable (no eta)")
    else
        ETA[] = sel
        R = Dict(l => run_life4("IDX", l, 1) for l in 1:NLIFE)     # writes out_r4/life1_IDX_<l>.jls (new names; r4 files untouched)
        FG = Dict(l => loadlife4(1, "FGT", l) for l in 1:NLIFE)
        for l in 1:NLIFE
            selfcheck3!(R[l]); for e in EPS_C; ctlgate!(R[l], e, w0); end
            L, P, N = mainrun(l)
            reinterpret(UInt64, P) == reinterpret(UInt64, R[l].P) || error("mainrun differs from run_life4 main: life $l")
            println(io, "== life $l (eta=$sel): tables made $(L.nextid - 1), events $(length(L.events)) [$(join(["$(e[2])@$(e[1])#$(e[3])" for e in L.events], " "))]")
            for i in 1:4
                nxt = i == 4 ? N : TS[i+1]
                f = findfirst(e -> TS[i] < e[1] <= nxt, L.events)    # search stops at the end of this segment (codex I-R P5)
                println(io, "  switch i=$i first event in [T_i, next): $(f === nothing ? "none" : "$(L.events[f][2]) after $(L.events[f][1] - TS[i]) examples")")
            end
        end
        o1 = Dict(l => open1_4(R[l], 0.0025, w0) for l in 1:NLIFE)
        for l in 1:NLIFE
            j = o1[l]; jf = open1_4(FG[l], 0.0025, w0)
            println(io, "  OPEN-1 life $l ok=$(j.ok) viol=$(j.nviol)  s=$(join([f5(x.s) for x in j.o], ",")) meas=$(join([x.meas for x in j.o], ",")) rec=$(join([x.rec for x in j.o], ","))  [L-FGT s=$(join([f5(x.s) for x in jf.o], ","))]")
            println(io, "  OPEN-2 life $l dmap=$(join([f5(dmap4(R[l], i, w0)) for i in 1:4], ",")) ok(delta 0.1)=$(open2_4(R[l], 0.1, w0))")
        end
        q2 = all(l -> o1[l].ok, 1:NLIFE)
        B = Dict(l => paired_idx(l) for l in 1:NLIFE)
        for l in 1:NLIFE
            b = B[l]
            reinterpret(UInt64, b.H.P[1:TS[4]]) == reinterpret(UInt64, R[l].P[1:TS[4]]) || error("paired H differs from the main stream: life $l")
            println(io, "  S73-B life $l D=$(f5(b.D)) (dpost=$(f5(b.dpost)) dpre=$(f5(b.dpre)))  H: table at T_2 #$(b.H.idT2), events in the return $(b.H.ev), reused=$(b.H.reused), tables $(b.H.ntab)  H': events $(b.Hp.ev), tables $(b.Hp.ntab)")
        end
        q3 = all(l -> B[l].D > 0, 1:NLIFE)
        println(io, "Q2 (OPEN-1 age branches 4/4): $(q2 ? "holds" : "miss") ($(count(l -> o1[l].ok, 1:NLIFE))/4)")
        println(io, "Q3 (S73 B D > 0 in 4/4): $(q3 ? "holds" : "miss") ($(count(l -> B[l].D > 0, 1:NLIFE))/4)")
        println(io, "Q4 (Q2 and Q3 together at eta=$sel): $(q2 && q3 ? "holds" : "miss")")
        println(io, "gates: self-check 0, table difficulty control bit-identical across ages (IDX, all eps), mainrun == run_life4 main == paired H on [1, T_4]")
    end
    s = String(take!(io)); print(s); write(joinpath(OUT74, "s74.out"), s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    ARGS[1] == "run" && run74()
end
