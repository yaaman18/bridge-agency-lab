# An environment the agent shapes by acting (2026-10-29). Each patch has a stock (cap 50). The yield of a
# patch is min(stock, 5). An active, non-silenced motor harvests its patch's yield, which is removed from
# the stock; each patch regrows by its regeneration rate per step. Patch sensors compare the current
# yields, so what the system senses depends on what it did: sensing is no longer independent of action.
# Seasons (regeneration of patch 1, patch 2): steps 1-300 (3, 2); 301-600 (0, 5) drought on patch 1;
# 601-1000 (5, 0) drought on patch 2. Stocks start at 50.
const CAP = 50
season(t) = t <= 300 ? (3, 2) : t <= 600 ? (0, 5) : (5, 0)
function live_in_world(s, p, T; silenced=Set{Int}(), on_step=nothing)
    st = AS.initial_state(s, p); stock = [CAP, CAP]; log = NamedTuple[]
    for t in 1:T
        y = (min(stock[1], 5), min(stock[2], 5))
        before = copy(st.strength)
        AS.step!(st, s, p, AS.Schedule("world", y, y, 0), silenced)
        harvested = [0, 0]
        if !st.dead
            for (m, patch) in s.motors
                (st.active[m] && !(m in silenced)) && (harvested[patch] = y[patch])
            end
        end
        g = season(t)
        stock = [min(CAP, stock[i] - harvested[i] + g[i]) for i in 1:2]
        push!(log, (t=t, y=y, stock=copy(stock), resource=st.resource, dead=st.dead, active=copy(st.active), before=before, harvested=copy(harvested)))
        st.dead && break
    end
    log
end
