defmodule Vxpipe.CallEngine.Speech.Channel do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.{
    Allocation,
    CapabilityTree,
    Cancellation,
    ChannelFailure,
    Event,
    EventDelivery,
    EventQueue,
    Input,
    OutputState,
    ProviderName,
    ResponseContexts,
    ResponseStarts,
    ScopeControl,
    STSInput,
    STSOutput,
    TTSFlow,
    TTSUsage
  }

  @credit_timeout 15_000
  @maximum_pending 32

  def start_link(allocation),
    do: GenServer.start_link(__MODULE__, allocation, name: address(allocation))

  def address(allocation), do: CapabilityTree.address({allocation.generation, :channel})
  def bind(channel), do: GenServer.call(channel, :bind, 5_000)

  def configure(allocation, module, descriptor, usage?, timeout),
    do:
      GenServer.call(
        address(allocation),
        {:configure, module, descriptor, usage?, timeout},
        5_000
      )

  def started(allocation, pid), do: GenServer.call(address(allocation), {:started, pid}, 5_000)

  @doc "Admit one provider PCM chunk and wait for its exact asynchronous credit."
  def submit(channel, request, audio),
    do: GenServer.call(channel, {:submit_audio, request, audio}, 5_000)

  def emit(channel, kind, fields) do
    with {:ok, event} <- Event.build(kind, fields),
         do: GenServer.call(channel, {:emit, event}, 5_000)
  end

  @impl true
  def init(allocation) do
    {:ok,
     %{
       allocation: allocation,
       scope_monitor: Process.monitor(allocation.scope.control),
       producer: nil,
       producer_monitor: nil,
       producer_down?: false,
       producer_drain_timer: nil,
       consumer: allocation.consumer,
       descriptor: nil,
       module: nil,
       call_timeout: 5_000,
       started?: false,
       ready?: false,
       active?: false,
       prepared?: false,
       events: EventQueue.new(),
       input: nil,
       response_contexts: ResponseContexts.new(),
       response_starts: ResponseStarts.new(),
       output: OutputState.new(),
       usage?: false,
       cancellation: nil,
       last_cancellation: nil,
       ready_acked?: false
     }}
  end

  @impl true
  def handle_call({:command, allocation, deadline, message}, from, state) do
    cond do
      allocation != state.allocation ->
        {:reply, {:error, :not_owner}, state}

      deadline <= System.monotonic_time(:millisecond) ->
        {:reply, {:error, :command_timeout}, state}

      true ->
        execute(message, from, deadline, state)
    end
  end

  def handle_call({:configure, module, descriptor, usage?, timeout}, _from, state) do
    {:reply, :ok,
     %{
       state
       | module: module,
         descriptor: descriptor,
         usage?: usage?,
         call_timeout: timeout
     }}
  end

  def handle_call(:bind, {producer, _tag}, %{producer: nil} = state) do
    if Allocation.valid?(state.allocation) and
         ProviderName.whereis_name(state.allocation) == producer do
      {:reply, :ok, %{state | producer: producer, producer_monitor: Process.monitor(producer)}}
    else
      {:reply, {:error, :closed}, state}
    end
  end

  def handle_call(:bind, _from, state), do: {:reply, {:error, :already_bound}, state}

  def handle_call({:started, producer}, _from, %{producer: producer} = state),
    do: {:reply, :ok, activate(%{state | started?: true})}

  def handle_call({:started, _producer}, _from, state), do: {:reply, {:error, :closed}, state}

  def handle_call(:metadata, {caller, _tag}, state) do
    cond do
      not Allocation.valid?(state.allocation) ->
        {:reply, {:error, :closed}, state}

      caller != state.consumer ->
        {:reply, {:error, :not_owner}, state}

      true ->
        {:reply,
         {:ok, Map.take(state, [:producer, :module, :descriptor, :call_timeout, :active?])},
         state}
    end
  end

  def handle_call({:submit_audio, reference, audio}, {producer, _tag}, state) do
    cond do
      not Allocation.valid?(state.allocation) ->
        {:reply, {:error, :closed}, state}

      producer != state.producer ->
        {:reply, {:error, :unbound_producer}, state}

      true ->
        case OutputState.prepare_audio(
               state.output,
               state.allocation,
               producer,
               reference,
               audio
             ) do
          {:ok, envelope} ->
            deadline = System.monotonic_time(:millisecond) + @credit_timeout
            timer = Process.send_after(self(), {:credit_expired, envelope.ref}, @credit_timeout)

            output =
              OutputState.await_audio(state.output, envelope, timer, deadline, state.usage?)

            state = %{state | output: output}
            {:reply, {:ok, envelope.ref}, dispatch_audio(state)}

          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call({:audio, deadline, operation, audio}, {caller, _tag}, state) do
    cond do
      caller != state.consumer ->
        {:reply, {:error, :not_owner}, state}

      deadline <= System.monotonic_time(:millisecond) ->
        {:reply, {:error, :command_timeout}, state}

      not Allocation.valid?(state.allocation) ->
        {:reply, {:error, :closed}, state}

      true ->
        case OutputState.audio_operation(
               state.output,
               operation,
               audio,
               System.monotonic_time(:millisecond)
             ) do
          {:ok, output} ->
            {:reply, :ok, %{state | output: output}}

          {:credit, awaiting, output} ->
            Process.cancel_timer(awaiting.timer)

            send(
              audio.producer,
              {:vxpipe_speech_credit, self(), audio.request_ref, audio.ref, :ok}
            )

            {:reply, :ok, %{state | output: output}}

          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call({:input, allocation, command, audio}, {caller, _tag} = from, state) do
    cond do
      allocation != state.allocation or caller != state.consumer ->
        {:reply, {:error, :not_owner}, state}

      not Allocation.valid?(allocation) ->
        {:reply, {:error, :closed}, state}

      state.producer_down? ->
        {:reply, {:error, :closed}, state}

      not state.active? ->
        {:reply, {:error, :not_ready}, state}

      not STSInput.supported?(state.descriptor, command) ->
        {:reply, {:error, :unsupported_operation}, state}

      command.deadline <= System.monotonic_time(:millisecond) ->
        {:reply, {:error, :command_timeout}, state}

      not is_nil(state.input) ->
        {:reply, {:error, :busy}, state}

      :atomics.compare_exchange(command.token, 1, 0, 1) != :ok ->
        {:reply, {:error, :command_timeout}, state}

      true ->
        case STSInput.stage_context(
               state.descriptor,
               state.module,
               command,
               state.response_contexts
             ) do
          {:ok, contexts} ->
            timer = Process.send_after(self(), {:input_expired, command.ref}, remaining(command))

            input = %{
              command: command,
              from: from,
              timer: timer,
              claimed?: false,
              unsafe_events?: false
            }

            Input.submit(allocation, command, audio)
            {:noreply, %{state | input: input, response_contexts: contexts}}

          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call({:claim_input, reference}, {worker, _tag}, state) do
    case state.input do
      %{command: %{ref: ^reference} = command, claimed?: false} = input ->
        if remaining(command) > 0 and Allocation.valid?(state.allocation) and
             worker == GenServer.whereis(Input.address(state.allocation)) do
          {:reply, {:ok, state.module, state.producer},
           %{state | input: %{input | claimed?: true}}}
        else
          {:reply, {:error, :closed}, state}
        end

      _input ->
        {:reply, {:error, :closed}, state}
    end
  end

  def handle_call({:speak, command, reference, text}, {caller, _tag}, state) do
    cond do
      caller != state.consumer ->
        {:reply, {:error, :not_owner}, state}

      not Allocation.valid?(state.allocation) ->
        {:reply, {:error, :closed}, state}

      not state.active? or not state.ready_acked? ->
        {:reply, {:error, :not_ready}, state}

      state.descriptor.kind != :tts ->
        {:reply, {:error, :unsupported_operation}, state}

      not is_nil(state.output.request) ->
        {:reply, {:error, :busy}, state}

      not EventQueue.idle?(state.events) ->
        {:reply, {:error, :busy}, state}

      not is_nil(state.input) ->
        {:reply, {:error, :busy}, state}

      remaining(command) == 0 or :atomics.compare_exchange(command.token, 1, 0, 1) != :ok ->
        {:reply, {:error, :command_timeout}, state}

      true ->
        with true <- remaining(command) > 0 and Allocation.valid?(state.allocation),
             {:ok, handle, output} <-
               OutputState.admit(
                 state.output,
                 state.allocation,
                 state.consumer,
                 state.descriptor,
                 reference,
                 text
               ) do
          command = Map.put(command, :operation, {:speak, reference})
          timer = Process.send_after(self(), {:input_expired, command.ref}, remaining(command))
          input = %{command: command, from: nil, timer: timer, claimed?: false}
          Input.submit(state.allocation, command, text)

          {:reply, {:ok, handle}, %{state | input: input, output: output}}
        else
          false -> ChannelFailure.fail(state, :command_timeout)
          error -> {:reply, error, state}
        end
    end
  end

  def handle_call({:fence_output, command, reference}, {caller, _tag}, state) do
    cond do
      caller != state.consumer ->
        {:reply, {:error, :not_owner}, state}

      not Allocation.valid?(state.allocation) ->
        {:reply, {:error, :closed}, state}

      is_nil(state.descriptor) or state.descriptor.kind != :tts ->
        {:reply, {:error, :unsupported_operation}, state}

      state.last_cancellation && state.last_cancellation.ticket.request_ref == reference ->
        {:reply, {:ok, state.last_cancellation.ticket}, state}

      state.cancellation && state.cancellation.ticket.request_ref == reference ->
        if remaining(state.cancellation.ticket) > 0,
          do: {:reply, {:ok, state.cancellation.ticket}, state},
          else: ChannelFailure.fail(state, :command_timeout)

      is_nil(state.output.request) or state.output.request.ref != reference ->
        {:reply, {:error, :stale_request}, state}

      remaining(command) == 0 or :atomics.compare_exchange(command.token, 1, 0, 1) != :ok ->
        {:reply, {:error, :command_timeout}, state}

      true ->
        case TTSFlow.fence(state, command, reference) do
          {:ok, ticket, state} -> {:reply, {:ok, ticket}, state}
          {:error, reason} -> ChannelFailure.fail(state, reason)
        end
    end
  end

  def handle_call({:settle_output, reference, played_ms}, {caller, _tag}, state) do
    TTSFlow.settle_completed(state, caller, reference, played_ms)
  end

  def handle_call({:admit_output, command, turn}, {caller, _tag}, state),
    do: STSOutput.admit(state, caller, command, turn)

  def handle_call({:reject_response, turn}, {caller, _tag}, state),
    do: STSOutput.reject(state, caller, turn)

  def handle_call({:settle_sts_output, handle, played}, {caller, _tag}, state),
    do: STSOutput.settle(state, caller, handle, played)

  def handle_call({:cancel, command, ticket, played_ms}, {caller, _tag} = from, state) do
    if Allocation.valid?(state.allocation) do
      case Cancellation.evaluate(
             command,
             ticket,
             played_ms,
             caller,
             state.consumer,
             state.allocation,
             state.cancellation,
             state.last_cancellation,
             System.monotonic_time(:millisecond)
           ) do
        {:reply, reply} ->
          {:reply, reply, state}

        {:fail, reason} ->
          ChannelFailure.fail(state, reason)

        {:continue, command} ->
          case TTSFlow.begin_cancel(state, command, played_ms, from) do
            :failed -> ChannelFailure.input_failed(state)
            result -> result
          end
      end
    else
      {:reply, {:error, :closed}, state}
    end
  end

  def handle_call({:emit, event}, {producer, _tag}, %{producer: producer} = state) do
    cond do
      not Allocation.valid?(state.allocation) ->
        {:reply, {:error, :closed}, state}

      not Event.supported?(event, state.descriptor) ->
        {:reply, {:error, :invalid_event}, state}

      is_nil(state.consumer) and event.kind != :ready ->
        {:reply, :discarded, state}

      EventQueue.full?(state.events, @maximum_pending) ->
        ChannelFailure.fail(state, :event_overflow)

      true ->
        case accept_event(event, state) do
          {:ok, event, state} ->
            publish_event(event, producer, EventDelivery.note_early_event(event, state))

          :failed ->
            ChannelFailure.fail(state, :session_failed)

          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call({:emit, _event}, _from, state), do: {:reply, {:error, :unbound_producer}, state}

  def handle_call({:ack, event}, {consumer, _tag}, %{consumer: consumer} = state) do
    if Allocation.valid?(state.allocation) do
      case EventQueue.acknowledge(state.events, event) do
        {:ok, events} ->
          case EventDelivery.acknowledge(event, %{state | events: events}) do
            {:ok, state} ->
              state = state |> dispatch() |> dispatch_audio()
              ChannelFailure.reply_after_ack(state)

            {:error, _reason} ->
              ChannelFailure.fail(state, :session_failed)
          end

        error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :closed}, state}
    end
  end

  def handle_call({:ack, _event}, _from, state), do: {:reply, {:error, :stale_event}, state}

  defp publish_event(event, producer, state) do
    {:reply, :ok, enqueue_event(state, event, producer)}
  end

  defp enqueue_event(state, event, producer) do
    delivered? =
      not EventDelivery.staged_context_input?(state) and
        EventDelivery.pre_deliver_terminal?(state.events, event)

    {event, events} =
      EventQueue.enqueue(state.events, event, state.allocation, producer, delivered?)

    if delivered?, do: send(state.consumer, {:vxpipe_speech, event})
    activate(%{state | events: events})
  end

  @impl true
  def handle_cast(:retire, state), do: {:stop, :normal, state}

  def handle_cast({:input_result, reference, worker, result}, state) do
    case state.input do
      %{command: %{ref: ^reference} = command, claimed?: true} = input ->
        cond do
          worker != GenServer.whereis(Input.address(state.allocation)) ->
            {:noreply, state}

          Allocation.valid?(state.allocation) and ChannelFailure.drainable_stt_failure?(state) and
              (remaining(command) == 0 or result == {:error, :session_failed}) ->
            {:noreply, ChannelFailure.begin_producer_failure_drain(state)}

          remaining(command) == 0 or not Allocation.valid?(state.allocation) or
              result == {:error, :session_failed} ->
            ChannelFailure.input_failed(state)

          true ->
            case finished_input(command, result, state) do
              {:ok, state, reply} ->
                settle_input_result(state, input, command, result, reply)

              :failed ->
                ChannelFailure.input_failed(state)
            end
        end

      _input ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:input_expired, reference}, %{input: %{command: %{ref: reference}}} = state) do
    if Allocation.valid?(state.allocation) and ChannelFailure.drainable_stt_failure?(state),
      do: {:noreply, ChannelFailure.begin_producer_failure_drain(state)},
      else: ChannelFailure.input_failed(state)
  end

  def handle_info({:input_expired, _reference}, state), do: {:noreply, state}

  def handle_info(
        {:credit_expired, reference},
        %{output: %OutputState{request: %{awaiting: %{audio: %{ref: reference}}}}} = state
      ) do
    ChannelFailure.retire(state.allocation)
    ScopeControl.failed(state.allocation, :audio_output_failed)
    {:stop, :normal, state}
  end

  def handle_info({:credit_expired, _reference}, state), do: {:noreply, state}

  def handle_info(
        {:cancellation_expired, reference},
        %{cancellation: %{ticket: %{ref: reference}}} = state
      ) do
    ChannelFailure.reply_pending_cancel(state.cancellation, {:error, :session_failed})
    ChannelFailure.retire(state.allocation)
    ScopeControl.failed(state.allocation, :command_timeout)
    {:stop, :normal, state}
  end

  def handle_info({:cancellation_expired, _reference}, state), do: {:noreply, state}

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state)
      when monitor == state.scope_monitor do
    ChannelFailure.retire(state.allocation)
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state)
      when monitor == state.producer_monitor do
    state = %{state | producer: nil, producer_monitor: nil, producer_down?: true}

    if ChannelFailure.drainable_stt_failure?(state) do
      {:noreply, ChannelFailure.begin_producer_failure_drain(state)}
    else
      ChannelFailure.retire(state.allocation)
      {:stop, :normal, state}
    end
  end

  def handle_info(
        {:producer_drain_expired, generation},
        %{allocation: %{generation: generation}, producer_down?: true} = state
      ) do
    ChannelFailure.finish_producer_failure_drain(state)
    {:stop, :normal, state}
  end

  def handle_info({:producer_drain_expired, _generation}, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :speech_channel)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp execute({:adopt, consumer, command}, {caller, _tag}, _deadline, state) do
    if caller == state.allocation.lease and state.prepared? and
         is_pid(consumer) and Process.alive?(consumer) and Allocation.pending?(state.allocation) and
         Allocation.valid?(state.allocation) do
      case ScopeControl.activate(state.allocation, caller, consumer, command) do
        :ok ->
          if remaining(command) > 0 and Allocation.valid?(state.allocation) do
            {:reply, :ok,
             dispatch(%{state | consumer: consumer, prepared?: false, active?: true})}
          else
            ChannelFailure.fail(state, :command_timeout)
          end

        {:error, :command_timeout} = error ->
          if :atomics.compare_exchange(command.token, 1, 0, 2) == 1,
            do: ChannelFailure.fail(state, :command_timeout),
            else: {:reply, error, state}

        error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :not_adoptable}, state}
    end
  end

  defp execute(message, from, _deadline, state), do: handle_call(message, from, state)

  defp activate(
         %{
           started?: true,
           events: %EventQueue{ready?: true},
           active?: false,
           consumer: nil,
           prepared?: false
         } = state
       ) do
    if Allocation.valid?(state.allocation) do
      send(state.allocation.lease, {:vxpipe_speech_prepared, state.allocation, state.descriptor})
      %{state | prepared?: true}
    else
      state
    end
  end

  defp activate(
         %{
           started?: true,
           events: %EventQueue{ready?: true},
           active?: false,
           consumer: consumer
         } = state
       )
       when is_pid(consumer) do
    authority = state.allocation.lease || state.allocation.consumer

    command = %{deadline: state.allocation.deadline, token: :atomics.new(1, [])}
    result = ScopeControl.activate(state.allocation, authority, consumer, command)

    if result == :ok and remaining(command) > 0 and Allocation.valid?(state.allocation) do
      dispatch(%{state | active?: true})
    else
      :atomics.compare_exchange(command.token, 1, 0, 2)
      ChannelFailure.retire(state.allocation)
      ScopeControl.failed(state.allocation, :startup_timeout)
      GenServer.cast(self(), :retire)
      state
    end
  end

  defp activate(state), do: dispatch(state)

  defp dispatch(state), do: EventDelivery.dispatch(state)

  defp settle_input_result(state, input, command, result, reply) do
    if remaining(command) > 0 and Allocation.valid?(state.allocation) and
         not EventDelivery.rejected_with_early_events?(state, input, result) do
      Process.cancel_timer(input.timer)
      contexts = STSInput.finish_context(state.response_contexts, command, result)
      state = %{state | response_contexts: contexts, input: nil}
      ChannelFailure.reply_input(input, reply)
      TTSFlow.continue_after_input(command, result, dispatch(state))
    else
      ChannelFailure.input_failed(state)
    end
  end

  defp accept_event(
         %Event{kind: :cancelled, request_ref: reference} = event,
         %{
           output: %OutputState{
             request: %{ref: reference, fenced?: true, terminal?: false}
           },
           cancellation: cancellation
         } = state
       )
       when not is_nil(cancellation) do
    if remaining(cancellation.ticket) > 0 and Allocation.valid?(state.allocation) do
      case OutputState.mark_terminal(state.output, event) do
        {:ok, output} ->
          state = %{state | output: output}
          event = attach_usage(event, state)

          case TTSFlow.settle(state) do
            {:ok, state} -> {:ok, event, state}
            :failed -> :failed
          end

        _error ->
          :failed
      end
    else
      :failed
    end
  end

  defp accept_event(%Event{kind: :input_submitted} = event, %{descriptor: %{kind: :sts}} = state),
    do: STSInput.accept_submission(event, state)

  defp accept_event(%Event{kind: :response_started} = event, state),
    do: EventDelivery.accept_response_start(event, state)

  defp accept_event(
         %Event{kind: :tool_call} = event,
         %{descriptor: %{response_start?: true}} = state
       ),
       do: EventDelivery.accept_tool_call(event, state)

  defp accept_event(%Event{kind: :output_completed} = event, state),
    do: STSOutput.complete(event, state)

  defp accept_event(
         %Event{kind: kind, request_ref: reference} = event,
         %{output: %OutputState{request: %{ref: reference, terminal?: false}}} = state
       )
       when kind in [:input_submitted, :completed] do
    result =
      if kind == :input_submitted,
        do: OutputState.mark_submitted(state.output, event),
        else: OutputState.complete(state.output, event)

    case result do
      {:ok, output} ->
        state = %{state | output: output}
        {:ok, attach_usage(event, state), state}

      error ->
        error
    end
  end

  defp accept_event(%Event{kind: kind}, _state)
       when kind in [:input_submitted, :completed, :cancelled],
       do: {:error, :stale_request}

  defp accept_event(event, state), do: {:ok, event, state}

  defp dispatch_audio(
         %{
           active?: true,
           ready_acked?: true,
           output: %OutputState{
             request: %{
               ref: reference,
               terminal?: false,
               fenced?: false
             },
             pending_audio: %{request_ref: reference} = audio
           }
         } = state
       ) do
    if Allocation.valid?(state.allocation) do
      send(state.consumer, {:vxpipe_speech_audio, audio})
      {_audio, output} = OutputState.take_pending(state.output)
      %{state | output: output}
    else
      state
    end
  end

  defp dispatch_audio(state), do: state

  defp finished_input(%{operation: {:cancel, _reference}}, :ok, state) do
    TTSFlow.finish_cancel(state)
  end

  defp finished_input(
         %{operation: {:speak, reference}} = command,
         {:error, reason} = result,
         state
       ) do
    case TTSFlow.reject(command, result, state) do
      {:ok, state} ->
        if remaining(command) > 0 and Allocation.valid?(state.allocation) and
             not EventQueue.full?(state.events, @maximum_pending) do
          {:ok, event} = Event.build(:failed, request_ref: reference, reason: reason)
          {:ok, enqueue_event(state, event, state.producer), result}
        else
          :failed
        end

      :failed ->
        :failed
    end
  end

  defp finished_input(command, result, state) do
    case TTSFlow.reject(command, result, state) do
      {:ok, state} -> {:ok, state, result}
      :failed -> :failed
    end
  end

  defp attach_usage(event, %{usage?: true, allocation: allocation, output: output}),
    do: %{event | usage: TTSUsage.snapshot(allocation, output.request)}

  defp attach_usage(event, _state), do: event

  defp remaining(command),
    do: max(command.deadline - System.monotonic_time(:millisecond), 0)
end
