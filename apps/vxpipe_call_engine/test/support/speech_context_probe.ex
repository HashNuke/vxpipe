defmodule Vxpipe.CallEngine.SpeechContextProbe do
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STSProvider
  alias Vxpipe.CallEngine.Provider.MorseCodeSTS.Session, as: Morse
  alias Vxpipe.CallEngine.Speech.{Channel, Event, STSProvider}

  def configure(options) do
    {opt_in, options} = Keyword.pop(options, :response_start?, true)

    with {:ok, descriptor} <- Morse.configure(options),
         do: {:ok, Map.put(descriptor, :response_start?, opt_in)}
  end

  def start_link(options), do: STSProvider.start_link(__MODULE__, options)

  def submit_input(pid, context, operation),
    do: GenServer.call(pid, {:context_input, context, operation})

  def push_audio(pid, pcm), do: GenServer.call(pid, {:legacy, {:audio, pcm}})
  def push_text(pid, ref, text), do: GenServer.call(pid, {:legacy, {:text, ref, text}})
  def input_activity(pid, boundary), do: GenServer.call(pid, {:legacy, {:activity, boundary}})
  def interrupt(_, _), do: {:error, :unsupported_operation}
  def send_tool_result(_, _, _), do: {:error, :unsupported_operation}
  def close(pid), do: GenServer.stop(pid)

  def init(options) do
    channel = Keyword.fetch!(options, :channel)
    private = Keyword.fetch!(options, :private)
    :ok = Channel.bind(channel)

    if not Keyword.get(private, :hold_ready?, false),
      do: :ok = Event.emit(channel, :ready, readiness: :initialized)

    send(Keyword.fetch!(private, :observer), {:context_probe_bound, channel})

    {:ok,
     %{
       channel: channel,
       observer: Keyword.fetch!(private, :observer),
       result: :ok,
       held: nil,
       hold?: false,
       early_response: nil
     }}
  end

  def handle_call({:configure_result, result, hold?}, _, state),
    do: {:reply, :ok, %{state | result: result, hold?: hold?}}

  def handle_call({:configure_early_response, turn, index}, _, state),
    do: {:reply, :ok, %{state | early_response: {turn, index}}}

  def handle_call({:configure_early_response, turn, index, context}, _, state),
    do: {:reply, :ok, %{state | early_response: {turn, index, context}}}

  def handle_call({:emit_response, context, turn, index}, _, state) do
    result =
      Event.emit(state.channel, :response_started,
        turn_ref: turn,
        response_index: index,
        response_context: context
      )

    {:reply, result, state}
  end

  def handle_call({:emit, kind, fields}, _, state),
    do: {:reply, Event.emit(state.channel, kind, fields), state}

  def handle_call(:release, _, state) do
    GenServer.reply(state.held, state.result)
    {:reply, :ok, %{state | held: nil}}
  end

  def handle_call({:provider_context_attempt, context}, _, state) do
    allocation = :sys.get_state(state.channel).allocation

    result =
      Vxpipe.CallEngine.Speech.Session.push_audio(allocation, <<0, 0>>, response_context: context)

    {:reply, result, state}
  end

  def handle_call({:context_input, context, operation}, from, state) do
    snapshot = :sys.get_state(state.channel)
    send(state.observer, {:context_input, context, operation, snapshot.response_contexts})

    if state.early_response do
      {turn, index, response_context} =
        case state.early_response do
          {turn, index} -> {turn, index, context}
          {turn, index, override} -> {turn, index, override}
        end

      result =
        Event.emit(state.channel, :response_started,
          turn_ref: turn,
          response_index: index,
          response_context: response_context
        )

      send(state.observer, {:early_response, result})
    end

    case operation do
      {:text, ref, _} ->
        result =
          Event.emit(state.channel, :input_submitted,
            request_ref: ref,
            provenance: :locally_measured
          )

        send(state.observer, {:early_semantics, result})

      _ ->
        :ok
    end

    if state.hold?,
      do: {:noreply, %{state | held: from}},
      else: {:reply, state.result, state}
  end

  def handle_call({:legacy, operation}, _, state) do
    send(state.observer, {:legacy_input, operation})
    {:reply, :ok, state}
  end

  def handle_info({:vxpipe_speech_output, channel, turn, reference}, state) do
    if channel == GenServer.whereis(state.channel),
      do: send(state.observer, {:context_output_granted, turn, reference})

    {:noreply, state}
  end

  def handle_info({:vxpipe_speech_response_discard, channel, turn}, state) do
    if channel == GenServer.whereis(state.channel),
      do: send(state.observer, {:context_response_discarded, turn})

    {:noreply, state}
  end

  def handle_info({:vxpipe_speech_output_settled, _channel, _turn, _reference, _played}, state),
    do: {:noreply, state}
end
