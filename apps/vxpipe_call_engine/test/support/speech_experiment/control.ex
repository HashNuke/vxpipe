defmodule Vxpipe.CallEngine.SpeechExperiment.Control do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.SpeechExperiment.Worker

  def address(token),
    do: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, token}}}

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: address(Keyword.fetch!(options, :token)))

  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    token = Keyword.fetch!(options, :token)
    delay = max(0, Keyword.fetch!(options, :deadline) - System.monotonic_time(:millisecond))
    timer = Process.send_after(self(), :startup_expired, delay)

    {:ok,
     %{
       owner: owner,
       monitor: Process.monitor(owner),
       token: token,
       kind: Keyword.fetch!(options, :kind),
       observer: Keyword.get(options, :observer),
       ready?: false,
       deadline: Keyword.fetch!(options, :deadline),
       credit_timeout: Keyword.get(options, :credit_timeout, 15_000),
       credit_timer: nil,
       timer: timer,
       pending: nil,
       sequence: 0,
       turn: 0,
       text: nil,
       generation: nil,
       awaiting: nil
     }}
  end

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}
  def handle_call(:inspect_scope, _from, state), do: {:reply, state.token, state}

  def handle_call({:audio, _audio}, _from, %{ready?: false} = state),
    do: {:reply, {:error, :not_ready}, state}

  def handle_call({:audio, audio}, from, %{pending: nil} = state)
      when is_binary(audio) and byte_size(audio) in 1..131_072 do
    command = make_ref()
    GenServer.cast(Worker.address(state.token), {:audio, command, audio})
    timer = Process.send_after(self(), {:command_expired, command}, 5_000)
    {:noreply, %{state | pending: {command, from, timer}}}
  end

  def handle_call({:audio, _audio}, _from, state),
    do: {:reply, {:error, :busy_or_invalid}, state}

  def handle_call({:control, payload}, _from, state) do
    control(JSON.decode!(payload), state)
  end

  def handle_info({:semantic, :ready}, %{ready?: true} = state), do: {:noreply, state}

  def handle_info({:semantic, :ready}, state) do
    if System.monotonic_time(:millisecond) < state.deadline do
      Process.cancel_timer(state.timer)
      observe(state, :ready)
      state = if state.kind == :stt, do: emit_stt(state, %{"type" => "Connected"}), else: state
      {:noreply, %{state | ready?: true}}
    else
      {:stop, :normal, state}
    end
  end

  def handle_info({:semantic, {:stt, event}}, state), do: {:noreply, stt_event(event, state)}

  def handle_info(
        {:semantic, {:accepted, command, result}},
        %{pending: {command, from, timer}} = state
      ) do
    Process.cancel_timer(timer)
    GenServer.reply(from, result)
    observe(state, :input_accepted)
    {:noreply, %{state | pending: nil}}
  end

  def handle_info({:semantic, {:tts, generation, event}}, %{generation: generation} = state) do
    tts_event(event, state)
  end

  def handle_info({:semantic, {:tts, _generation, _event}}, state), do: {:noreply, state}

  def handle_info(
        {:vxpipe_tts_audio_result, owner, reference, result},
        %{owner: owner, awaiting: reference} = state
      ) do
    Process.cancel_timer(state.credit_timer)

    if result == :ok do
      GenServer.cast(Worker.address(state.token), {:credit, state.generation, result})
      {:noreply, %{state | awaiting: nil, credit_timer: nil}}
    else
      {:stop, :normal, state}
    end
  end

  def handle_info({:credit_expired, reference}, %{awaiting: reference} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info(:startup_expired, %{ready?: false} = state), do: {:stop, :normal, state}

  def handle_info({:command_expired, command}, %{pending: {command, from, _}} = state) do
    GenServer.reply(from, {:error, :timeout})
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp control(%{"type" => kind}, %{ready?: false} = state) when kind in ["Speak", "Flush"],
    do: {:reply, {:error, :not_ready}, state}

  defp control(%{"type" => "Speak", "text" => text}, %{text: nil} = state),
    do: {:reply, :ok, %{state | text: text}}

  defp control(%{"type" => "Flush"}, %{text: text} = state) when is_binary(text) do
    generation = state.sequence + 1
    GenServer.cast(Worker.address(state.token), {:speak, generation, text})
    {:reply, :ok, %{state | generation: generation, sequence: generation}}
  end

  defp control(%{"type" => "Interrupt", "playback_offset_ms" => played}, state) do
    GenServer.cast(Worker.address(state.token), {:cancel, state.generation})
    if state.credit_timer, do: Process.cancel_timer(state.credit_timer)

    if state.generation do
      emit_tts(state, %{
        "type" => "SpeechInterrupted",
        "audio_played_ms" => played,
        "text_spoken" => "",
        "text_remaining" => state.text || ""
      })
    end

    {:reply, :ok, %{state | generation: nil, awaiting: nil, text: nil, credit_timer: nil}}
  end

  defp control(_control, state), do: {:reply, {:error, :invalid_control}, state}

  defp stt_event(:started, state), do: emit_turn(state, "StartOfTurn", "")
  defp stt_event({:partial, text}, state), do: emit_turn(state, "Update", text)

  defp stt_event({:final, text}, state) do
    state = emit_turn(state, "EndOfTurn", text)
    %{state | turn: state.turn + 1}
  end

  defp emit_turn(state, event, text) do
    emit_stt(state, %{
      "type" => "TurnInfo",
      "event" => event,
      "transcript" => text,
      "turn_index" => state.turn,
      "trigger" => "morse_end_gap"
    })
  end

  defp emit_stt(state, message) do
    message =
      Map.merge(message, %{"sequence_id" => state.sequence, "request_id" => "morse-local"})

    send(state.owner, {:vxpipe_stt_transport, self(), {:message, JSON.encode!(message)}})
    %{state | sequence: state.sequence + 1}
  end

  defp tts_event(:started, state) do
    emit_tts(state, %{"type" => "SpeechStarted"})
    {:noreply, state}
  end

  defp tts_event({:audio, audio}, %{awaiting: nil} = state) do
    reference = make_ref()
    timer = Process.send_after(self(), {:credit_expired, reference}, state.credit_timeout)
    send(state.owner, {:vxpipe_tts_transport, self(), {:audio, reference, audio}})
    {:noreply, %{state | awaiting: reference, credit_timer: timer}}
  end

  defp tts_event(:completed, state) do
    emit_tts(state, %{"type" => "SpeechMetadata"})
    observe(state, :generation_completed)
    {:noreply, %{state | generation: nil, awaiting: nil, text: nil}}
  end

  defp emit_tts(state, message) do
    message = Map.put(message, "speech_id", "morse-#{state.generation}")
    send(state.owner, {:vxpipe_tts_transport, self(), {:control, JSON.encode!(message)}})
  end

  defp observe(%{observer: observer}, event) when is_pid(observer),
    do: send(observer, {:experiment_observed, self(), event, System.monotonic_time(:microsecond)})

  defp observe(_state, _event), do: :ok
end
