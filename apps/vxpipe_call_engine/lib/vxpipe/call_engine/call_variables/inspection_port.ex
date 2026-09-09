defmodule Vxpipe.CallEngine.CallVariables.InspectionPort do
  @moduledoc false

  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}
  alias Vxpipe.CallEngine.LiveInspection.Buffer
  alias Vxpipe.CallEngine.LiveInspection.Port
  alias Vxpipe.CallEngine.ResolvedCallPlan

  @derive {Inspect, except: [:port]}
  defstruct [:port]

  @type snapshot :: BaselineSnapshot.t() | UpdateSnapshot.t()
  @type t :: %__MODULE__{port: nil | Port.t()}

  @spec new(ResolvedCallPlan.t()) :: t()
  def new(%ResolvedCallPlan{} = plan) do
    case Buffer.port(plan.tenant_id, plan.call_id) do
      {:ok, port} -> %__MODULE__{port: port}
      {:error, :unavailable} -> %__MODULE__{port: nil}
    end
  end

  @spec offer(t(), snapshot()) :: :ok
  def offer(%__MODULE__{port: nil}, snapshot)
      when is_struct(snapshot, BaselineSnapshot) or is_struct(snapshot, UpdateSnapshot),
      do: :ok

  def offer(%__MODULE__{port: port}, snapshot)
      when is_struct(snapshot, BaselineSnapshot) or is_struct(snapshot, UpdateSnapshot) do
    _accepted_or_dropped = Port.offer(port, snapshot)
    :ok
  end
end
