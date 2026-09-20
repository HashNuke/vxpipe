defmodule Vxpipe.CallEngine.SpeechSegmentedSTTProfile do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, STTProvider}

  @impl true
  def configure(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             sample_rate: 16_000,
             endpointing: :provider_semantic,
             speech_start?: true
           ),
         sample_rate when is_integer(sample_rate) and sample_rate > 0 <-
           Keyword.fetch!(options, :sample_rate),
         endpointing when endpointing in [:provider_semantic, :none] <-
           Keyword.fetch!(options, :endpointing),
         speech_start? when is_boolean(speech_start?) <- Keyword.fetch!(options, :speech_start?) do
      semantic? = endpointing == :provider_semantic

      Descriptor.new(
        kind: :stt,
        settings: %{sample_rate: sample_rate, endpointing: endpointing},
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: sample_rate,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{
          provider: :segmented_profile,
          model: :revision_and_commit,
          provenance: :locally_measured
        },
        readiness: :initialized,
        endpointing: endpointing,
        speech_start?: speech_start?,
        eager_end?: semantic?,
        resume?: semantic?
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def start_link(options), do: STTProvider.start_link(__MODULE__, options)

  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:push_audio, audio}, 5_000)

  @impl true
  def close(pid), do: GenServer.call(pid, :close, 5_000)

  @impl true
  def init(options) do
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = Keyword.fetch!(options, :channel)
    private = Keyword.fetch!(options, :private)
    credential = Keyword.get(private, :credential)
    observer = Keyword.get(private, :observer)

    with true <- is_binary(credential) and byte_size(credential) > 0,
         true <- is_pid(observer),
         :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: :initialized) do
      send(observer, {:speech_profile_stt_started, self()})

      {:ok,
       %{
         channel: channel,
         endpointing: descriptor.endpointing,
         observer: observer,
         step: 0,
         turn_ref: nil
       }}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:push_audio, <<command>>}, _from, %{step: step} = state)
      when command == step + 1 do
    case publish(command, state) do
      {:ok, state} -> {:reply, :ok, %{state | step: command}}
      {:error, _reason} -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:push_audio, _audio}, _from, state),
    do: {:reply, {:error, :session_failed}, state}

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :segmented_stt_profile)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp publish(1, state) do
    turn_ref = make_ref()

    with :ok <- Event.emit(state.channel, :speech_started, turn_ref: turn_ref),
         do: {:ok, %{state | turn_ref: turn_ref}}
  end

  defp publish(2, state), do: transcript(state, "hel")
  defp publish(3, state), do: transcript(state, "hello")

  defp publish(4, state) do
    with {:ok, state} <- transcript(state, "hello ") do
      send(state.observer, {:speech_profile_segment_committed, "hello "})
      {:ok, state}
    end
  end

  defp publish(5, state), do: transcript(state, "hello worl")

  defp publish(6, state) do
    emit(state, :eager_turn_ended,
      turn_ref: state.turn_ref,
      text: "hello world",
      endpointing: state.endpointing,
      audio_duration_ms: 600
    )
  end

  defp publish(7, state), do: emit(state, :turn_resumed, turn_ref: state.turn_ref)

  defp publish(8, state) do
    with {:ok, state} <-
           emit(state, :turn_ended,
             turn_ref: state.turn_ref,
             text: "hello world!",
             endpointing: state.endpointing,
             audio_duration_ms: 800
           ) do
      {:ok, %{state | turn_ref: nil}}
    end
  end

  defp transcript(state, text),
    do: emit(state, :transcript, turn_ref: state.turn_ref, text: text)

  defp emit(state, kind, fields) do
    case Event.emit(state.channel, kind, fields) do
      :ok -> {:ok, state}
      {:error, _reason} = error -> error
    end
  end
end
