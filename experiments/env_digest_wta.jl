# env_digest.jl with the winner-take-all allocation of variant_attention.jl (2026-10-29).
const CAP = 50
season(t) = t <= 300 ? (3, 2) : t <= 600 ? (0, 5) : (5, 0)
function run_world(s, p, T; sil=t -> Set{Int}())
    st = AS.initial_state(s, p); R = [CAP, CAP]; log = AS.State[]
    for t in 1:T
        y = (min(R[1], 5), min(R[2], 5)); S = sil(t)
        AS.step!(st, s, p, AS.Schedule("w", y, y, 0), S)
        offer = [0, 0]; for (m, pa) in s.motors; (st.active[m] && !(m in S)) && (offer[pa] = y[pa]); end
        d = AS.allocate(offer); g = season(t)
        R = [min(CAP, R[i] - d[i] + g[i]) for i in 1:2]
        push!(log, deepcopy(st))
    end
    log
end
formed(s, log, t, w) = AS.form(log[max(1, t - w + 1):t], s)
