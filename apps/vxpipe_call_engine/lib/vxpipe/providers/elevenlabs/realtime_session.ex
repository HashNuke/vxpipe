defmodule Vxpipe.Providers.ElevenLabs.RealtimeSession do
  @moduledoc "ElevenLabs Realtime speech-to-speech with provider-native turn detection."

  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, Opening, SessionTree, STSProvider}
  alias Vxpipe.Providers.ElevenLabs.{Realtime, RealtimeAPI, RealtimeOutput, RealtimeSocket}

  @impl true
  defdelegate models(), to: Realtime

  @impl true
  def configure(options) do
    with {:ok, public} <- Realtime.public_options(options) do
      Descriptor.new(
        kind: :sts,
        settings: public,
        input_format: Realtime.pcm_format(),
        format: Realtime.pcm_format(),
        usage_identity: %{
          provider: :elevenlabs,
          model: public.model,
          provenance: :locally_measured
        },
        readiness: :provider_acknowledged,
        endpointing: :provider_semantic,
        speech_start?: true,
        turn_control: "provider",
        turn_control_supported: ["provider"],
        input_transcript?: true,
        output_transcript?: true,
        response_start?: true,
        output_settlement: :transcript_end,
        history_reconciliation?: false,
        output_shape: :turns,
        barge_in: :room,
        continuity: :none,
        tool_cancellation?: true,
        hold: :stop,
        input_cutover: :close
      )
    end
  end

  @impl true
  def start_link(options), do: STSProvider.start_link(__MODULE__, options)
  @impl true
  def submit_input(pid, context, operation),
    do: GenServer.call(pid, {:input, context, operation}, 5_000)

  @impl true
  def push_audio(_pid, _audio), do: {:error, :unsupported_operation}
  @impl true
  def push_text(_pid, _ref, _text), do: {:error, :unsupported_operation}
  @impl true
  def input_activity(_pid, _boundary), do: {:error, :unsupported_operation}
  @impl true
  def input_quiescent?(pid), do: GenServer.call(pid, :quiescent, 1_000)
  @impl true
  def interrupt(pid, turn), do: GenServer.call(pid, {:interrupt, turn}, 5_000)
  @impl true
  def send_tool_result(pid, ref, result),
    do: GenServer.call(pid, {:tool_result, ref, result}, 5_000)

  @impl true
  def close(pid) do
    GenServer.call(pid, :close, 5_000)
  catch
    :exit, {:noproc, _call} -> :ok
    :exit, {:normal, _call} -> :ok
  end

  @impl true
  def init(options) do
    private = Keyword.fetch!(options, :private)
    config = Keyword.fetch!(private, :config)
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    descriptor = Keyword.fetch!(options, :descriptor)

    with :ok <- Realtime.validate(config),
         {:ok, ^descriptor} <- configure(model: config.model, voice: config.voice),
         :ok <- Channel.bind(channel) do
      {:ok,
       %{
         channel: channel,
         config: config,
         supervisor: SessionTree.providers(Keyword.fetch!(options, :allocation)),
         api: Keyword.get(private, :api_module, RealtimeAPI),
         api_options: Keyword.get(private, :api_options, []),
         wire_module: Keyword.get(private, :wire_module, RealtimeSocket),
         wire_options: Keyword.get(private, :wire_options, []),
         wire: nil,
         bootstrap: nil,
         ready?: false,
         context: nil,
         audio_pending?: false,
         audio_serial: 0,
         callers: %{},
         native_origin: nil,
         responses: %{},
         queue: [],
         active: nil,
         retired: [],
         tools: %{},
         index: 0
       }, {:continue, :connect}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_continue(:connect, state) do
    owner = self()

    task = %{
      id: :realtime_credentials,
      start:
        {Task, :start_link,
         [
           fn ->
             result = state.api.connect(state.config, state.api_options)
             send(owner, {:realtime_credentials, self(), result})
           end
         ]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(state.supervisor, task) do
      {:ok, pid} ->
        Process.send_after(self(), :setup_timeout, 20_000)
        {:noreply, %{state | bootstrap: pid}}

      _failure ->
        stop(state)
    end
  end

  @impl true
  def handle_call(:close, _from, state) do
    if state.wire, do: state.wire_module.close(state.wire)
    {:stop, :normal, :ok, state}
  end

  def handle_call(:quiescent, _from, state),
    do: {:reply, state.audio_serial == 0 and map_size(state.responses) == 0, state}

  def handle_call({:input, _context, _operation}, _from, %{ready?: false} = state),
    do: {:reply, {:error, :busy}, state}

  # Native stop events do not acknowledge consumption of every accepted PCM byte.
  # Keep one authorization origin for this allocation; cutover needs a new one.
  def handle_call({:input, context, _operation}, _from, %{context: bound} = state)
      when is_reference(bound) and context != bound,
      do: stop_reply(state)

  def handle_call({:input, context, {:audio, pcm}}, _from, state) when is_reference(context) do
    with true <- not explicit_waiting?(state) and not queued_input?(state),
         {:ok, message} <- Realtime.audio(pcm),
         :ok <- send_wire(state, message) do
      {:reply, :ok,
       %{state | context: context, audio_pending?: true, audio_serial: state.audio_serial + 1}}
    else
      false -> {:reply, {:error, :busy}, state}
      {:error, :invalid_audio} -> {:reply, {:error, :invalid_audio}, state}
      _failure -> stop_reply(state)
    end
  end

  def handle_call({:input, context, {:text, ref, text}}, _from, state)
      when is_reference(context) and is_reference(ref) do
    with true <-
           not state.audio_pending? and is_nil(state.native_origin) and
             map_size(state.callers) == 0 and map_size(state.responses) < 16,
         {:ok, message} <- Realtime.text(token(), text),
         :ok <- send_wire(state, message),
         :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: ref,
             provenance: :locally_measured
           ),
         {:ok, state} <- enqueue(%{state | context: context}, context, nil, nil) do
      {:reply, :ok, state}
    else
      false -> {:reply, {:error, :busy}, state}
      {:error, :invalid_text} -> {:reply, {:error, :invalid_text}, state}
      _failure -> stop_reply(state)
    end
  end

  def handle_call({:input, context, {:opening, ref, opening}}, _from, state)
      when is_reference(context) and is_reference(ref) do
    if Opening.valid?(opening) and map_size(state.responses) == 0 and not state.audio_pending? do
      {instructions, fixed} = opening_instructions(opening)

      with :ok <-
             Event.emit(state.channel, :input_submitted,
               request_ref: ref,
               provenance: :locally_measured
             ),
           {:ok, state} <- enqueue(%{state | context: context}, context, instructions, fixed) do
        {:reply, :ok, state}
      else
        _failure -> stop_reply(state)
      end
    else
      {:reply, {:error, :busy}, state}
    end
  end

  def handle_call({:input, _context, _operation}, _from, state),
    do: {:reply, {:error, :unsupported_operation}, state}

  def handle_call({:interrupt, turn}, _from, state) do
    case interrupt_turn(state, turn) do
      {:ok, state} -> {:reply, :ok, state}
      _failure -> stop_reply(state)
    end
  end

  def handle_call({:tool_result, ref, result}, _from, state) do
    case Map.fetch(state.tools, ref) do
      {:ok, %{id: id, token: token}} ->
        with {:ok, message} <- Realtime.tool_result(id, result),
             :ok <- send_wire(state, message),
             {:ok, state} <- continue_tools(%{state | tools: Map.delete(state.tools, ref)}, token) do
          {:reply, :ok, state}
        else
          {:error, :invalid_tool_result} -> {:reply, {:error, :invalid_tool_result}, state}
          _failure -> stop_reply(state)
        end

      :error ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  @impl true
  def handle_info({:realtime_credentials, pid, {:ok, connection}}, %{bootstrap: pid} = state) do
    options = [owner: self(), connection: connection, transport_options: state.wire_options]

    child = %{
      id: state.wire_module,
      start: {state.wire_module, :start_link, [options]},
      restart: :temporary,
      shutdown: :brutal_kill
    }

    case DynamicSupervisor.start_child(state.supervisor, child) do
      {:ok, wire} ->
        Process.monitor(wire)
        {:noreply, %{state | wire: wire, bootstrap: nil}}

      _failure ->
        stop(state)
    end
  end

  def handle_info({:realtime_credentials, pid, _failure}, %{bootstrap: pid} = state),
    do: stop(state)

  def handle_info({:elevenlabs_realtime, wire, credit, payload}, %{wire: wire} = state) do
    case handle_info({:elevenlabs_realtime, wire, payload}, state) do
      {:noreply, state} ->
        :ok = RealtimeSocket.ack(wire, credit)
        {:noreply, state}

      stopped ->
        stopped
    end
  end

  def handle_info({:elevenlabs_realtime, wire, payload}, %{wire: wire} = state) do
    with {:ok, event} <- Realtime.decode(payload),
         {:ok, state} <- wire_event(state, event),
         {:ok, state} <- drain(state) do
      {:noreply, state}
    else
      {:error, reason} ->
        :telemetry.execute([:vxpipe, :elevenlabs, :realtime, :failure], %{count: 1}, %{
          reason: reason
        })

        stop(state)
    end
  end

  def handle_info({:elevenlabs_realtime_closed, wire}, %{wire: wire} = state), do: stop(state)
  def handle_info({:DOWN, _ref, :process, wire, _reason}, %{wire: wire} = state), do: stop(state)
  def handle_info(:setup_timeout, %{ready?: false} = state), do: stop(state)

  def handle_info({:native_timeout, turn}, %{native_origin: %{turn: turn}} = state),
    do: stop(state)

  def handle_info({:caller_timeout, id, turn}, state) do
    case Map.get(state.callers, id) do
      %{turn: ^turn, stopped?: true} -> stop(state)
      _settled -> {:noreply, state}
    end
  end

  def handle_info({:response_timeout, token}, state) do
    case Map.get(state.responses, token) do
      %{completed?: false, interrupted?: false} -> stop(state)
      %{done?: false} -> stop(state)
      _retired -> {:noreply, state}
    end
  end

  def handle_info({:vxpipe_speech_output, channel, turn, output}, %{channel: channel} = state) do
    update_turn(state, turn, fn response ->
      if is_nil(response.output),
        do: {:ok, %{response | output: output}},
        else: {:error, :duplicate_grant}
    end)
  end

  def handle_info(
        {:vxpipe_speech_credit, channel, output, credit, :ok},
        %{channel: channel} = state
      ) do
    case Enum.find(state.responses, fn {_token, response} ->
           response.output == output and response.awaiting == credit
         end) do
      {token, response} -> finish_update(state, token, %{response | awaiting: nil})
      nil -> {:noreply, state}
    end
  end

  def handle_info(
        {:vxpipe_speech_credit, channel, _output, _credit, _failure},
        %{channel: channel} = state
      ),
      do: stop(state)

  def handle_info(
        {:vxpipe_speech_output_settled, channel, turn, output, _played},
        %{channel: channel} = state
      ) do
    update_turn(state, turn, fn response ->
      if response.output == output and response.completed?,
        do: {:ok, %{response | settled?: true}},
        else: {:error, :invalid_settlement}
    end)
  end

  def handle_info({:vxpipe_speech_response_discard, channel, turn}, %{channel: channel} = state) do
    case interrupt_turn(state, turn) do
      {:ok, state} ->
        update_turn(state, turn, fn response -> {:ok, %{response | settled?: true}} end)

      _failure ->
        stop(state)
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status),
    do:
      status
      |> Map.put(:state, %{provider: :elevenlabs_realtime})
      |> Map.put(:message, :redacted)
      |> Map.put(:reason, :redacted)
      |> Map.put(:log, [])

  defp wire_event(state, :ignored), do: {:ok, state}

  defp wire_event(state, {:session, _model, session}) do
    if Realtime.acknowledged?(state.config, session) do
      if not state.ready?,
        do: Event.emit(state.channel, :ready, readiness: :provider_acknowledged)

      {:ok, %{state | ready?: true}}
    else
      {:error, :configuration_not_acknowledged}
    end
  end

  defp wire_event(%{ready?: false}, _event), do: {:error, :not_ready}

  defp wire_event(state, {:speech_started, id}) do
    if is_reference(state.context) and not Map.has_key?(state.callers, id) and
         map_size(state.callers) < 16 do
      caller = %{
        turn: make_ref(),
        context: state.context,
        stopped?: false,
        text: nil,
        stop_serial: nil
      }

      with :ok <- Event.emit(state.channel, :speech_started, turn_ref: caller.turn) do
        {:ok, %{state | callers: Map.put(state.callers, id, caller)}}
      end
    else
      {:error, :invalid_caller}
    end
  end

  defp wire_event(%{native_origin: nil} = state, {:speech_stopped, id}) do
    with {:ok, caller} <- Map.fetch(state.callers, id) do
      origin = %{context: caller.context, turn: caller.turn}
      Process.send_after(self(), {:caller_timeout, id, caller.turn}, 30_000)
      Process.send_after(self(), {:native_timeout, caller.turn}, 30_000)

      update_caller(%{state | native_origin: origin}, id, fn caller ->
        %{caller | stopped?: true, stop_serial: state.audio_serial}
      end)
    else
      _failure -> {:error, :unknown_caller}
    end
  end

  defp wire_event(state, {:input_transcript, id, text}),
    do: update_caller(state, id, &Map.put(&1, :text, text))

  defp wire_event(
         %{active: nil, native_origin: %{context: context}} = state,
         {:response_created, id, echoed}
       )
       when is_reference(context) do
    if map_size(state.responses) < 16 do
      token = token()
      response = RealtimeOutput.new(context, nil, nil, nil)
      Process.send_after(self(), {:response_timeout, token}, 30_000)

      state = %{
        put_response(state, token, response)
        | active: token,
          native_origin: nil
      }

      wire_event(state, {:response_created, id, echoed})
    else
      {:error, :response_overflow}
    end
  end

  defp wire_event(%{active: token} = state, {:response_created, id, echoed})
       when is_binary(token) do
    response = Map.fetch!(state.responses, token)

    if is_nil(response.id) and is_nil(state.native_origin) and
         (is_nil(echoed) or echoed == token) and not known_id?(state, id) do
      response = %{response | id: id}
      state = put_response(state, token, response)
      result = if response.interrupted?, do: send_wire(state, Realtime.cancel(id)), else: :ok
      with :ok <- result, do: {:ok, state}
    else
      {:error, :unexpected_response}
    end
  end

  defp wire_event(state, {:audio, id, pcm}) do
    with {:ok, state} <- update_response(state, id, &RealtimeOutput.audio(&1, pcm)) do
      announce_audio(state, id)
    end
  end

  defp wire_event(state, {:output_transcript, id, text}),
    do: update_response(state, id, &RealtimeOutput.transcript(&1, text))

  defp wire_event(state, {:response_done, id, status}) do
    with {:ok, token, response} <- response_by_id(state, id),
         true <- token == state.active and not response.done?,
         true <- status == "completed" or (status == "cancelled" and response.interrupted?) do
      response = %{response | done?: true}

      response =
        if not response.announced?,
          do: %{response | completed?: true, settled?: true},
          else: response

      state = put_response(%{state | active: nil}, token, response)
      with {:ok, state} <- continue_tools(state, token), do: dispatch(state)
    else
      :retired -> {:ok, state}
      _failure -> {:error, :invalid_completion}
    end
  end

  defp wire_event(state, {:tool_call, response_id, id, name, arguments}) do
    case response_by_id(state, response_id) do
      {:ok, _token, %{interrupted?: true}} -> {:ok, state}
      {:ok, token, response} -> accept_tool(state, token, response, id, name, arguments)
      :retired -> {:ok, state}
      _unknown -> {:error, :unknown_response}
    end
  end

  defp wire_event(_state, _event), do: {:error, :unexpected_event}

  defp update_caller(state, id, update) do
    case Map.fetch(state.callers, id) do
      {:ok, caller} ->
        caller = update.(caller)

        if caller.stopped? and is_binary(caller.text) do
          with :ok <-
                 Event.emit(state.channel, :input_transcript,
                   turn_ref: caller.turn,
                   text: caller.text,
                   final: true
                 ),
               :ok <-
                 Event.emit(state.channel, :turn_ended,
                   turn_ref: caller.turn,
                   text: caller.text,
                   endpointing: :provider_semantic
                 ) do
            callers = Map.delete(state.callers, id)
            pending? = state.audio_serial != caller.stop_serial or map_size(callers) > 0
            state = %{state | callers: callers, audio_pending?: pending?}

            dispatch(state)
          end
        else
          {:ok, %{state | callers: Map.put(state.callers, id, caller)}}
        end

      :error ->
        {:error, :unknown_caller}
    end
  end

  defp enqueue(state, context, instructions, fixed, continuation? \\ false) do
    if map_size(state.responses) < 16 do
      token = token()

      response = %{
        RealtimeOutput.new(context, nil, instructions, fixed)
        | continuation?: continuation?
      }

      Process.send_after(self(), {:response_timeout, token}, 30_000)

      dispatch(%{
        put_response(state, token, response)
        | queue: state.queue ++ [token]
      })
    else
      {:error, :response_overflow}
    end
  end

  defp dispatch(
         %{
           active: nil,
           native_origin: nil,
           callers: callers,
           queue: [token | rest]
         } = state
       )
       when map_size(callers) == 0 do
    response = Map.fetch!(state.responses, token)

    if not state.audio_pending? or response.continuation? do
      with :ok <- send_wire(state, Realtime.response(token, response.instructions)) do
        {:ok, %{state | active: token, queue: rest}}
      end
    else
      {:ok, state}
    end
  end

  defp dispatch(state), do: {:ok, state}

  defp continue_tools(state, token) do
    response = Map.fetch!(state.responses, token)
    pending? = Enum.any?(state.tools, fn {_ref, tool} -> tool.token == token end)

    if response.had_tools? and response.done? and not response.interrupted? and
         not response.continued? and not pending? do
      enqueue(
        put_response(state, token, %{response | continued?: true}),
        response.context,
        nil,
        nil,
        true
      )
    else
      {:ok, state}
    end
  end

  defp interrupt_turn(state, turn) do
    case Enum.find(state.responses, fn {_token, response} -> response.turn == turn end) do
      nil ->
        {:ok, state}

      {_token, %{interrupted?: true}} ->
        drain(state)

      {token, response} ->
        result =
          if response.id && not response.done?,
            do: send_wire(state, Realtime.cancel(response.id)),
            else: :ok

        with :ok <- result do
          tools =
            Enum.reduce(state.tools, %{}, fn {ref, tool}, retained ->
              if tool.token == token do
                Event.emit(state.channel, :tool_cancelled, call_ref: ref)
                retained
              else
                Map.put(retained, ref, tool)
              end
            end)

          response = RealtimeOutput.interrupt(response)

          response =
            if token in state.queue, do: %{response | done?: true, settled?: true}, else: response

          drain(%{
            put_response(state, token, response)
            | tools: tools,
              queue: List.delete(state.queue, token)
          })
        end
    end
  end

  defp update_response(state, id, update) do
    case response_by_id(state, id) do
      {:ok, token, response} ->
        with {:ok, response} <- update.(response), do: {:ok, put_response(state, token, response)}

      :retired ->
        {:ok, state}

      _unknown ->
        {:error, :unknown_response}
    end
  end

  defp response_by_id(state, id) do
    case Enum.find(state.responses, fn {_token, response} -> response.id == id end) do
      {token, response} -> {:ok, token, response}
      nil -> if id in state.retired, do: :retired, else: {:error, :unknown_response}
    end
  end

  defp known_id?(state, id), do: response_by_id(state, id) != {:error, :unknown_response}

  defp update_turn(state, turn, update) do
    case Enum.find(state.responses, fn {_token, response} -> response.turn == turn end) do
      {token, response} ->
        case update.(response) do
          {:ok, response} -> finish_update(state, token, response)
          _failure -> stop(state)
        end

      nil ->
        {:noreply, state}
    end
  end

  defp finish_update(state, token, response) do
    case drain(put_response(state, token, response)) do
      {:ok, state} -> {:noreply, state}
      _failure -> stop(state)
    end
  end

  defp drain(state) do
    Enum.reduce_while(state.responses, {:ok, state}, fn {token, response}, {:ok, current} ->
      case RealtimeOutput.drain(response, state.channel) do
        {:ok, response} ->
          current = put_response(current, token, response)
          pending? = Enum.any?(current.tools, fn {_ref, tool} -> tool.token == token end)

          current =
            if response.settled? and response.done? and not pending? do
              %{
                current
                | responses: Map.delete(current.responses, token),
                  retired: Enum.take([response.id | current.retired], 64)
              }
            else
              current
            end

          {:cont, {:ok, current}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp explicit_waiting?(%{active: nil}), do: false
  defp explicit_waiting?(state), do: is_nil(Map.fetch!(state.responses, state.active).id)

  defp queued_input?(state),
    do: Enum.any?(state.queue, &(not Map.fetch!(state.responses, &1).continuation?))

  defp announce_audio(state, id) do
    case response_by_id(state, id) do
      {:ok, token, %{announced?: false, interrupted?: false} = response} ->
        index = state.index + 1

        with :ok <-
               Event.emit(state.channel, :response_started,
                 turn_ref: response.turn,
                 response_context: response.context,
                 response_index: index
               ) do
          {:ok,
           %{
             put_response(state, token, %{response | announced?: true, index: index})
             | index: index
           }}
        end

      {:ok, _token, _response} ->
        {:ok, state}

      :retired ->
        {:ok, state}

      _unknown ->
        {:error, :unknown_response}
    end
  end

  defp accept_tool(state, token, response, id, name, arguments) do
    cond do
      MapSet.member?(response.tool_ids, id) ->
        {:ok, state}

      response.done? or not is_nil(response.fixed) ->
        {:error, :invalid_tool}

      map_size(state.tools) >= 16 or MapSet.size(response.tool_ids) >= 16 ->
        {:error, :tool_overflow}

      true ->
        ref = make_ref()

        with :ok <-
               Event.emit(state.channel, :tool_call,
                 call_ref: ref,
                 turn_ref: response.turn,
                 response_context: response.context,
                 tool_name: name,
                 arguments: arguments
               ) do
          response = %{response | had_tools?: true, tool_ids: MapSet.put(response.tool_ids, id)}

          {:ok,
           %{
             put_response(state, token, response)
             | tools: Map.put(state.tools, ref, %{id: id, token: token})
           }}
        end
    end
  end

  defp put_response(state, token, response),
    do: %{state | responses: Map.put(state.responses, token, response)}

  defp send_wire(state, message), do: state.wire_module.send_control(state.wire, message)
  defp token, do: "vxp_" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  defp stop(state), do: {:stop, {:shutdown, :session_failed}, state}

  defp stop_reply(state),
    do: {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}

  defp opening_instructions(:generated),
    do: {"Begin the conversation with a brief greeting based on your system instructions.", nil}

  defp opening_instructions({:fixed, text}),
    do: {"Speak exactly the following text, with no additions: " <> text, text}
end
