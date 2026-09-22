defmodule Vxpipe.CallEngine.STSInputHandle do
  @moduledoc "Private, connection-bound lookup for an asynchronously prepared STS input."

  alias Vxpipe.CallEngine.Media.STSIngress

  @enforce_keys [:identity, :connection]
  defstruct @enforce_keys
  @type t :: %__MODULE__{identity: map(), connection: pid()}

  def new(command, connection) do
    %__MODULE__{
      identity:
        Map.take(command, [:tenant_id, :room_id, :incarnation_id, :participant_id, :connection_id]),
      connection: connection
    }
  end

  def address(%__MODULE__{} = handle),
    do: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, handle}}}

  def configuration(%__MODULE__{} = handle) do
    with ingress when is_pid(ingress) <- GenServer.whereis(address(handle)),
         {:ok, format} <- STSIngress.media_format(ingress) do
      {:ok, %{ingress: ingress, format: format}}
    else
      _missing -> {:error, :speech_to_speech_unavailable}
    end
  end

  def push(%__MODULE__{connection: connection} = handle, frame) when connection == self() do
    case GenServer.whereis(address(handle)) do
      ingress when is_pid(ingress) -> STSIngress.push(ingress, frame)
      nil -> {:error, :speech_to_speech_unavailable}
    end
  end

  def push(%__MODULE__{}, _frame), do: {:error, :wrong_connection}
end
