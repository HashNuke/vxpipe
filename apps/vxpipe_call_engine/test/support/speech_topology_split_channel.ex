defmodule Vxpipe.CallEngine.SpeechTopologySplitChannel do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.{
    SpeechTopologyEvent,
    SpeechTopologyInput,
    SpeechTopologyUsage
  }

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: options[:name])

  @impl true
  def init(options) do
    {:ok,
     %{
       consumer: Keyword.fetch!(options, :consumer),
       observer: Keyword.fetch!(options, :observer),
       usage: Keyword.fetch!(options, :usage),
       input: Keyword.fetch!(options, :input),
       output: Keyword.fetch!(options, :output),
       provider: Keyword.fetch!(options, :provider),
       request: nil,
       prepared?: false,
       input_busy?: false,
       cancellation: nil,
       awaiting_event: nil,
       events: :queue.new(),
       pending_audio: nil
     }}
  end

  @impl true
  def handle_call({:consumer, deadline, operation}, {caller, _tag} = from, state) do
    cond do
      caller != state.consumer -> {:reply, {:error, :not_owner}, state}
      not live?(deadline) -> {:reply, {:error, :command_timeout}, state}
      true -> consumer_operation(operation, from, deadline, state)
    end
  end

  def handle_call(
        {:provider_event, request, kind, provider_request_id},
        {caller, _tag},
        state
      ) do
    if caller == GenServer.whereis(state.provider) do
      provider_event(request, kind, provider_request_id, state)
    else
      {:reply, {:error, :not_owner}, state}
    end
  end

  @impl true
  def handle_cast({:output_audio, output, audio}, state) do
    if output == GenServer.whereis(state.output) and current?(state, audio.request_ref) and
         not state.request.fenced? do
      {:noreply, dispatch_audio(%{state | pending_audio: audio})}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:input_result, input, command, result}, state) do
    if input == GenServer.whereis(state.input),
      do: input_result(command, result, state),
      else: {:noreply, state}
  end

  @impl true
  def handle_info(
        {:cancellation_expired, reference},
        %{cancellation: %{ticket: %{ref: reference}} = cancellation} = state
      ) do
    case Map.fetch(cancellation, :from) do
      {:ok, from} -> GenServer.reply(from, {:error, :command_timeout})
      :error -> :ok
    end

    {:stop, :normal, state}
  end

  def handle_info({:cancellation_expired, _stale}, state), do: {:noreply, state}

  defp consumer_operation({:prepare, format}, _from, deadline, state) do
    with :ok <- output(state, {:configure, format}, deadline) do
      state = enqueue_event(state, nil, :ready, nil)
      {:reply, :ok, dispatch_event(state)}
    end
  end

  defp consumer_operation({:speak, text, options}, _from, deadline, state) do
    cond do
      not state.prepared? ->
        {:reply, {:error, :not_ready}, state}

      state.request ->
        {:reply, {:error, :busy}, state}

      true ->
        request = make_ref()

        with :ok <- output(state, {:begin, request}, deadline) do
          command = %{
            kind: :speak,
            request: request,
            text: text,
            hold_result?: Keyword.get(options, :hold_result?, false),
            deadline: deadline
          }

          SpeechTopologyInput.submit(state.input, command)

          current = %{
            ref: request,
            input_characters: String.length(text),
            provider_request_id: nil,
            submitted?: false,
            submitted_acked?: false,
            terminal?: false,
            fenced?: false
          }

          {:reply, {:ok, request}, %{state | request: current, input_busy?: true}}
        end
    end
  end

  defp consumer_operation({:fence, request}, _from, deadline, state) do
    if current?(state, request) and not state.request.fenced? do
      with :ok <- output(state, {:fence, request}, deadline) do
        ticket = %{
          request_ref: request,
          ref: make_ref(),
          consumer: state.consumer,
          deadline: deadline
        }

        timer =
          Process.send_after(self(), {:cancellation_expired, ticket.ref}, remaining(deadline))

        current = %{state.request | fenced?: true}

        {:reply, {:ok, ticket},
         %{
           state
           | request: current,
             pending_audio: nil,
             cancellation: %{ticket: ticket, timer: timer}
         }}
      end
    else
      {:reply, {:error, :stale_request}, state}
    end
  end

  defp consumer_operation({:cancel, ticket, played_ms}, from, deadline, state) do
    cond do
      is_nil(state.cancellation) or state.cancellation.ticket != ticket ->
        {:reply, {:error, :stale_request}, state}

      ticket.consumer != state.consumer or not live?(ticket.deadline) ->
        {:reply, {:error, :command_timeout}, state}

      Map.has_key?(state.cancellation, :from) ->
        {:reply, {:error, :busy}, state}

      true ->
        deadline = min(deadline, ticket.deadline)

        case output(state, {:played, ticket.request_ref, played_ms}, deadline) do
          {:ok, report} ->
            cancellation = Map.merge(state.cancellation, %{from: from, report: report})
            state = %{state | cancellation: cancellation}

            if state.input_busy? do
              send(state.observer, {:topology_cancel_queued, ticket.request_ref})
              {:noreply, state}
            else
              {:noreply, dispatch_cancel(state)}
            end

          error ->
            {:reply, error, state}
        end
    end
  end

  defp consumer_operation({:ack_event, event}, _from, _deadline, %{awaiting_event: event} = state) do
    state =
      case event.kind do
        :ready -> %{state | prepared?: true}
        :input_submitted -> %{state | request: %{state.request | submitted_acked?: true}}
        _terminal -> state
      end

    {:reply, :ok, state |> Map.put(:awaiting_event, nil) |> dispatch_event() |> dispatch_audio()}
  end

  defp consumer_operation({:ack_event, _event}, _from, _deadline, state),
    do: {:reply, {:error, :stale_event}, state}

  defp consumer_operation(:sync, _from, _deadline, state), do: {:reply, :ok, state}

  defp consumer_operation(_operation, _from, _deadline, state),
    do: {:reply, {:error, :unsupported}, state}

  defp provider_event(request, :input_submitted, provider_request_id, state) do
    if current?(state, request) and not state.request.submitted? do
      with :ok <- output(state, {:submitted, request}, deadline()),
           :ok <-
             SpeechTopologyUsage.publish(
               state.usage,
               usage_fact(state.request, provider_request_id)
             ) do
        current = %{
          state.request
          | submitted?: true,
            provider_request_id: provider_request_id
        }

        state = %{state | request: current}

        {:reply, :ok,
         state
         |> enqueue_event(request, :input_submitted, provider_request_id)
         |> dispatch_event()}
      end
    else
      {:reply, {:error, :stale_request}, state}
    end
  end

  defp provider_event(request, :completed, _provider_request_id, state) do
    if current?(state, request) and not state.request.fenced? do
      with :ok <- output(state, {:completed, request}, deadline()) do
        state = %{state | request: %{state.request | terminal?: true}}
        {:reply, :ok, state |> enqueue_event(request, :completed, nil) |> dispatch_event()}
      end
    else
      {:reply, {:error, :cancelled}, state}
    end
  end

  defp provider_event(request, :cancelled, provider_request_id, state) do
    if current?(state, request) and state.request.fenced? do
      with :ok <- output(state, {:cancelled, request}, state.cancellation.ticket.deadline) do
        state = %{state | request: %{state.request | terminal?: true}}

        {:reply, :ok,
         state
         |> enqueue_event(request, :cancelled, provider_request_id)
         |> dispatch_event()
         |> settle_cancellation()}
      end
    else
      {:reply, {:error, :stale_request}, state}
    end
  end

  defp input_result(%{kind: :speak, request: request}, :ok, state) do
    if current?(state, request) do
      state = %{state | input_busy?: false}
      {:noreply, if(cancellation_pending?(state), do: dispatch_cancel(state), else: state)}
    else
      {:noreply, state}
    end
  end

  defp input_result(%{kind: :cancel, request: request}, :ok, state) do
    if current?(state, request) and state.cancellation do
      state = %{
        state
        | input_busy?: false,
          cancellation: Map.put(state.cancellation, :accepted?, true)
      }

      {:noreply, settle_cancellation(state)}
    else
      {:noreply, state}
    end
  end

  defp input_result(_command, _error, state), do: {:stop, :normal, state}

  defp dispatch_cancel(state) do
    ticket = state.cancellation.ticket

    command = %{
      kind: :cancel,
      request: ticket.request_ref,
      played_ms: state.cancellation.report.played_ms,
      deadline: ticket.deadline
    }

    SpeechTopologyInput.submit(state.input, command)
    %{state | input_busy?: true}
  end

  defp settle_cancellation(
         %{cancellation: %{accepted?: true} = cancellation, request: %{terminal?: true}} = state
       ) do
    if output(state, {:settle, cancellation.ticket.request_ref}, cancellation.ticket.deadline) ==
         :ok do
      Process.cancel_timer(cancellation.timer)
      GenServer.reply(cancellation.from, {:ok, cancellation.report})
      %{state | request: nil, cancellation: nil, pending_audio: nil}
    else
      state
    end
  end

  defp settle_cancellation(state), do: state

  defp enqueue_event(state, request, kind, provider_request_id) do
    event = %SpeechTopologyEvent{
      ref: make_ref(),
      kind: kind,
      request_ref: request,
      provider_request_id: provider_request_id
    }

    %{state | events: :queue.in(event, state.events)}
  end

  defp dispatch_event(%{awaiting_event: nil} = state) do
    case :queue.out(state.events) do
      {{:value, event}, events} ->
        send(state.consumer, {:topology_event, event})
        %{state | events: events, awaiting_event: event}

      {:empty, _events} ->
        state
    end
  end

  defp dispatch_event(state), do: state

  defp dispatch_audio(
         %{
           pending_audio: %{request_ref: request} = audio,
           request: %{ref: request, submitted_acked?: true, fenced?: false}
         } = state
       ) do
    send(state.consumer, {:topology_audio, audio})
    %{state | pending_audio: nil}
  end

  defp dispatch_audio(state), do: state

  defp cancellation_pending?(%{cancellation: cancellation}),
    do: not is_nil(cancellation) and Map.has_key?(cancellation, :from)

  defp output(state, operation, deadline),
    do: GenServer.call(state.output, {:control, deadline, operation}, remaining(deadline))

  defp current?(%{request: %{ref: request}}, request), do: true
  defp current?(_state, _request), do: false

  defp usage_fact(request, provider_request_id) do
    %{
      request_ref: request.ref,
      input_characters: request.input_characters,
      provider_request_id: provider_request_id,
      provenance: :locally_measured
    }
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 1_000
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
  defp live?(deadline), do: remaining(deadline) > 0
end
