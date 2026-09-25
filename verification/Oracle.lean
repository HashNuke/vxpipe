import Verification

open Vxpipe

/-!
Oracle generator for slice 1. Emits a pipe-delimited transition/admission table
for the `SourceGate` model. `verification/conformance/source_gate.exs` replays
it against the Elixir implementation.

Line format:
  <gate>|admitted|<epoch|nil>|<true|false>
  <gate>|hold|-|<gate'>
  <gate>|arm|<epoch>|<gate'>

Gate encoding: `open`, `held:nil`, `held:<n>`, `active:<n>`.
-/

def encEpoch : Option Nat → String
  | none => "nil"
  | some n => toString n

def encGate : Gate Nat → String
  | .open => "open"
  | .held e => s!"held:{encEpoch e}"
  | .active e => s!"active:{e}"

def encBool : Bool → String
  | true => "true"
  | false => "false"

def oracleEpochs : List Nat := [0, 1, 2]

def epochCases : List (String × Option Nat) :=
  ("nil", none) :: oracleEpochs.map (fun e => (toString e, some e))

def gateCases : List (Gate Nat × String) :=
  ([Gate.open, Gate.held none] ++
        oracleEpochs.map (fun e => Gate.held (some e)) ++
        oracleEpochs.map Gate.active).map
    (fun g => (g, encGate g))

def admittedLines : List String :=
  gateCases.foldl
    (fun acc (g, gs) =>
      acc ++ epochCases.map (fun (es, e) => s!"{gs}|admitted|{es}|{encBool (g.admitted e)}"))
    []

def holdLines : List String :=
  gateCases.map (fun (g, gs) => s!"{gs}|hold|-|{encGate g.hold}")

def armLines : List String :=
  gateCases.foldl
    (fun acc (g, gs) => acc ++ oracleEpochs.map (fun e => s!"{gs}|arm|{e}|{encGate (g.arm e)}"))
    []

def main : IO Unit := do
  for line in admittedLines ++ holdLines ++ armLines do
    IO.println line
