defmodule Vxpipe.CallEngine.Speech.Silero do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.Silero.Model

  @frame_bytes 1_024
  @derive {Inspect, only: [:samples]}
  defstruct samples: 0, recurrent: nil, context: nil, pending: ""

  defdelegate load(), to: Model
  def new, do: %__MODULE__{}
  def reset(%__MODULE__{}), do: new()
  def pending_bytes(%__MODULE__{pending: pending}), do: byte_size(pending)

  def valid_audio?(audio),
    do: is_binary(audio) and byte_size(audio) in 2..32_000 and rem(byte_size(audio), 2) == 0

  def push(%__MODULE__{} = state, %Model{} = model, audio) do
    if valid_audio?(audio) do
      {state, probabilities} = frames(state, model, state.pending <> audio, [])
      {:ok, state, Enum.reverse(probabilities)}
    else
      {:error, :invalid_audio}
    end
  rescue
    _error -> {:error, :classification_failed}
  catch
    _kind, _reason -> {:error, :classification_failed}
  end

  defp frames(state, _model, audio, probabilities) when byte_size(audio) < @frame_bytes,
    do: {%{state | pending: audio}, probabilities}

  defp frames(state, model, <<frame::binary-size(@frame_bytes), rest::binary>>, probabilities) do
    recurrent = state.recurrent || Nx.broadcast(Nx.tensor(0, type: :f32), {2, 1, 128})
    context = state.context || Nx.broadcast(Nx.tensor(0, type: :f32), {1, 64})

    # Explicit little-endian decoding keeps the PCM contract independent of host endianness.
    samples =
      for <<sample::signed-little-16 <- frame>>,
        into: <<>>,
        do: <<sample / 32_768.0::float-native-32>>

    frame_input = samples |> Nx.from_binary(:f32) |> Nx.reshape({1, 512})
    input = Nx.concatenate([context, frame_input], axis: 1)

    {probability, recurrent} =
      Ortex.run_cpu(model.resource, {input, recurrent, model.sample_rate})

    probability = probability |> Nx.reshape({}) |> Nx.to_number()

    if is_number(probability) and probability >= 0 and probability <= 1 do
      state = %{
        state
        | samples: state.samples + 512,
          recurrent: recurrent,
          context: Nx.slice(input, [0, 512], [1, 64])
      }

      frames(state, model, rest, [probability | probabilities])
    else
      throw(:invalid_probability)
    end
  end
end
