# Direction of agency and the digestion capacity (2026-10-29, user decisions: add a direction condition to
# agency; put an upper bound on the prediction error digested in one step). Load after variant_tracking_sets.jl.
#
# * Capacity: at most CAPACITY = 5 units of prediction error are digested per step, whatever the number of
#   acting motors. 5 is the largest yield one patch offers in every frozen schedule (not a new number).
#   val(sch, A) = min(CAPACITY, summed yield of the patches of the motor set A under sch).
#   (The world's split of the capacity between patches is in env_digest_cap.jl.)
# * Direction (new condition of agency): with A_i the choice in choice schedule i, the system is directed iff
#   val(c1, A_1) > val(c1, A_2) and val(c2, A_2) > val(c2, A_1): in each context its own choice digests more
#   there than the choice it makes in the other context would. Agency = adopted conditions (with minimal
#   tracking sets) AND directed.
@eval AgencySubstrate const CAPACITY = 5
@eval AgencySubstrate capval(s, sch, A) = min(CAPACITY, sum((yield_of(sch, s.motors[m], 0) for m in A); init=0))
@eval AgencySubstrate function directed(s, pc, c, window)
    A = [choice(s, pc, x, window) for x in c]
    capval(s, c[1], A[1]) > capval(s, c[1], A[2]) && capval(s, c[2], A[2]) > capval(s, c[2], A[1])
end
@eval AgencySubstrate function evaluate(s::Substrate, setup)
    p, pc, c, w, surv = setup.params, setup.choice_params, setup.choice, setup.choice_window, setup.survival
    core = endogenous_core(s, pc, surv[1])
    sets = minimal_tracking_sets(s, pc, c, w, core)
    T = sort!(unique(vcat(Int[], sets...)))
    alive_somewhere = any(x -> survives(s, p, x), surv)
    differentiated = value_differentiated(s, pc, c, w)
    needed = value_needed(s, p, surv, T)
    hinge = core_enables_action(s, pc, c, w, core)
    dir = directed(s, pc, c, w)
    base_agency = !isempty(core) && hinge && alive_somewhere && differentiated && needed
    (; agency=base_agency && dir, agency_without_direction=base_agency, directed=dir,
       self_producing=self_producing(s, p, pc, surv),
       self_repairing=self_repairing(s, p, pc, surv),
       core=[s.names[u] for u in core], core_enables_action=hinge,
       alive_somewhere, differentiated, value_needed=needed,
       value_tracking=[s.names[u] for u in T],
       tracking_sets=[[s.names[u] for u in S] for S in sets],
       choices=Dict(x.name => sort!([s.names[m] for m in choice(s, pc, x, w)]) for x in c))
end
