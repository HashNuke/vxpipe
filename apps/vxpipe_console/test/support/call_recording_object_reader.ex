defmodule Vxpipe.Console.TestCallRecordingObjectReader do
  @moduledoc false

  def read_range(reference, first, last, options) do
    observer = Keyword.fetch!(options, :observer)
    payload = payload!(Keyword.fetch!(options, :payload), reference)
    send(observer, {:read_call_recording_object, reference, first, last, options})
    {:ok, binary_part(payload, first, last - first + 1)}
  end

  defp payload!(payload, _reference) when is_binary(payload), do: payload

  defp payload!(payloads, reference) when is_map(payloads) and is_map(reference) do
    case Map.fetch(payloads, Map.get(reference, "object_key")) do
      {:ok, payload} when is_binary(payload) -> payload
      _invalid -> raise ArgumentError, "missing test payload for object reference"
    end
  end
end
