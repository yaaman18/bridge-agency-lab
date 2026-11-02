# Raising curricula for body_org's circuit (item 74). :std = core/body_org.jl BO_CUR (nursery: 50-step blocks starting
# [5,0], so it ends on [0,5]; school: 15-step blocks [5,2]/[2,5]). :swap = the nursery's blocks swapped (starting [0,5],
# so it ends on [5,0]); the school is unchanged. Only the order of the frozen yields changes (no number changes).
curriculum(kind::Symbol) = kind == :std ? LabCore.BO_CUR :
    kind == :swap ? vcat([((i ÷ 50) % 2 == 0 ? [0.0, 5.0] : [5.0, 0.0]) for i in 0:399], LabCore.BO_CUR[401:800]) :
    error("unknown curriculum $kind")
