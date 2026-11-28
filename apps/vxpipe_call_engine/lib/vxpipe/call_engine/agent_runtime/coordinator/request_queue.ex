defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.RequestQueue do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.CompletionContinuation

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{
    ActiveRequest,
    HeldOutput,
    IdlePause,
    LiteralOutput,
    State,
    UsageRounds
  }

  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Tool.ConversationAdmission

  defp start_request(%SendText{} = command, %State{} = state) do
    if state.reply_protocol == :mode_message_v1 do
      :ok =
        Vxpipe.CallEngine.Tool.InvocationRegistry.update_source(
          state.invocation_registry,
          command.participant_id,
          command.connection_id,
          :resume
        )
    end

    case ActiveRequest.start_caller(command, State.request_options(state)) do
      {:ok, current} -> {:ok, put_current(state, current)}
      {:error, :unavailable} = error -> error
    end
  end

  def start_next(
        %State{
          current: nil,
          held_output: nil,
          awaiting_output: nil,
          pending_literal: %{timer: _}
        } = state
      ) do
    case LiteralOutput.resume_hold(state) do
      %State{pending_literal: nil} = expired -> start_next(expired)
      checking -> checking
    end
  end

  def start_next(%State{pending_literal: literal} = state) when not is_nil(literal), do: state

  def start_next(
        %State{
          reply_protocol: :mode_message_v1,
          awaiting_output: pending,
          current: nil,
          held_output: nil
        } = state
      )
      when not is_nil(pending) do
    # One inference at a time, overlapping playback: while exactly one
    # predecessor output is outstanding, a leased completion may start. Caller,
    # idle and greeting work wait, as does a second overlapping completion.
    # The overlapping request's output is held until the predecessor settles.
    case start_completion(state) do
      {:ok, state} -> HeldOutput.start(state, pending)
      {:held, state} -> state
      {:empty, state} -> state
      {:error, :unavailable} -> exit(:completion_lease_unavailable)
    end
  end

  def start_next(%State{awaiting_output: pending} = state) when not is_nil(pending), do: state
  def start_next(%State{current: current} = state) when not is_nil(current), do: state

  def start_next(%State{} = state) do
    case start_completion(state) do
      {:ok, state} -> state
      {:held, state} -> state
      {:empty, state} -> start_after_completions(state)
      {:error, :unavailable} -> exit(:completion_lease_unavailable)
    end
  end

  defp start_after_completions(state) do
    case IdlePause.take_timeout(state) do
      {:waiting, state} ->
        state

      {:open, state} ->
        start_next_caller(state)

      {:ready, command, state} ->
        case ActiveRequest.start_caller_idle(command, State.request_options(state)) do
          {:ok, current} ->
            put_current(state, current)

          {:error, :unavailable} ->
            send(state.owner, {:vxpipe_capability_failed, self(), command, :provider_unavailable})
            state
        end
    end
  end

  defp start_next_caller(%State{} = state) do
    case :queue.out(state.pending) do
      {{:value, command}, pending} ->
        state = %{state | pending: pending}

        case admit(command, state) do
          {:ok, state} ->
            state

          {:held, state} ->
            start_next(state)

          {:error, :unavailable} ->
            send(state.owner, {:vxpipe_capability_failed, self(), command, :provider_unavailable})
            start_next(state)
        end

      {:empty, _pending} ->
        state
    end
  end

  def start_completion(state) do
    case CompletionContinuation.lease_next(
           state.invocation_registry,
           state.completion_consumer_id
         ) do
      {:ok, continuation} ->
        cond do
          IdlePause.retain?(state, continuation) ->
            with {:ok, state} <- IdlePause.retain(state, continuation),
                 do: start_completion(state)

          continuation.lease.source_retired? ->
            with :ok <-
                   CompletionContinuation.retain(
                     continuation,
                     state.session,
                     state.invocation_registry
                   ),
                 do: start_completion(state)

          true ->
            start_completion_request(continuation, state)
        end

      {:error, :empty} ->
        {:empty, state}

      {:error, :held} ->
        {:held, state}

      {:error, :unavailable} = error ->
        error
    end
  end

  defp start_completion_request(continuation, state) do
    case ActiveRequest.start_completion(continuation, State.request_options(state)) do
      {:ok, current} -> {:ok, put_current(state, current)}
      {:error, :unavailable} -> release_unstarted_completion(continuation, state)
    end
  end

  defp release_unstarted_completion(continuation, state) do
    _ = CompletionContinuation.release(state.invocation_registry, continuation)
    {:error, :unavailable}
  end

  def admit(command, state) do
    case ConversationAdmission.decide(state.invocation_registry) do
      :admit ->
        start_request(command, state)

      :hold ->
        {:ok, state} =
          LiteralOutput.start(state, command, ConversationAdmission.holding_response(), :hold)

        {:held, state}

      {:error, :unavailable} ->
        {:error, :unavailable}
    end
  end

  def enqueue(command, state) do
    if :queue.len(state.pending) < state.maximum_pending_requests do
      {:reply, :ok, %{state | pending: :queue.in(command, state.pending)}}
    else
      {:reply, {:error, :queue_full}, state}
    end
  end

  def put_current(state, current) do
    %{state | current: current, usage_rounds: UsageRounds.register(state.usage_rounds, current)}
  end
end
