defmodule Vxpipe.CallEngine.SpeechTopologyMergedChannel do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.{
    SpeechTopologyAudio,
    SpeechTopologyEvent,
    SpeechTopologyInput,
    SpeechTopologyUsage
  }

  @credit_timeout 1_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: options[:name])

  @impl true
  def init(options) do
    {:ok,
     %{
       consumer: Keyword.fetch!(options, :consumer),
       observer: Keyword.fetch!(options, :observer),
       usage: Keyword.fetch!(options, :usage),
       input: Keyword.fetch!(options, :input),
       provider: Keyword.fetch!(options, :provider),
       format: nil,
       request: nil,
       prepared?: false,
       input_busy?: false,
       cancellation: nil,
       awaiting_event: nil,
       events: :queue.new(),
       pending_audio: nil,
       session_played_ms: 0
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

  def handle_call({:submit_audio, request, payload}, {caller, _tag}, state) do
    if caller == GenServer.whereis(state.provider) and open?(state, request) and
         state.request.submitted? and is_nil(state.request.awaiting) do
      audio = %SpeechTopologyAudio{ref: make_ref(), request_ref: request, payload: payload}
      timer = Process.send_after(self(), {:credit_expired, audio.ref}, @credit_timeout)

      request_state = %{
        state.request
        | awaiting: %{audio: audio, timer: timer},
          generated_bytes: state.request.generated_bytes + byte_size(payload)
      }

      state = %{state | request: request_state}
      {:reply, {:ok, audio.ref}, dispatch_audio(state)}
    else
      {:reply, {:error, :stale_request}, state}
    end
  end

  @impl true
  def handle_cast({:input_result, input, command, result}, state) do
    if input == GenServer.whereis(state.input),
      do: input_result(command, result, state),
      else: {:noreply, state}
  end

  @impl true
  def handle_info(
        {:credit_expired, reference},
        %{request: %{awaiting: %{audio: %{ref: reference}}}} = state
      ),
      do: {:stop, :normal, state}

  def handle_info({:credit_expired, _stale}, state), do: {:noreply, state}

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

  defp consumer_operation({:prepare, format}, _from, _deadline, state) do
    state = %{state | format: format}
    state = enqueue_event(state, nil, :ready, nil)
    {:reply, :ok, dispatch_event(state)}
  end

  defp consumer_operation({:speak, text, options}, _from, deadline, state) do
    cond do
      not state.prepared? ->
        {:reply, {:error, :not_ready}, state}

      state.request ->
        {:reply, {:error, :busy}, state}

      true ->
        request = make_ref()

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
          phase: :open,
          submitted?: false,
          submitted_acked?: false,
          terminal?: false,
          awaiting: nil,
          generated_bytes: 0,
          accepted_bytes: 0,
          uncredited_bytes: 0,
          played_ms: 0
        }

        {:reply, {:ok, request}, %{state | request: current, input_busy?: true}}
    end
  end

  defp consumer_operation({:fence, request}, _from, deadline, state) do
    if current?(state, request) and state.request.phase in [:open, :completed] do
      cancel_credit(state.request.awaiting)

      uncredited =
        if state.request.awaiting, do: byte_size(state.request.awaiting.audio.payload), else: 0

      ticket = %{
        request_ref: request,
        ref: make_ref(),
        consumer: state.consumer,
        deadline: deadline
      }

      timer = Process.send_after(self(), {:cancellation_expired, ticket.ref}, remaining(deadline))

      current = %{
        state.request
        | phase: :fenced,
          awaiting: nil,
          uncredited_bytes: uncredited
      }

      {:reply, {:ok, ticket},
       %{
         state
         | request: current,
           pending_audio: nil,
           cancellation: %{ticket: ticket, timer: timer}
       }}
    else
      {:reply, {:error, :stale_request}, state}
    end
  end

  defp consumer_operation({:cancel, ticket, played_ms}, from, _deadline, state) do
    cond do
      is_nil(state.cancellation) or state.cancellation.ticket != ticket ->
        {:reply, {:error, :stale_request}, state}

      ticket.consumer != state.consumer or not live?(ticket.deadline) ->
        {:reply, {:error, :command_timeout}, state}

      Map.has_key?(state.cancellation, :from) ->
        {:reply, {:error, :busy}, state}

      not is_integer(played_ms) or played_ms < 0 ->
        {:reply, {:error, :invalid_playback}, state}

      true ->
        maximum =
          div(
            (state.request.accepted_bytes + state.request.uncredited_bytes) * 1_000,
            state.format.sample_rate * 2
          )

        if played_ms < state.request.played_ms or played_ms > maximum do
          {:reply, {:error, :invalid_playback}, state}
        else
          total = state.session_played_ms + played_ms - state.request.played_ms

          report = %{
            request_ref: ticket.request_ref,
            played_ms: played_ms,
            session_played_ms: total
          }

          cancellation = Map.merge(state.cancellation, %{from: from, report: report})
          request = %{state.request | played_ms: played_ms}

          state = %{
            state
            | cancellation: cancellation,
              request: request,
              session_played_ms: total
          }

          if state.input_busy? do
            send(state.observer, {:topology_cancel_queued, ticket.request_ref})
            {:noreply, state}
          else
            {:noreply, dispatch_cancel(state)}
          end
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

  defp consumer_operation({:validate_audio, audio}, _from, _deadline, state),
    do: validate(audio, state)

  defp consumer_operation({:ack_audio, audio}, _from, _deadline, state),
    do: acknowledge(audio, state)

  defp consumer_operation(:sync, _from, _deadline, state), do: {:reply, :ok, state}

  defp consumer_operation(_operation, _from, _deadline, state),
    do: {:reply, {:error, :unsupported}, state}

  defp provider_event(request, :input_submitted, provider_request_id, state) do
    if open?(state, request) and not state.request.submitted? do
      with :ok <-
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
    if open?(state, request) and is_nil(state.request.awaiting) do
      current = %{state.request | phase: :completed, terminal?: true}
      state = %{state | request: current}
      {:reply, :ok, state |> enqueue_event(request, :completed, nil) |> dispatch_event()}
    else
      {:reply, {:error, :cancelled}, state}
    end
  end

  defp provider_event(request, :cancelled, provider_request_id, state) do
    if current?(state, request) and state.request.phase == :fenced do
      current = %{state.request | phase: :cancelled, terminal?: true}
      state = %{state | request: current}

      {:reply, :ok,
       state
       |> enqueue_event(request, :cancelled, provider_request_id)
       |> dispatch_event()
       |> settle_cancellation()}
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

  defp acknowledge(audio, state) do
    case state.request do
      %{ref: request, phase: :open, awaiting: %{audio: ^audio, timer: timer}} ->
        Process.cancel_timer(timer)
        provider = GenServer.whereis(state.provider)
        send(provider, {:topology_credit, self(), request, audio.ref, :ok})

        request_state = %{
          state.request
          | awaiting: nil,
            accepted_bytes: state.request.accepted_bytes + byte_size(audio.payload)
        }

        {:reply, :ok, %{state | request: request_state}}

      _other ->
        {:reply, {:error, :stale_audio}, state}
    end
  end

  defp validate(audio, state) do
    case state.request do
      %{phase: :open, awaiting: %{audio: ^audio}} -> {:reply, :ok, state}
      _other -> {:reply, {:error, :stale_audio}, state}
    end
  end

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
    if live?(cancellation.ticket.deadline) do
      Process.cancel_timer(cancellation.timer)
      GenServer.reply(cancellation.from, {:ok, cancellation.report})
      %{state | request: nil, cancellation: nil, pending_audio: nil}
    else
      GenServer.reply(cancellation.from, {:error, :command_timeout})
      send(self(), {:cancellation_expired, cancellation.ticket.ref})
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
           request: %{
             ref: request,
             submitted_acked?: true,
             phase: :open,
             awaiting: %{audio: audio}
           }
         } = state
       )
       when audio.request_ref == request do
    send(state.consumer, {:topology_audio, audio})
    state
  end

  defp dispatch_audio(state), do: state

  defp cancel_credit(nil), do: :ok
  defp cancel_credit(%{timer: timer}), do: Process.cancel_timer(timer)

  defp cancellation_pending?(%{cancellation: cancellation}),
    do: not is_nil(cancellation) and Map.has_key?(cancellation, :from)

  defp open?(%{request: %{ref: request, phase: :open}}, request), do: true
  defp open?(_state, _request), do: false

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

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
  defp live?(deadline), do: remaining(deadline) > 0
end
