# LabCore: the canonical rules of bridge-agency-lab (user decision 2026-10-31: the rules are written in Julia; the
# JavaScript files are copies for the app and for the history of results, checked against these step by step,
# core/check/). Use: include("../core/LabCore.jl"); using .LabCore
module LabCore

include("jsmath.jl")
include("circuit.jl")
include("life.jl")
include("matter.jl")
include("evo.jl")
include("body_org.jl")
include("dc.jl")

export Mulberry, newborn, init, step!, form, allocate, cross!, drop_sources!, FEATURES,
       makelife, freshlife, live!, gesture!, set_mode!, set_counting!, clear_stats!, mark!, start_auto!, stop_auto!,
       reverse_world!, stasis!, jsonable,
       make_world, seed!, total, count_matter, kernel,
       make_evo, think!, evo_stats, evo_sources,
       body_org_run, DC_L, dc_record, dc_window, check_dc

end
