# Memory transfer pilot: the task, the three readouts, training, transplant and the four questions.
# Predictions frozen in predictions.toml (experiments/freeze-memory-transfer-pilot.txt) before the first run.
# Exact rationals, no randomness. Nothing here reads ~/bridge-protocol, the app's db or an existing individual.

const Q = Rational{BigInt}
const TRAIN = [(:A, :A), (:B, :B), (:A, :B), (:B, :A)]
const TEST = [(:C, :C), (:D, :D), (:C, :D), (:D, :C)]
const ETA = Q(1, 16)
const EPOCHS = 200

# Shared ±1 feature channels (the same code on both ports). Sylvester Hadamard rows r_i(j) = (-1)^popcount(i & j).
hrow(n, i) = Q[isodd(count_ones(i & j)) ? -1 : 1 for j in 0:n-1]
const CODINGS = Dict(
    :H4 => Dict(:A => hrow(4, 0), :B => hrow(4, 2), :C => hrow(4, 1), :D => hrow(4, 3)),       # C⊙D == A⊙B
    :O8 => Dict(:A => hrow(8, 0), :B => hrow(8, 1), :C => hrow(8, 2), :D => hrow(8, 2) .* hrow(8, 4)))  # C⊙D ⊥ 1, A⊙B

# Inputs of a trial: one symbol on the left port, one on the right; always two items.
# :ADD  additive  x = [f(L); f(R)]           (the bound of formal/MemoryTransfer.lean applies)
# :P    positive control, comparator given by design: x = [L == R ? 1 : -1]  (reads symbol identity by definition)
# :LP   local product of the shared channels: x = f(L) .* f(R)  (the product operator is design; which channels and
#       which sign are learned jointly with the bias)
function inputs(model::Symbol, coding::Symbol, L::Symbol, R::Symbol)
    f = CODINGS[coding]
    model === :ADD && return vcat(f[L], f[R])
    model === :P && return Q[L === R ? 1 : -1]
    model === :LP && return f[L] .* f[R]
    error("unknown model $model")
end

# An individual: the enumerated bonds (w, b) that are carried across training, and the transient state that is not.
mutable struct Individual
    model::Symbol
    coding::Symbol
    w::Vector{Q}          # bond
    b::Q                  # bond
    last_input::Vector{Q} # transient
    teacher::Q            # transient: the last teacher signal
    nupdates::Int         # transient
    errtrace::Q           # transient: summed |error| of the last epoch
end

fresh(model, coding) = Individual(model, coding, zeros(Q, length(inputs(model, coding, :A, :A))), Q(0), Q[], Q(0), 0, Q(0))
is_initial_transient(ind) = isempty(ind.last_input) && ind.teacher == 0 && ind.nupdates == 0 && ind.errtrace == 0

# The readout at test time: only the bonds and the two port inputs. No symbol IDs (except through :P's comparator, which
# is its definition), no labels, no history.
score(ind::Individual, L, R) = sum(ind.w .* inputs(ind.model, ind.coding, L, R)) + ind.b

# assignment :SX (same → X = +1, different → Y = -1) or :SY (labels inverted)
target(assign, L, R) = (L === R) == (assign === :SX) ? Q(1) : Q(-1)

function train!(ind::Individual, assign::Symbol; eta = ETA, epochs = EPOCHS)
    for _ in 1:epochs
        gw = zeros(Q, length(ind.w)); gb = Q(0); err = Q(0)
        for (L, R) in TRAIN
            x = inputs(ind.model, ind.coding, L, R); t = target(assign, L, R); e = t - score(ind, L, R)
            gw .+= e .* x; gb += e; err += abs(e)
            ind.last_input = x; ind.teacher = t
        end
        ind.w .+= eta .* gw; ind.b += eta * gb; ind.nupdates += 1; ind.errtrace = err
    end
    ind
end

# Transplant: a new individual from the same initial state; only the enumerated bonds are copied.
function transplant(src::Individual)
    dst = fresh(src.model, src.coding)
    dst.w = copy(src.w); dst.b = src.b
    @assert is_initial_transient(dst)
    dst
end

answer(s) = s > 0 ? "X" : s < 0 ? "Y" : "tie"

# Each question from its own copy of the same state, read once, no answer shown.
ask(ind, pairs; readout = score) = [(p, (s = readout(deepcopy(ind), p...); (s, answer(s)))) for p in pairs]

# One run: model × coding × assignment × condition. Conditions: TRANS (train, transplant), INIT (transplant the initial
# bonds), FROZEN (train with eta 0, transplant), SELF (the trained individual itself, no transplant).
function run_one(model, coding, assign, cond; readout = score)
    ind = fresh(model, coding)
    cond === :INIT || train!(ind, assign; eta = cond === :FROZEN ? Q(0) : ETA)
    subj = cond === :SELF ? ind : transplant(ind)
    (test = ask(subj, TEST; readout), train = ask(subj, TRAIN; readout), bonds = (copy(subj.w), subj.b))
end

ncorrect(rows, assign) = count(r -> r[2][2] == (target(assign, r[1]...) > 0 ? "X" : "Y"), rows)
