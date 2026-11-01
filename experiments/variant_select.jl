# Action selection in the substrate (2026-10-29, user decision "A"): at most one motor acts per step.
# Load after variant_attention.jl; sets ATTN_MODE to :consolidate (the rule A presupposes).
# Among the motors whose threshold is reached, the one with the largest total input fires; on a tie, the
# motor that fired in the previous step keeps firing if it is among the tied; otherwise the motor of the
# lower patch. The others do not fire this step. A silenced motor can win the selection (the intended action
# is then blocked: it fires but acts on nothing, as before). This is the sharpest policy precision.
@eval AgencySubstrate ATTN_MODE[] = :consolidate
@eval AgencySubstrate function select_motor!(new, total, old, s)
    cand = [m for m in keys(s.motors) if new[m]]
    length(cand) <= 1 && return new
    best = maximum(total[m] for m in cand)
    tied = [m for m in cand if total[m] == best]
    prev = [m for m in tied if old[m]]
    win = !isempty(prev) ? first(sort(prev; by=m -> s.motors[m])) : first(sort(tied; by=m -> s.motors[m]))
    for m in cand; m == win || (new[m] = false); end
    new
end
let src = read(joinpath(@__DIR__, "variant_attention.jl"), String)
    i = findfirst("@eval AgencySubstrate function step!", src)
    body = src[first(i):end]
    anchor = "    acting = [m for m in keys(s.motors) if new[m] && !(m in silenced)]"
    count(anchor, body) == 1 || error("edit target not unique")
    include_string(Main, replace(body, anchor => "    select_motor!(new, total, old, s)\n" * anchor))
end
