# S62b r2 (discussion/specs/S62b-aue-boundary-audit.md): the S62 r2 boundary audit with two fixtures re-set (GB2(5), the
# GB4c identified pair). Everything else is the S62 module itself: experiments/boundary_audit/BoundaryAudit.jl is included
# unchanged (GB5 checks its SHA-256), so s_40, the closures, mu_bytes, live_wrapped, B-Test 1 and B-Test 3 are S62's
# byte for byte. Every fixture works on deep copies of s_40; nothing here writes into core/ or the parent S62 files.
module BoundaryAuditB

include(joinpath(@__DIR__, "..", "boundary_audit", "BoundaryAudit.jl"))
using .BoundaryAudit

export BoundaryAudit, port_fixture, sat_fixture

# GB2(5), the port removed (S62b §1.1): s_40 with pool = [0, 0] (no circuit take, no overflow return at 50U) and the drive
# g = (5, 5) = 10U for one step, arm A with w.port.reservoir = 0.00 and arm B with 0.25. Arm A can only take back what the
# step itself paid into the port (paid_all <= 0.052 < 0.20), arm B gets the full [0.10, 0.10]. The states come from the
# canonical onelife_step; live_wrapped (= onelife_step, GB4) is run beside it only for the diagnostic paid_all.
function port_fixture(s40)
    a = deepcopy(s40); a.pool .= [0.0, 0.0]; a.w.port.reservoir = 0.00
    b = deepcopy(s40); b.pool .= [0.0, 0.0]; b.w.port.reservoir = 0.25
    a41, _ = onelife_step(a, (5, 5)); b41, _ = onelife_step(b, (5, 5))
    _, ia = BoundaryAudit.wrapped_step(a, (5, 5)); _, ib = BoundaryAudit.wrapped_step(b, (5, 5))
    return (A = a41, B = b41, paid_A = ia.paid, paid_B = ib.paid, got_A = ia.got, got_B = ib.got)
end

# GB4c identified pair (S62b §1.2): s_40 with pool = [0.40, 0.40] = 20U, g_t = (4, 4) vs (5, 5), then g_{t+1} = g_sched(41)
# in both arms. The step t take is <= P_CAPACITY U = 0.10, so pool_{t+1} stays in [0.38, 0.50]: y_{t+1} = [5, 5] in both,
# no overflow, and the pool difference survives the identical step t+1.
function sat_fixture(s40)
    u = deepcopy(s40); u.pool .= [0.40, 0.40]
    u1, i0 = BoundaryAudit.wrapped_step(u, (4, 4)); v1, j0 = BoundaryAudit.wrapped_step(u, (5, 5))
    g1 = BoundaryAudit.g_sched(41)
    u2, iu = BoundaryAudit.wrapped_step(u1, g1); v2, iv = BoundaryAudit.wrapped_step(v1, g1)
    return (u1 = u1, v1 = v1, u2 = u2, v2 = v2, i0 = i0, j0 = j0, iu = iu, iv = iv)
end

end
