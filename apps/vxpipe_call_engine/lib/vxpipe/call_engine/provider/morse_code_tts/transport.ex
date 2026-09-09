defmodule Vxpipe.CallEngine.Provider.MorseCodeTTS.Transport do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Provider.TextToSpeech.Transport

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}

  @call_timeout 5_000

  @impl true
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def send_control(transport, payload) when is_binary(payload) do
    GenServer.call(transport, {:send_control, payload}, @call_timeout)
  end

  @impl true
  def close(transport), do: GenServer.call(transport, :close, @call_timeout)

  @impl true
  def init(options) do
    transport_options = Keyword.fetch!(options, :transport_options)

    with %{config: %Config{} = config} <- Keyword.fetch!(options, :connection),
         {:ok, chunk_samples, emit_interval_ms} <- transport_settings(config, transport_options) do
      {:ok,
       %{
         awaiting_audio: nil,
         chunk_samples: chunk_samples,
         emit_interval_ms: emit_interval_ms,
         encoder: nil,
         generation: 0,
         next_speech_number: 1,
         owner: Keyword.fetch!(options, :owner),
         pending_text: nil,
         speech_id: nil,
         text: nil,
         config: config
       }}
    else
      _invalid -> {:stop, :invalid_transport_options}
    end
  end

  @impl true
  def handle_call({:send_control, payload}, _from, state) do
    case JSON.decode(payload) do
      {:ok, %{"type" => "Speak", "text" => text}} when is_binary(text) ->
        handle_speak(text, state)

      {:ok, %{"type" => "Flush"}} ->
        handle_flush(state)

      {:ok, %{"type" => "Interrupt", "playback_offset_ms" => played_ms}}
      when is_integer(played_ms) and played_ms >= 0 ->
        handle_interrupt(played_ms, state)

      _invalid ->
        {:reply, {:error, :invalid_control}, state}
    end
  end

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, clear_active(state)}

  @impl true
  def handle_info({:emit_audio, generation}, %{generation: generation} = state) do
    case state do
      %{encoder: nil} ->
        {:noreply, state}

      %{awaiting_audio: reference} when is_reference(reference) ->
        {:noreply, state}

      _active ->
        emit_next_audio(state)
    end
  end

  def handle_info({:emit_audio, _stale_generation}, state), do: {:noreply, state}

  def handle_info(
        {:vxpipe_tts_audio_result, owner, reference, :ok},
        %{owner: owner, awaiting_audio: reference} = state
      ) do
    state = %{state | awaiting_audio: nil}
    schedule_emit(state.generation, state.emit_interval_ms)
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_tts_audio_result, owner, reference, {:error, _reason}},
        %{owner: owner, awaiting_audio: reference} = state
      ) do
    {:noreply, emit_error(:audio_output_failed, clear_active(state))}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp handle_speak(text, %{pending_text: nil, encoder: nil} = state) do
    {:reply, :ok, %{state | pending_text: text}}
  end

  defp handle_speak(_text, state), do: {:reply, {:error, :speech_in_progress}, state}

  defp handle_flush(%{pending_text: text, encoder: nil} = state) when is_binary(text) do
    case Encoder.start(state.config, text) do
      {:ok, encoder} ->
        speech_id = "morse-#{state.next_speech_number}"
        generation = state.generation + 1

        state = %{
          state
          | encoder: encoder,
            generation: generation,
            next_speech_number: state.next_speech_number + 1,
            pending_text: nil,
            speech_id: speech_id,
            text: text
        }

        emit_control(%{"type" => "SpeechStarted", "speech_id" => speech_id}, state)
        schedule_emit(generation, 0)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, :ok, emit_error(reason, %{state | pending_text: nil})}
    end
  end

  defp handle_flush(state), do: {:reply, {:error, :nothing_to_flush}, state}

  defp handle_interrupt(played_ms, %{encoder: %Encoder{}, speech_id: speech_id} = state) do
    message = %{
      "type" => "SpeechInterrupted",
      "speech_id" => speech_id,
      "audio_played_ms" => played_ms,
      "text_spoken" => "",
      "text_remaining" => state.text
    }

    emit_control(message, state)
    {:reply, :ok, state |> clear_active() |> Map.update!(:generation, &(&1 + 1))}
  end

  defp handle_interrupt(_played_ms, state), do: {:reply, :ok, state}

  defp emit_next_audio(state) do
    case Encoder.next(state.encoder, state.chunk_samples) do
      {:ok, audio, encoder} ->
        reference = make_ref()
        send(state.owner, {:vxpipe_tts_transport, self(), {:audio, reference, audio}})
        {:noreply, %{state | awaiting_audio: reference, encoder: encoder}}

      :done ->
        emit_control(%{"type" => "SpeechMetadata", "speech_id" => state.speech_id}, state)
        {:noreply, clear_active(state)}
    end
  end

  defp emit_error(reason, state) do
    emit_control(%{"type" => "Error", "code" => error_code(reason)}, state)
    state
  end

  defp emit_control(message, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:control, JSON.encode!(message)}})
    :ok
  end

  defp clear_active(state) do
    %{
      state
      | awaiting_audio: nil,
        encoder: nil,
        pending_text: nil,
        speech_id: nil,
        text: nil
    }
  end

  defp schedule_emit(generation, 0), do: send(self(), {:emit_audio, generation})

  defp schedule_emit(generation, delay_ms) do
    _timer = Process.send_after(self(), {:emit_audio, generation}, delay_ms)
    :ok
  end

  defp transport_settings(config, options) when is_list(options) do
    chunk_duration_ms = Keyword.get(options, :chunk_duration_ms, 20)
    emit_interval_ms = Keyword.get(options, :emit_interval_ms, chunk_duration_ms)

    valid_chunk? =
      is_integer(chunk_duration_ms) and chunk_duration_ms > 0 and chunk_duration_ms <= 100 and
        rem(config.sample_rate * chunk_duration_ms, 1_000) == 0

    valid_interval? =
      is_integer(emit_interval_ms) and emit_interval_ms >= 0 and emit_interval_ms <= 1_000

    if valid_chunk? and valid_interval? do
      {:ok, div(config.sample_rate * chunk_duration_ms, 1_000), emit_interval_ms}
    else
      {:error, :invalid_transport_options}
    end
  end

  defp transport_settings(_config, _options), do: {:error, :invalid_transport_options}

  defp error_code(reason) do
    reason
    |> Atom.to_string()
    |> String.upcase()
  end
end
