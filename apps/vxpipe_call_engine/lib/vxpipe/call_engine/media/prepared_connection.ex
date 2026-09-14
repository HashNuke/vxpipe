defmodule Vxpipe.CallEngine.Media.PreparedConnection do
  @moduledoc false

  alias Vxpipe.CallEngine.Readiness.Resource

  @enforce_keys [:identity, :instance, :generation, :input_track, :resources]
  defstruct @enforce_keys ++ [preparations: []]

  @type input_track :: %{
          track_id: String.t(),
          codec: atom(),
          sample_rate: pos_integer(),
          channels: 1 | 2
        }

  @type t :: %__MODULE__{
          identity: map(),
          instance: pid(),
          generation: reference(),
          input_track: input_track() | nil,
          resources: [Resource.t()],
          preparations: [map()]
        }

  def discard(%__MODULE__{preparations: preparations}), do: discard_preparations(preparations)

  @doc false
  def discard_preparations(preparations) do
    Enum.reduce(Enum.reverse(preparations), :ok, fn preparation, result ->
      case discard_preparation(preparation) do
        :ok -> result
        {:error, :stale_preparation} -> result
        _unavailable -> {:error, :unavailable}
      end
    end)
  end

  defp discard_preparation(preparation) do
    preparation.adapter.discard_policy(preparation.instance, preparation.token)
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
