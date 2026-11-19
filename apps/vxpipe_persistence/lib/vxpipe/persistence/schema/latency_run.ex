defmodule Vxpipe.Persistence.Schema.LatencyRun do
  use Ecto.Schema
  @derive {Inspect, only: [:id, :public_id, :revision]}
  schema "call_latency_runs" do
    field(:call_id, :integer)
    field(:public_id, :string)
    field(:revision, :integer)
    field(:record, :map)
    field(:profile, :map)
    field(:state, :string)
    field(:heartbeat_at, :utc_datetime_usec)
  end
end
