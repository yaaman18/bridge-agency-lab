# g3_next_audit: a supplementary audit of G3's frozen text "B1 のその行為の次の例の p は変わる", read strictly
# (without c0.jl's exception "or P in (LO, HI)"). Not a gate, no change to the freeze, c0.jl or its outputs.
# c0.jl is loaded from its source without its last line "main()" into a module of its own; its G7 and G0 checks run on load.
# The same 100 flips as c0.jl's G3 (EVAL[1:4], 25 positions each), with c0.jl's own run_world, train, transfer, replay, predict.
# Usage (from experiments/):  julia --project=.. -t 4 memory-transfer-c0/g3_next_audit.jl
using Printf
const HERE = @__DIR__
const C0 = Module(:C0)
let f = joinpath(HERE, "c0.jl"), src = read(f, String)
    s = rstrip(src)
    endswith(s, "\nmain()") || error("anchor: main() at the end of c0.jl")
    empty!(ARGS); push!(ARGS, "unused-by-audit")   # c0.jl's OUT; main() is not called, nothing is written there
    Base.include_string(C0, s[1:end-length("main()")], f)
end
const LO, HI = C0.LO, C0.HI

jobs = vcat([(u, C0.FAM_IN) for u in C0.TRAIN], [(u, C0.FAM_IN) for u in C0.EVAL[1:4]])
R = C0.tmapv(j -> C0.run_world(j...), jobs)
W = Dict(j[1] => R[i][1] for (i, j) in enumerate(jobs))
tw = [W[u] for u in C0.TRAIN]
rate, _, _ = C0.rates(tw)
tr, _ = C0.train(tw); tr0, _ = C0.train(tw; mem = false)
ind = C0.transfer(tr); ind0 = C0.transfer(tr0)

rows = ["seed\tflip_i\tt_i\ta\tnext_i\tt_next\tB1_p_next\tB1_p_next_flipped\tm_next_raw\tm_next_raw_flipped\tp_changed\traw_changed\tp_at_clip\tclass"]
cnt = Dict("changed" => 0, "unchanged_clipped" => 0, "unchanged_not_clipped" => 0, "no_next" => 0)
nraw = 0; nflip = 0; c0pass = 0
for u in C0.EVAL[1:4]
    w = W[u]; P, _ = C0.predict(w, rate, ind, ind0); ctx, _ = C0.replay(w)
    for i in unique(round.(Int, range(1, length(w.ex_t) - 50; length = 25)))
        global nflip += 1
        Q, _ = C0.predict(w, rate, ind, ind0; flip = i); cq, _ = C0.replay(w; flip = i)
        a = w.ex_a[i]
        nx = findnext(==(a), w.ex_a, i + 1)
        if nx === nothing
            cnt["no_next"] += 1; global c0pass += 1
            push!(rows, join([u, i, w.ex_t[i], a, "", "", "", "", "", "", "", "", "", "no_next"], "\t")); continue
        end
        p, q = P["B1"][nx], Q["B1"][nx]; mr, mq = ctx[nx][a], cq[nx][a]
        pch = q != p; rch = mq != mr; atclip = p in (LO, HI)
        rch && (global nraw += 1)
        (pch || atclip) && (global c0pass += 1)   # c0.jl's criterion, recomputed
        cls = pch ? "changed" : atclip ? "unchanged_clipped" : "unchanged_not_clipped"
        cnt[cls] += 1
        push!(rows, join([u, i, w.ex_t[i], a, nx, w.ex_t[nx], repr(p), repr(q), repr(mr), repr(mq), pch, rch, atclip, cls], "\t"))
    end
end
write(joinpath(HERE, "g3_next_audit.tsv"), join(rows, "\n") * "\n")
out = ["g3_next_audit (supplementary; G3 as frozen: B1's p at the next example of the same action changes, no clip exception)",
       "flips $(nflip) (EVAL[1:4] = $(C0.EVAL[1:4]))",
       "p changed $(cnt["changed"]), p unchanged $(cnt["unchanged_clipped"] + cnt["unchanged_not_clipped"]) (at clip $(cnt["unchanged_clipped"]), not at clip $(cnt["unchanged_not_clipped"])), no next $(cnt["no_next"])",
       "raw trace m_a at the next example changed (before the clip): $(nraw) of $(nflip - cnt["no_next"])",
       "c0.jl's criterion (changed or at clip; no-next skipped) recomputed: $(c0pass) of $(nflip)",
       "strict reading (every flip has a next example and its p changes): $(cnt["changed"] == nflip)"]
foreach(println, out)
write(joinpath(HERE, "g3_next_audit.out"), join(out, "\n") * "\n")
