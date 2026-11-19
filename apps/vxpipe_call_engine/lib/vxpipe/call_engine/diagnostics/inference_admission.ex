defmodule Vxpipe.CallEngine.Diagnostics.InferenceAdmission do
  @moduledoc "Count-bounded asynchronous inference offers for an isolated diagnostic runtime."
  alias Vxpipe.CallEngine.Diagnostics.CaptureHandoff
  alias Vxpipe.CallEngine.Speech.Silero
  @enforce_keys [:runtime, :token, :counter, :capacity]
  @derive {Inspect, only: [:capacity]}
  defstruct @enforce_keys

  def new(_runtime, nil), do: nil

  def new(runtime, capacity) when is_integer(capacity) and capacity in 1..32,
    do: %__MODULE__{
      runtime: runtime,
      token: make_ref(),
      counter: :atomics.new(1, []),
      capacity: capacity
    }

  def submit(%__MODULE__{} = admission, %CaptureHandoff{} = grant, %Silero{} = stream, audio) do
    cond do
      grant.receiver != self() or not CaptureHandoff.current?(grant) or
          not Process.alive?(admission.runtime) ->
        {:error, :unavailable}

      not Silero.valid_audio?(audio) or not valid_stream?(stream) ->
        {:error, :invalid_audio}

      true ->
        offer(admission, grant, stream, audio)
    end
  end

  def pending(admission), do: :atomics.get(admission.counter, 1)
  def release(admission), do: :atomics.sub(admission.counter, 1, 1)

  defp offer(admission, grant, stream, audio) do
    if reserve(admission, 16) do
      reference = make_ref()
      # Detach retained sub-binaries only after reserving a bounded queue slot.
      stream = detach(stream)

      message =
        {:diagnostic_inference, admission.token, self(), reference, grant, stream,
         :binary.copy(audio)}

      case :erlang.send(admission.runtime, message, [:nosuspend]) do
        :nosuspend ->
          release(admission)
          {:error, :unavailable}

        _ ->
          {:ok, reference}
      end
    else
      {:error, :full}
    end
  end

  defp valid_stream?(stream) do
    is_integer(stream.samples) and stream.samples in 0..9_223_372_036_854_775_807 and
      is_binary(stream.pending) and byte_size(stream.pending) < 1_024 and
      tensor?(stream.recurrent, {2, 1, 128}) and tensor?(stream.context, {1, 64}) and
      :erlang.external_size(stream) <= 16_384
  end

  defp tensor?(nil, _shape), do: true
  defp tensor?(%Nx.Tensor{shape: shape, type: {:f, 32}}, shape), do: true
  defp tensor?(_tensor, _shape), do: false

  # Preserve native tensor references, but detach every BEAM binary view, including
  # BinaryBackend tensor storage. Pinned Silero owns native tensor dimensions.
  defp detach(value) when is_binary(value), do: :binary.copy(value)

  defp detach(value) when is_map(value),
    do: Map.new(Map.to_list(value), fn {k, v} -> {detach(k), detach(v)} end)

  defp detach(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&detach/1) |> List.to_tuple()

  defp detach([head | tail]), do: [detach(head) | detach(tail)]
  defp detach(value), do: value

  defp reserve(_admission, 0), do: false

  defp reserve(admission, attempts) do
    count = pending(admission)

    cond do
      count >= admission.capacity -> false
      :atomics.compare_exchange(admission.counter, 1, count, count + 1) == :ok -> true
      true -> reserve(admission, attempts - 1)
    end
  end
end
