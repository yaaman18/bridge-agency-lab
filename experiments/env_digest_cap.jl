# env_digest.jl with the digestion capacity (2026-10-29): the acting motors together digest at most
# AS.CAPACITY per step. If the offered yields sum to more, the capacity is split in proportion to the
# yields (floor), and what the floors leave goes to the patch with the larger yield (patch 1 on a tie).
const CAP = 50
const CONSUME = Ref(true)
season(t) = t <= 300 ? (3, 2) : t <= 600 ? (0, 5) : (5, 0)
function split_capacity(offer)
    tot = sum(offer)
    tot <= AS.CAPACITY && return offer
    d = [div(AS.CAPACITY * offer[i], tot) for i in 1:2]
    d[offer[1] >= offer[2] ? 1 : 2] += AS.CAPACITY - sum(d)
    d
end
function run_world(s, p, T; sil=t -> Set{Int}(), stasis=t -> false, wipe=t -> false)
    st = AS.initial_state(s, p); R = [CAP, CAP]; log = AS.State[]
    for t in 1:T
        wipe(t) && (R = [0, 0])
        y = stasis(t) ? (0, 0) : (min(R[1], 5), min(R[2], 5))
        S = sil(t)
        AS.step!(st, s, p, AS.Schedule("w", y, y, 0), S)
        offer = [0, 0]; for (m, pa) in s.motors; (st.active[m] && !(m in S)) && (offer[pa] = y[pa]); end
        d = split_capacity(offer)
        g = stasis(t) ? (0, 0) : season(t)
        R = [min(CAP, R[i] - (CONSUME[] ? d[i] : 0) + g[i]) for i in 1:2]
        push!(log, deepcopy(st))
    end
    log
end
formed(s, log, t, w) = AS.form(log[max(1, t - w + 1):t], s)
