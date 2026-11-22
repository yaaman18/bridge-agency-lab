import ERIEC.MetaSelection
import Mathlib.Logic.Equiv.Defs

/-!
# Nesting lineage: the Stage 0 witness and the Stage 1 lineage span (S61 §4 G0; statements first)

Spec `discussion/specs/S61-nesting-cpc.md` r3, note `discussion/notes/L3-STAGE0-WITNESS-AND-EXPLORATION.md` §1.
The carriers of the two time points are disjoint types (`Node0`, `Node1`, `Node1s`), so no label is shared across time.
Stage 0 is the vocabulary of `ERIEC.MetaSelection`: a `PartOfHierarchy`, a `WorldDecomposition` with its
`WorldIrreducible`, and `classifyIndividuality`. The decomposition with `PartWorld _ := Unit`, `WholeWorld := Unit` is a
typing witness only (any two parts make it irreducible); it is not evidence of emergence.
Stage 1 adds a tagged span between adjacent time points with M1 carrier IDs (a monotone allocator `nextId`). The
continuant of a split and the continuing parent of an absorption are the outputs that keep the parent's carrier ID; this
is the Lean side of the Julia carrier-continuity check, and (3)–(4) follow from ID injectivity and the allocator bound.
(5) follows from the construction of the body step (death is absorbing). `phenomenal_claim` is not touched.
-/

namespace BridgeLab.NestingLineage

open ERIEC.MetaSelection

/-! ### Stage 0 -/

/-- Carrier at `t = 0`: the body `W` and two lower modules. -/
inductive Node0 | W | a | b
  deriving DecidableEq, Repr

/-- Carrier at `t = 1` (disjoint from `Node0` as a type). -/
inductive Node1 | W | a | b
  deriving DecidableEq, Repr

/-- Carrier at `t = 1` of the shifting coalition: `a` gone, `b` continued, `c` new. -/
inductive Node1s | W | b | c
  deriving DecidableEq, Repr

/-- The star order: every node is below itself and below the body `top`. -/
def starLeq {V : Type} (top : V) (x y : V) : Prop := x = y ∨ y = top

/-- The static part-of hierarchy of one snapshot. -/
def starHierarchy {V : Type} (top : V) : PartOfHierarchy V where
  leq := starLeq top
  refl := fun _ => Or.inl rfl
  trans := by
    intro x y z hxy hyz
    rcases hyz with rfl | rfl
    · exact hxy
    · exact Or.inr rfl
  antisymm := by
    intro x y hxy hyx
    rcases hxy with h | rfl
    · exact h
    · rcases hyx with h | rfl
      · exact h.symm
      · rfl

/-- The parts of one snapshot are the non-body nodes. -/
abbrev Parts {V : Type} (top : V) := {x : V // x ≠ top}

/-- The typing witness decomposition of one snapshot. -/
def starDecomp {V : Type} (top : V) :
    WorldDecomposition (Parts top) (fun _ => Unit) Unit where
  inclusion := fun _ _ => ()

/-- Two distinct parts make the canonical comparison non-injective. -/
theorem starDecomp_irreducible {V : Type} (top p q : V) (hp : p ≠ top) (hq : q ≠ top) (hpq : p ≠ q) :
    WorldIrreducible (starDecomp top) := by
  intro hbij
  have h := hbij.1 (a₁ := ⟨⟨p, hp⟩, ()⟩) (a₂ := ⟨⟨q, hq⟩, ()⟩) rfl
  have h1 := congrArg (fun z => z.1.1) h
  exact hpq h1

/-- The Stage 0 classification of both snapshots: upper irreducible, lower modules not independent. -/
def cls0 : IndividualityKind := classifyIndividuality true false
def cls1 : IndividualityKind := classifyIndividuality true false

def phi01 : Node0 ≃ Node1 where
  toFun | .W => .W | .a => .a | .b => .b
  invFun | .W => .W | .a => .a | .b => .b
  left_inv := by intro x; cases x <;> rfl
  right_inv := by intro x; cases x <;> rfl

def phi01s : Node0 ≃ Node1s where
  toFun | .W => .W | .a => .b | .b => .c
  invFun | .W => .W | .b => .a | .c => .b
  left_inv := by intro x; cases x <;> rfl
  right_inv := by intro x; cases x <;> rfl

/-- (1) The Stage 0 observations of `t = 0`, `t = 1` and the shifting `t = 1` are isomorphic: an order isomorphism
fixing the body, irreducible decompositions at every snapshot, and the same classification `individual`. -/
theorem stage0_isomorphic :
    (∃ φ : Node0 ≃ Node1, φ .W = .W ∧
      ∀ x y, (starHierarchy Node0.W).leq x y ↔ (starHierarchy Node1.W).leq (φ x) (φ y)) ∧
    (∃ ψ : Node0 ≃ Node1s, ψ .W = .W ∧
      ∀ x y, (starHierarchy Node0.W).leq x y ↔ (starHierarchy Node1s.W).leq (ψ x) (ψ y)) ∧
    WorldIrreducible (starDecomp Node0.W) ∧ WorldIrreducible (starDecomp Node1.W) ∧
    WorldIrreducible (starDecomp Node1s.W) ∧
    cls0 = cls1 ∧ cls0 = .individual := by
  refine ⟨⟨phi01, rfl, ?_⟩, ⟨phi01s, rfl, ?_⟩, ?_, ?_, ?_, rfl, rfl⟩
  · intro x y
    cases x <;> cases y <;> simp [starHierarchy, starLeq, phi01]
  · intro x y
    cases x <;> cases y <;> simp [starHierarchy, starLeq, phi01s]
  · exact starDecomp_irreducible _ Node0.a Node0.b (by decide) (by decide) (by decide)
  · exact starDecomp_irreducible _ Node1.a Node1.b (by decide) (by decide) (by decide)
  · exact starDecomp_irreducible _ Node1s.b Node1s.c (by decide) (by decide) (by decide)

/-! ### Stage 1 -/

inductive MergeKind | absorption | fusion
  deriving DecidableEq, Repr

inductive Tag | persist | split | merge (k : MergeKind)
  deriving DecidableEq, Repr

/-- A span between adjacent time points with M1 carrier IDs (`none` for the body) and the allocator bound. -/
structure LineageSpan (V V' : Type) where
  edge : V → V' → Tag → Prop
  idSrc : V → Option Nat
  idTgt : V' → Option Nat
  nextId : Nat

namespace LineageSpan

variable {V V' : Type} (L : LineageSpan V V')

def Death : Set V := {u | ¬ ∃ v k, L.edge u v k}
def Birth : Set V' := {v | ¬ ∃ u k, L.edge u v k}

/-- `v` keeps the carrier of `u`. -/
def KeepsCarrier (u : V) (v : V') : Prop := (L.idSrc u).isSome ∧ L.idTgt v = L.idSrc u

/-- Well-formedness: endpoint exclusivity per kind, arity, and the M1 carrier rules. -/
structure WellFormed : Prop where
  persist_excl : ∀ u v, L.edge u v .persist →
    (∀ v' k, L.edge u v' k → v' = v ∧ k = .persist) ∧ (∀ u' k, L.edge u' v k → u' = u ∧ k = .persist)
  split_excl : ∀ u v, L.edge u v .split →
    (∀ v' k, L.edge u v' k → k = .split) ∧ (∀ u' k, L.edge u' v k → u' = u ∧ k = .split) ∧
      ∃ v', v' ≠ v ∧ L.edge u v' .split
  merge_excl : ∀ u v m, L.edge u v (.merge m) →
    (∀ v' k, L.edge u v' k → v' = v ∧ k = .merge m) ∧ (∀ u' k, L.edge u' v k → k = .merge m) ∧
      ∃ u', u' ≠ u ∧ L.edge u' v (.merge m)
  idSrc_inj : ∀ x y n, L.idSrc x = some n → L.idSrc y = some n → x = y
  idTgt_inj : ∀ x y n, L.idTgt x = some n → L.idTgt y = some n → x = y
  idSrc_lt : ∀ x n, L.idSrc x = some n → n < L.nextId
  persist_id : ∀ u v, L.edge u v .persist → L.idTgt v = L.idSrc u
  split_id : ∀ u v, L.edge u v .split →
    (L.idSrc u).isSome ∧ (L.idTgt v = L.idSrc u ∨ ∃ n, L.idTgt v = some n ∧ L.nextId ≤ n)
  absorption_id : ∀ u v, L.edge u v (.merge .absorption) →
    ∃ u', L.edge u' v (.merge .absorption) ∧ L.KeepsCarrier u' v
  fusion_id : ∀ u v, L.edge u v (.merge .fusion) → ∃ n, L.idTgt v = some n ∧ L.nextId ≤ n
  birth_fresh : ∀ v n, v ∈ L.Birth → L.idTgt v = some n → L.nextId ≤ n

end LineageSpan

/-- `H_persist`: body and both modules persist; IDs 1, 2 kept. -/
def spanPersist : LineageSpan Node0 Node1 where
  edge
    | .W, .W, .persist => True
    | .a, .a, .persist => True
    | .b, .b, .persist => True
    | _, _, _ => False
  idSrc | .W => none | .a => some 1 | .b => some 2
  idTgt | .W => none | .a => some 1 | .b => some 2
  nextId := 3

/-- `H_replace`: the body persists, both modules die and two new carriers (IDs 3, 4) are born. -/
def spanReplace : LineageSpan Node0 Node1 where
  edge
    | .W, .W, .persist => True
    | _, _, _ => False
  idSrc | .W => none | .a => some 1 | .b => some 2
  idTgt | .W => none | .a => some 3 | .b => some 4
  nextId := 3

/-- `H_shifting`: `a` dies, `b` buds into the continuant `b` and the new `c` (ID 3). -/
def spanShifting : LineageSpan Node0 Node1s where
  edge
    | .W, .W, .persist => True
    | .b, .b, .split => True
    | .b, .c, .split => True
    | _, _, _ => False
  idSrc | .W => none | .a => some 1 | .b => some 2
  idTgt | .W => none | .b => some 2 | .c => some 3
  nextId := 3

theorem spanPersist_wf : spanPersist.WellFormed where
  persist_excl := by
    intro u v h; cases u <;> cases v <;> simp_all [spanPersist] <;>
      (constructor <;> intro x k <;> cases x <;> cases k <;> simp_all)
  split_excl := by intro u v h; cases u <;> cases v <;> simp_all [spanPersist]
  merge_excl := by intro u v m h; cases u <;> cases v <;> simp_all [spanPersist]
  idSrc_inj := by intro x y n hx hy; cases x <;> cases y <;> simp_all [spanPersist] <;> omega
  idTgt_inj := by intro x y n hx hy; cases x <;> cases y <;> simp_all [spanPersist] <;> omega
  idSrc_lt := by intro x n h; cases x <;> simp_all [spanPersist] <;> omega
  persist_id := by intro u v h; cases u <;> cases v <;> simp_all [spanPersist]
  split_id := by intro u v h; cases u <;> cases v <;> simp_all [spanPersist]
  absorption_id := by intro u v h; cases u <;> cases v <;> simp_all [spanPersist]
  fusion_id := by intro u v h; cases u <;> cases v <;> simp_all [spanPersist]
  birth_fresh := by
    intro v n hv _; exfalso; apply hv
    cases v
    · exact ⟨.W, .persist, trivial⟩
    · exact ⟨.a, .persist, trivial⟩
    · exact ⟨.b, .persist, trivial⟩

theorem spanReplace_wf : spanReplace.WellFormed where
  persist_excl := by
    intro u v h; cases u <;> cases v <;> simp_all [spanReplace] <;>
      (constructor <;> intro x k <;> cases x <;> cases k <;> simp_all)
  split_excl := by intro u v h; cases u <;> cases v <;> simp_all [spanReplace]
  merge_excl := by intro u v m h; cases u <;> cases v <;> simp_all [spanReplace]
  idSrc_inj := by intro x y n hx hy; cases x <;> cases y <;> simp_all [spanReplace] <;> omega
  idTgt_inj := by intro x y n hx hy; cases x <;> cases y <;> simp_all [spanReplace] <;> omega
  idSrc_lt := by intro x n h; cases x <;> simp_all [spanReplace] <;> omega
  persist_id := by intro u v h; cases u <;> cases v <;> simp_all [spanReplace]
  split_id := by intro u v h; cases u <;> cases v <;> simp_all [spanReplace]
  absorption_id := by intro u v h; cases u <;> cases v <;> simp_all [spanReplace]
  fusion_id := by intro u v h; cases u <;> cases v <;> simp_all [spanReplace]
  birth_fresh := by intro v n _ h; cases v <;> simp_all [spanReplace] <;> omega

theorem spanShifting_wf : spanShifting.WellFormed where
  persist_excl := by
    intro u v h; cases u <;> cases v <;> simp_all [spanShifting] <;>
      (constructor <;> intro x k <;> cases x <;> cases k <;> simp_all)
  split_excl := by
    intro u v h; cases u <;> cases v <;> simp_all [spanShifting]
    · refine ⟨?_, ?_, .c, by decide, trivial⟩
      · intro x k; cases x <;> cases k <;> simp_all
      · intro x k; cases x <;> cases k <;> simp_all
    · refine ⟨?_, ?_, .b, by decide, trivial⟩
      · intro x k; cases x <;> cases k <;> simp_all
      · intro x k; cases x <;> cases k <;> simp_all
  merge_excl := by intro u v m h; cases u <;> cases v <;> simp_all [spanShifting]
  idSrc_inj := by intro x y n hx hy; cases x <;> cases y <;> simp_all [spanShifting] <;> omega
  idTgt_inj := by intro x y n hx hy; cases x <;> cases y <;> simp_all [spanShifting] <;> omega
  idSrc_lt := by intro x n h; cases x <;> simp_all [spanShifting] <;> omega
  persist_id := by intro u v h; cases u <;> cases v <;> simp_all [spanShifting]
  split_id := by intro u v h; cases u <;> cases v <;> simp_all [spanShifting]
  absorption_id := by intro u v h; cases u <;> cases v <;> simp_all [spanShifting]
  fusion_id := by intro u v h; cases u <;> cases v <;> simp_all [spanShifting]
  birth_fresh := by
    intro v n hv _; exfalso; apply hv
    cases v
    · exact ⟨.W, .persist, trivial⟩
    · exact ⟨.b, .split, trivial⟩
    · exact ⟨.b, .split, trivial⟩

/-- Two spans over the same snapshots are isomorphic when automorphisms of the carriers transport the edges. -/
def SpanIso {V V' : Type} (L M : LineageSpan V V') : Prop :=
  ∃ (φ : V ≃ V) (φ' : V' ≃ V'), ∀ u v k, L.edge u v k ↔ M.edge (φ u) (φ' v) k

/-- (2) `H_persist` and `H_replace` have the same (isomorphic) Stage 0 observations, both spans are well formed, and
the spans are separated: not isomorphic, and the death sets differ. -/
theorem stage1_separates_persist_and_replace :
    (∃ φ : Node0 ≃ Node1, φ .W = .W ∧
      ∀ x y, (starHierarchy Node0.W).leq x y ↔ (starHierarchy Node1.W).leq (φ x) (φ y)) ∧
    spanPersist.WellFormed ∧ spanReplace.WellFormed ∧
    ¬ SpanIso spanPersist spanReplace ∧
    spanPersist.Death = ∅ ∧ Node0.a ∈ spanReplace.Death := by
  refine ⟨stage0_isomorphic.1, spanPersist_wf, spanReplace_wf, ?_, ?_, ?_⟩
  · rintro ⟨φ, φ', h⟩
    -- every edge of `spanReplace` starts at `W`, so `φ a = W = φ b`
    have only_W : ∀ u v k, spanReplace.edge u v k → u = .W := by
      intro u v k hk; cases u <;> cases v <;> cases k <;> simp_all [spanReplace]
    have ha := only_W _ _ _ ((h .a .a .persist).1 trivial)
    have hb := only_W _ _ _ ((h .b .b .persist).1 trivial)
    exact absurd (φ.injective (ha.trans hb.symm)) (by decide)
  · ext u
    simp only [LineageSpan.Death, Set.mem_setOf_eq, Set.mem_empty_iff_false, iff_false, not_not]
    cases u
    · exact ⟨.W, .persist, trivial⟩
    · exact ⟨.a, .persist, trivial⟩
    · exact ⟨.b, .persist, trivial⟩
  · rintro ⟨v, k, hk⟩
    cases v <;> cases k <;> simp_all [spanReplace]

/-- (3) In a well-formed span, a split has at most one continuant output. -/
theorem split_continuant_unique {V V' : Type} (L : LineageSpan V V') (hL : L.WellFormed)
    (u : V) (v₁ v₂ : V') (_h₁ : L.edge u v₁ .split) (_h₂ : L.edge u v₂ .split)
    (c₁ : L.KeepsCarrier u v₁) (c₂ : L.KeepsCarrier u v₂) : v₁ = v₂ := by
  obtain ⟨hs, e₁⟩ := c₁
  obtain ⟨_, e₂⟩ := c₂
  obtain ⟨n, hn⟩ := Option.isSome_iff_exists.mp hs
  exact hL.idTgt_inj v₁ v₂ n (e₁.trans hn) (e₂.trans hn)

/-- (4) A fusion output keeps no parent's carrier; an absorption output keeps exactly one parent's carrier. -/
theorem merge_fusion_no_continuant {V V' : Type} (L : LineageSpan V V') (hL : L.WellFormed) (v : V') :
    ((∃ u, L.edge u v (.merge .fusion)) → ∀ u', ¬ L.KeepsCarrier u' v) ∧
    ((∃ u, L.edge u v (.merge .absorption)) →
      ∃ u', (L.edge u' v (.merge .absorption) ∧ L.KeepsCarrier u' v) ∧
        ∀ u'', L.edge u'' v (.merge .absorption) ∧ L.KeepsCarrier u'' v → u'' = u') := by
  constructor
  · rintro ⟨u, hu⟩ u' ⟨hs, e⟩
    obtain ⟨n, hn, hle⟩ := hL.fusion_id u v hu
    obtain ⟨m, hm⟩ := Option.isSome_iff_exists.mp hs
    have : n = m := by rw [hn] at e; rw [hm] at e; exact Option.some.inj e
    have hlt := hL.idSrc_lt u' m hm
    omega
  · rintro ⟨u, hu⟩
    obtain ⟨u', hu', hc⟩ := hL.absorption_id u v hu
    refine ⟨u', ⟨hu', hc⟩, ?_⟩
    rintro u'' ⟨_, hs'', e''⟩
    obtain ⟨n, hn⟩ := Option.isSome_iff_exists.mp hc.1
    exact hL.idSrc_inj u'' u' n (e''.symm.trans (hc.2.trans hn)) hn

/-! ### The body -/

/-- A body law: the living step of the inner state and the lethal predicate on the stepped state. -/
structure BodyLaw (σ ι : Type) where
  live : σ → ι → σ
  lethal : σ → Bool

structure BodyState (σ : Type) where
  inner : σ
  alive : Bool

/-- One step (S61 §3.2 order: the function-end check first, lethality last). -/
def bodyStep {σ ι : Type} (B : BodyLaw σ ι) (s : BodyState σ) (x : ι) : BodyState σ :=
  if s.alive then
    let s' := B.live s.inner x
    { inner := s', alive := !B.lethal s' }
  else s

def bodyRun {σ ι : Type} (B : BodyLaw σ ι) (s : BodyState σ) (xs : List ι) : BodyState σ :=
  xs.foldl (bodyStep B) s

/-- The body node has a `persist` edge in `L_t` exactly when it is alive before and after the step. -/
def BodyPersist {σ : Type} (s s' : BodyState σ) : Prop := s.alive = true ∧ s'.alive = true

/-- (5) After the end of function the body stays dead under any further inputs and never gets a `persist` edge again. -/
theorem body_death_irreversible {σ ι : Type} (B : BodyLaw σ ι) (s : BodyState σ) (h : s.alive = false)
    (xs : List ι) :
    bodyRun B s xs = s ∧ ∀ x, ¬ BodyPersist (bodyRun B s xs) (bodyStep B (bodyRun B s xs) x) := by
  have hrun : bodyRun B s xs = s := by
    induction xs with
    | nil => rfl
    | cons x xs ih =>
      have : bodyStep B s x = s := by simp [bodyStep, h]
      simp only [bodyRun, List.foldl_cons, this] at ih ⊢
      exact ih
  refine ⟨hrun, ?_⟩
  intro x ⟨ha, _⟩
  rw [hrun] at ha
  simp [h] at ha

end BridgeLab.NestingLineage

#print axioms BridgeLab.NestingLineage.stage0_isomorphic
#print axioms BridgeLab.NestingLineage.stage1_separates_persist_and_replace
#print axioms BridgeLab.NestingLineage.split_continuant_unique
#print axioms BridgeLab.NestingLineage.merge_fusion_no_continuant
#print axioms BridgeLab.NestingLineage.body_death_irreversible
