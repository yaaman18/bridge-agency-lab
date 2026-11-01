# The world of the digestion variant (2026-10-29): env_deplete.jl with the stock read as residual
# prediction error R_i (cap 50). Acting at a patch digests min(R_i, 5); the world drifts, adding g_i per
# step. Seasons of drift (patch 1, patch 2): 1-300 (3, 2); 301-600 (0, 5), patch 1 static; 601-1000 (5, 0),
# patch 2 static. CONSUME[] = false: ablation, acting never reduces R (the world always answers the same).
const CAP = 50
const CONSUME = Ref(true)
season(t) = t <= 300 ? (3, 2) : t <= 600 ? (0, 5) : (5, 0)
function run_world(s, p, T; sil=t -> Set{Int}(), stasis=t -> false, wipe=t -> false)
    st = AS.initial_state(s, p); R = [CAP, CAP]; log = AS.State[]
    for t in 1:T
        wipe(t) && (R = [0, 0])
        y = stasis(t) ? (0, 0) : (min(R[1], 5), min(R[2], 5))
        S = sil(t)
        AS.step!(st, s, p, AS.Schedule("w", y, y, 0), S)
        d = [0, 0]; for (m, pa) in s.motors; (st.active[m] && !(m in S)) && (d[pa] = y[pa]); end
        g = stasis(t) ? (0, 0) : season(t)
        R = [min(CAP, R[i] - (CONSUME[] ? d[i] : 0) + g[i]) for i in 1:2]
        push!(log, deepcopy(st))
    end
    log
end
formed(s, log, t, w) = AS.form(log[max(1, t - w + 1):t], s)
