import Std

/-!
Slice 1 of the formal-verification lane: the telephony media source gate.

This is a faithful model of `Vxpipe.Gateway.Telephony.SourceGate`:

* `new/0` is `nil`, modelled as `Gate.open`.
* `hold/1` is `Gate.hold`.
* `arm/2` is `Gate.arm`.
* `admitted?/2` is `Gate.admitted`.

The theorems below are the safety properties the Elixir module must preserve.
The oracle in `Oracle.lean` enumerates this model and is replayed against the
Elixir implementation by `verification/conformance/source_gate.exs`.
-/

namespace Vxpipe

/-- Telephony media source gate. `E` is the epoch type. -/
inductive Gate (E : Type) where
  | open : Gate E
  | held : Option E → Gate E
  | active : E → Gate E
  deriving Repr, DecidableEq

namespace Gate

variable {E : Type}

/-- `SourceGate.hold/1`. -/
def hold : Gate E → Gate E
  | .open => .held none
  | .held e => .held e
  | .active e => .held (some e)

/-- `SourceGate.arm/2`. -/
def arm (_g : Gate E) (e : E) : Gate E := .active e

/-- `SourceGate.admitted?/2`. -/
def admitted [DecidableEq E] : Gate E → Option E → Bool
  | .open, _ => true
  | .held _, _ => false
  | .active e, some e' => decide (e = e')
  | .active _, none => false

/-- A hold closes admission for every epoch, including the legacy nil stamp. -/
theorem hold_closed [DecidableEq E] (g : Gate E) (e : Option E) :
    (hold g).admitted e = false := by
  cases g <;> simp [hold, admitted]

/-- An arm admits exactly its own epoch. -/
theorem arm_admits_self [DecidableEq E] (g : Gate E) (e : E) :
    (arm g e).admitted (some e) = true := by
  simp [arm, admitted]

/-- An arm admits no epoch other than the one it was given. -/
theorem arm_admits_only [DecidableEq E] (g : Gate E) {e e' : E}
    (h : (arm g e).admitted (some e') = true) : e' = e := by
  simp [arm, admitted] at h
  exact h.symm

/-- An arm never admits the legacy nil stamp. -/
theorem arm_rejects_none [DecidableEq E] (g : Gate E) (e : E) :
    (arm g e).admitted none = false := by
  simp [arm, admitted]

/-- The slice-1 safety property: after a hold and an arm to `a`, every other
epoch is rejected. This is the stale-media-drop invariant. -/
theorem stale_epoch_rejected [DecidableEq E] (g : Gate E) {old a : E} (hne : old ≠ a) :
    (arm (hold g) a).admitted (some old) = false := by
  simp [arm, admitted, hne, ne_comm]

end Gate

end Vxpipe
