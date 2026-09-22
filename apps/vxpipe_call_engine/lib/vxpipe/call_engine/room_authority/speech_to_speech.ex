defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech do
  @moduledoc """
  Room-side owner of one agent-owned speech-to-speech allocation.

  The provider-facing `Capability.SpeechToSpeech` never publishes to the room.
  It forwards policy-checked evidence as `vxpipe_sts_*` owner messages; this
  module is the only room path that turns that evidence into public
  `EventPublisher`/`TranscriptRouter` publications. Every publication reuses the
  existing transcript archive projection so STS history, usage and inspection
  stay on the established contracts.
  """

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech, as: Capability

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnInterrupted,
    ParticipantTranscription,
    TextOutput
  }

  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.{Evidence, Tools}

  import Evidence,
    only: [
      human_connection: 2,
      agent_connection: 1,
      turn_key: 1,
      agent_participant: 1,
      agent_fields: 3
    ]

  alias Vxpipe.CallEngine.{Error, Id, RoomCapabilitySupervisor, SpeechToSpeechRuntime}
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Snapshot}
  alias Vxpipe.CallEngine.RoomAuthority.{EventPublisher, State}
  alias Vxpipe.CallEngine.Usage.ProviderContext

  @spec bind_capability(State.t(), pid(), String.t(), String.t() | nil) :: State.t()
  def bind_capability(%State{} = state, capability, agent_id, activation_id \\ nil)
      when is_pid(capability) and is_binary(agent_id) do
    if state.speech_to_speech_monitor,
      do: Process.demonitor(state.speech_to_speech_monitor, [:flush])

    %{
      state
      | speech_to_speech_capability: %{
          pid: capability,
          participant_id: agent_id,
          activation_id: activation_id,
          monitor: nil
        },
        speech_to_speech_monitor: nil,
        speech_to_speech_ready?: false
    }
  end

  @spec ready?(State.t()) :: boolean()
  def ready?(%State{speech_to_speech_capability: nil}), do: false
  def ready?(%State{speech_to_speech_ready?: ready?}), do: ready?

  defdelegate current?(state, candidate), to: Evidence

  @spec handle_ready(State.t(), pid()) :: State.t()
  def handle_ready(%State{} = state, capability) do
    if current?(state, capability) do
      monitor = Process.monitor(capability)
      %{state | speech_to_speech_monitor: monitor, speech_to_speech_ready?: true}
    else
      state
    end
  end

  @type turn_ref :: String.t() | reference()

  @spec handle_input_transcript(State.t(), pid(), String.t(), String.t(), turn_ref(), boolean()) ::
          State.t()
  def handle_input_transcript(
        %State{} = state,
        capability,
        human_id,
        text,
        provider_turn,
        final? \\ true
      )
      when is_binary(human_id) and is_binary(text) and
             (is_binary(provider_turn) or is_reference(provider_turn)) and is_boolean(final?) do
    if current?(state, capability) do
      case human_connection(state, human_id) do
        {connection_id, connection} ->
          turn_key = turn_key(provider_turn)

          event = %ParticipantTranscription{
            id: Id.generate(:event),
            sequence: state.next_sequence,
            tenant_id: state.snapshot.tenant_id,
            room_id: state.snapshot.room_id,
            incarnation_id: state.snapshot.incarnation_id,
            participant_id: human_id,
            connection_id: connection_id,
            command_id: Id.generate(:command),
            correlation_id: turn_key,
            text: text,
            final: final?,
            provider_turn_index: 0,
            occurred_at: DateTime.utc_now(:millisecond)
          }

          {state, _policy} =
            EventPublisher.publish_transcript(state, connection.pid, event,
              media_policy_revision: state.speech_to_speech_policy_revision
            )

          state = %{state | next_sequence: state.next_sequence + 1}

          if final? do
            %{
              state
              | spoken_history:
                  Vxpipe.CallEngine.RoomAuthority.SpokenHistory.confirm_user(
                    state.spoken_history,
                    text
                  )
            }
          else
            state
          end

        nil ->
          state
      end
    else
      state
    end
  end

  @spec handle_turn_started(State.t(), pid(), String.t(), turn_ref()) :: State.t()
  def handle_turn_started(%State{} = state, capability, agent_id, provider_turn)
      when is_binary(agent_id) and (is_binary(provider_turn) or is_reference(provider_turn)) do
    if current?(state, capability) do
      case agent_connection(state) do
        {connection_id, connection} ->
          turn_key = turn_key(provider_turn)

          turn = %{
            agent_id: agent_id,
            provider_turn: turn_key,
            connection_id: connection_id,
            command_id: Id.generate(:command),
            correlation_id: turn_key
          }

          state = %{state | sts_turns: Map.put(state.sts_turns, turn_key, turn)}

          event = struct!(AgentSpeechStarted, agent_fields(state, connection, turn))

          state = EventPublisher.publish(state, connection.pid, event)
          %{state | next_sequence: state.next_sequence + 1}

        nil ->
          state
      end
    else
      state
    end
  end

  @spec handle_agent_transcript(
          State.t(),
          pid(),
          String.t(),
          String.t(),
          turn_ref(),
          non_neg_integer()
        ) :: State.t()
  def handle_agent_transcript(
        %State{} = state,
        capability,
        agent_id,
        text,
        provider_turn,
        played_ms
      )
      when is_binary(agent_id) and is_binary(text) and
             (is_binary(provider_turn) or is_reference(provider_turn)) and
             is_integer(played_ms) do
    if current?(state, capability) do
      case Map.fetch(state.sts_turns, turn_key(provider_turn)) do
        {:ok, turn} ->
          connection = Map.fetch!(state.connections, turn.connection_id)

          event = %TextOutput{
            id: Id.generate(:event),
            sequence: state.next_sequence,
            tenant_id: state.snapshot.tenant_id,
            room_id: state.snapshot.room_id,
            incarnation_id: state.snapshot.incarnation_id,
            participant_id: agent_id,
            source_participant_id: agent_id,
            connection_id: turn.connection_id,
            command_id: turn.command_id,
            correlation_id: turn.correlation_id,
            text: text,
            aggregated_by: :sentence,
            will_be_spoken: true,
            occurred_at: DateTime.utc_now(:millisecond)
          }

          {state, _policy} =
            EventPublisher.publish_transcript(state, connection.pid, event,
              media_policy_revision: state.speech_to_speech_policy_revision
            )

          %{state | next_sequence: state.next_sequence + 1}

        :error ->
          state
      end
    else
      state
    end
  end

  @spec handle_turn_completed(State.t(), pid(), String.t(), turn_ref()) :: State.t()
  def handle_turn_completed(%State{} = state, capability, agent_id, provider_turn)
      when is_binary(agent_id) and (is_binary(provider_turn) or is_reference(provider_turn)) do
    if current?(state, capability) do
      case Map.pop(state.sts_turns, turn_key(provider_turn)) do
        {nil, _turns} ->
          state

        {turn, turns} ->
          connection = Map.fetch!(state.connections, turn.connection_id)
          event = struct!(AgentTurnCompleted, agent_fields(state, connection, turn))
          state = EventPublisher.publish(state, connection.pid, event)
          %{state | next_sequence: state.next_sequence + 1, sts_turns: turns}
      end
    else
      state
    end
  end

  @spec handle_interrupted(State.t(), pid(), String.t(), String.t(), non_neg_integer(), term()) ::
          State.t()
  def handle_interrupted(
        %State{} = state,
        capability,
        agent_id,
        provider_turn,
        played_ms,
        _prefix
      )
      when is_binary(agent_id) and (is_binary(provider_turn) or is_reference(provider_turn)) and
             is_integer(played_ms) do
    if current?(state, capability) do
      case Map.pop(state.sts_turns, turn_key(provider_turn)) do
        {nil, _turns} ->
          state

        {turn, turns} ->
          connection = Map.fetch!(state.connections, turn.connection_id)

          event =
            struct!(
              AgentTurnInterrupted,
              Map.merge(agent_fields(state, connection, turn), %{
                interrupted_by_participant_id: turn.agent_id,
                interrupted_by_connection_id: turn.connection_id,
                interruption_command_id: turn.command_id,
                interruption_correlation_id: turn.correlation_id,
                played_ms: played_ms
              })
            )

          _ = agent_id
          state = EventPublisher.publish(state, connection.pid, event)
          %{state | next_sequence: state.next_sequence + 1, sts_turns: turns}
      end
    else
      state
    end
  end

  defdelegate handle_tool_call(
                state,
                capability,
                agent_id,
                call_ref,
                provider_turn,
                name,
                arguments
              ),
              to: Tools

  defdelegate deliver_tool_result(state, capability, call_ref, result), to: Tools
  defdelegate handle_tool_executed(state, capability, call_ref, outcome), to: Tools
  defdelegate handle_tool_timeout(state, capability, call_ref), to: Tools
  defdelegate handle_tool_cancelled(state, capability, agent_id, call_ref), to: Tools

  @spec handle_unavailable(State.t(), pid(), term()) :: State.t()
  def handle_unavailable(%State{} = state, capability, _reason) do
    if current?(state, capability) do
      %{state | speech_to_speech_capability: nil, speech_to_speech_ready?: false, sts_turns: %{}}
    else
      state
    end
  end

  @doc """
  Handles provider-driven speech onset (barge-in) through the room boundary.

  The capability has already fenced local playback and will follow with a
  `vxpipe_sts_interrupted` owner message that performs the public
  publication. This notification cannot interrupt again: by the time the room
  handles it, the capability may have admitted the reply to that new input.
  Only the generation-qualified interruption evidence publishes an outcome.
  """
  @spec handle_speech_started(State.t(), pid(), String.t(), turn_ref()) :: State.t()
  def handle_speech_started(%State{} = state, capability, _agent_id, _provider_turn)
      when is_pid(capability),
      do: state

  @spec offer_audio(State.t(), String.t(), binary()) :: :ok | {:error, term()}
  def offer_audio(%State{} = state, connection_id, pcm)
      when is_binary(connection_id) and is_binary(pcm) do
    with %{pid: capability} <- state.speech_to_speech_capability,
         connection when not is_nil(connection) <- Map.get(state.connections, connection_id),
         false <- MapSet.member?(state.held_participant_ids, connection.participant_id) do
      Capability.push_audio(capability, connection.participant_id, pcm)
    else
      nil -> {:error, :unavailable}
      true -> {:error, :held}
      %{} -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec interrupt(State.t()) :: {:ok, State.t()} | {:error, term()}
  def interrupt(%State{speech_to_speech_capability: nil} = state), do: {:ok, state}

  def interrupt(%State{} = state) do
    case Capability.interrupt(state.speech_to_speech_capability.pid) do
      {:ok, _played} -> {:ok, state}
      {:error, _reason} = error -> error
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec hold(State.t()) :: State.t()
  def hold(%State{speech_to_speech_capability: nil} = state), do: state

  def hold(%State{} = state) do
    _ = Capability.hold(state.speech_to_speech_capability.pid)
    state
  catch
    :exit, _reason -> state
  end

  @spec release(State.t()) :: State.t()
  def release(%State{speech_to_speech_capability: nil} = state), do: state

  def release(%State{} = state) do
    _ = Capability.release(state.speech_to_speech_capability.pid)
    state
  catch
    :exit, _reason -> state
  end

  @spec stop(State.t()) :: State.t()
  def stop(%State{speech_to_speech_capability: nil} = state), do: state

  def stop(%State{} = state) do
    state = cancel_pending_tools(state)
    retire_sts_enforcer(state)

    if state.speech_to_speech_monitor,
      do: Process.demonitor(state.speech_to_speech_monitor, [:flush])

    _ =
      RoomCapabilitySupervisor.stop_capability(
        state.snapshot.incarnation_id,
        state.speech_to_speech_capability.pid
      )

    %{
      state
      | speech_to_speech_capability: nil,
        speech_to_speech_monitor: nil,
        speech_to_speech_ready?: false,
        sts_turns: %{},
        sts_tool_calls: %{}
    }
  catch
    :exit, _reason ->
      %{
        state
        | speech_to_speech_capability: nil,
          speech_to_speech_monitor: nil,
          speech_to_speech_ready?: false,
          sts_turns: %{},
          sts_tool_calls: %{}
      }
  end

  def source_disconnected(
        %State{speech_to_speech_capability: %{connection_id: connection_id}} = state,
        connection_id
      ),
      do: stop(state)

  def source_disconnected(%State{} = state, _connection_id), do: state

  def authorize_connection(%State{speech_to_speech_runtime: nil}, _participant_id), do: :ok

  def authorize_connection(%State{} = state, participant_id) do
    source? = Map.get(state.participant_roles, participant_id) == :human

    already_attached? =
      Enum.any?(state.connections, fn {_id, connection} ->
        connection.role == :human and connection.admission == :main
      end)

    if source? and already_attached? do
      {:error,
       Error.new(:sts_source_already_attached, "Speech-to-speech permits one source connection.")}
    else
      :ok
    end
  end

  defp cancel_pending_tools(%State{sts_tool_calls: calls} = state) when map_size(calls) == 0,
    do: state

  defp cancel_pending_tools(%State{} = state) do
    capability = state.speech_to_speech_capability.pid

    Enum.reduce(state.sts_tool_calls, state, fn {call_ref, _pending}, state ->
      handle_tool_cancelled(state, capability, agent_participant(state), call_ref)
    end)
  end

  @doc """
  Starts the agent-owned STS allocation once its single human source connection
  is attached with an output sink. No-op when no STS runtime is planned, when
  the capability already exists, or when the connection has no sink yet.
  """
  @spec maybe_start(State.t(), map()) :: State.t()
  def maybe_start(%State{speech_to_speech_runtime: nil} = state, _connection), do: state

  def maybe_start(%State{speech_to_speech_capability: %{pid: pid}} = state, _connection)
      when is_pid(pid), do: state

  def maybe_start(%State{} = state, connection) when is_map(connection) do
    with %{output_sink: sink} when is_pid(sink) <- connection,
         %{speech_to_speech_runtime: runtime} when not is_nil(runtime) <- state,
         {:ok, {policy, revision}} <- allocation_policy(state),
         {:ok, started} <- start_allocation(state, connection, runtime, {policy, revision}) do
      state
      |> bind_capability(started, runtime.participant_id, runtime.activation_id)
      |> Map.update!(:speech_to_speech_capability, fn binding ->
        Map.merge(binding, %{
          connection_id: connection.attach_command.connection_id,
          connection: connection.pid
        })
      end)
      |> Map.put(:speech_to_speech_policy_revision, revision)
      |> register_sts_enforcer(started)
    else
      _unavailable -> state
    end
  end

  @doc """
  Returns a validated current policy and revision. Missing or unavailable
  authority never grants an unrestricted allocation.
  """
  @spec allocation_policy(State.t()) ::
          {:ok, {term(), non_neg_integer()}} | {:error, :media_policy_unavailable}
  def allocation_policy(%State{media_policy_authority: nil}),
    do: {:error, :media_policy_unavailable}

  def allocation_policy(%State{} = state) do
    case Authority.snapshot(state.media_policy_authority) do
      %Snapshot{effective: effective, revision: revision} = snapshot ->
        if Snapshot.valid?(snapshot),
          do: {:ok, {effective, revision}},
          else: {:error, :media_policy_unavailable}

      _unexpected ->
        {:error, :media_policy_unavailable}
    end
  catch
    :exit, _reason -> {:error, :media_policy_unavailable}
  end

  defp register_sts_enforcer(%State{} = state, capability) do
    result =
      try do
        Authority.register_connection_enforcer(
          state.media_policy_authority,
          capability,
          state.speech_to_speech_capability.connection
        )
      catch
        :exit, _reason -> {:error, :unavailable}
      end

    case result do
      {:ok, %Snapshot{} = snapshot} ->
        if Snapshot.valid?(snapshot),
          do: %{state | speech_to_speech_policy_revision: snapshot.revision},
          else: stop(state)

      _rejected ->
        stop(state)
    end
  end

  defp retire_sts_enforcer(%State{
         media_policy_authority: authority,
         speech_to_speech_capability: %{pid: capability, connection: connection}
       })
       when is_pid(authority) do
    Authority.retire_connection_enforcers(authority, connection, [capability])
  catch
    :exit, _reason -> :ok
  end

  defp retire_sts_enforcer(_state), do: :ok

  defp start_allocation(state, connection, runtime, {effective, revision}) do
    plan = state.participant_transfer_runtime.plan
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    human_id = caller.participant_id

    caller_source =
      case Map.get(state.speech_to_text_runtime, human_id) do
        nil -> :sts
        _human_stt -> :human_stt
      end

    options =
      [
        owner: self(),
        agent_id: runtime.participant_id,
        human_id: human_id,
        provider: runtime.provider,
        provider_private: runtime.provider_private,
        sink: connection.output_sink,
        frame_identity: %{
          tenant_id: state.snapshot.tenant_id,
          room_id: state.snapshot.room_id,
          incarnation_id: state.snapshot.incarnation_id,
          connection_id: connection.attach_command.connection_id
        },
        caller_source: caller_source,
        policy: effective,
        policy_revision: revision,
        usage_context: usage_context(state, runtime)
      ] ++ output_stt_options(runtime)

    RoomCapabilitySupervisor.start_speech_to_speech(state.snapshot.incarnation_id, options)
  end

  defp usage_context(state, runtime) do
    {provider_module, provider_options} = runtime.provider

    provider =
      case SpeechToSpeechRuntime.usage_identity(provider_module, provider_options) do
        {:ok, labels} ->
          case ProviderContext.new(name: labels[:name], model: labels[:model]) do
            {:ok, context} -> context
            {:error, _} -> %ProviderContext{name: "speech_to_speech"}
          end

        {:error, _reason} ->
          %ProviderContext{name: "speech_to_speech"}
      end

    [
      tenant_id: state.snapshot.tenant_id,
      call_id: runtime.call_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: runtime.participant_id,
      activation_id: runtime.activation_id,
      provider: provider
    ]
  end

  defp output_stt_options(%{output_speech_to_text: nil}), do: []

  defp output_stt_options(%{output_speech_to_text: {module, options}}) do
    [output_stt: {module, options}, output_stt_private: []]
  end
end
