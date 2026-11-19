defmodule Vxpipe.Persistence.Schema.TurnDiagnostic do
  use Ecto.Schema
  @derive {Inspect, only: [:id, :turn_id, :revision]}
  schema "call_turn_diagnostics" do
    field(:run_id, :integer)
    field(:turn_id, :string)
    field(:revision, :integer)
    field(:record, :map)
    field(:durations_us, :map)
    field(:quality, :string)
  end
end
