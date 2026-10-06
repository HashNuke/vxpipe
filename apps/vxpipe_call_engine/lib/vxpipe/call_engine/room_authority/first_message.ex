defmodule Vxpipe.CallEngine.RoomAuthority.FirstMessage do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.{CreateRoom, SendText}
  alias Vxpipe.CallEngine.{Error, Id, ResolvedCallPlan}
  alias Vxpipe.CallEngine.RoomAuthority.{OpeningAudio, TextCapability, TurnState}

  @derive {Inspect, only: [:mode, :status, :target_participant_id]}
  @enforce_keys [:mode, :status, :target_participant_id, :text]
  defstruct @enforce_keys ++ [turn_key: nil, pending_commands: []]

  @type t :: %__MODULE__{
          mode: :wait_for_input | :fixed | :generated,
          status: :completed | :pending | :started,
          target_participant_id: nil | String.t(),
          text: nil | String.t()
        }

  @spec new(CreateRoom.t() | ResolvedCallPlan.t()) :: t()
  def new(%CreateRoom{}), do: completed()

  def new(%ResolvedCallPlan{} = plan) do
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    case receiver.kind do
      :agent -> for_agent_activation(receiver, caller.participant_id, true)
      :human -> completed(caller.participant_id)
    end
  end

  @spec for_agent_activation(ResolvedCallPlan.Participant.t(), String.t(), boolean()) :: t()
  def for_agent_activation(
        %ResolvedCallPlan.Participant{} = participant,
        target_participant_id,
        true
      )
      when is_binary(target_participant_id) do
    first_message(participant, target_participant_id)
  end

  def for_agent_activation(
        %ResolvedCallPlan.Participant{},
        target_participant_id,
        false
      )
      when is_binary(target_participant_id) do
    completed(target_participant_id)
  end

  defp first_message(participant, target_participant_id) do
    mode = participant.first_message

    %__MODULE__{
      mode: mode,
      status: if(mode == :wait_for_input, do: :completed, else: :pending),
      target_participant_id: target_participant_id,
      text: participant.first_message_text
    }
  end

  @spec completed() :: t()
  def completed, do: completed(nil)

  @spec completed(nil | String.t()) :: t()
  def completed(target_participant_id) do
    %__MODULE__{
      mode: :wait_for_input,
      status: :completed,
      target_participant_id: target_participant_id,
      text: nil
    }
  end

  @spec start(map()) :: {:ok, map()} | {:error, Error.t()}
  def start(%{first_message: %__MODULE__{status: status}} = state)
      when status in [:completed, :started],
      do: {:ok, state}

  def start(%{startup_ready?: false} = state), do: {:ok, state}

  def start(%{text_capability: nil, speech_to_speech_runtime: runtime} = state)
      when not is_nil(runtime) do
    case state.first_message.mode do
      :wait_for_input ->
        {:ok, state}

      mode when mode in [:fixed, :generated] ->
        opening = if mode == :fixed, do: {:fixed, state.first_message.text}, else: :generated

        with %{pid: capability} when is_pid(capability) <- state.speech_to_speech_capability,
             :ok <-
               Vxpipe.CallEngine.Capability.SpeechToSpeech.begin_opening(
                 capability,
                 opening
               ) do
          first_message = %{state.first_message | status: :started}
          {:ok, %{state | first_message: first_message}}
        else
          _unavailable -> {:error, unavailable()}
        end
    end
  end

  def start(state) do
    with :open <- OpeningAudio.admission(state.opening_audio),
         {:ok, connection_id, connection} <- target_connection(state),
         {:ok, command} <- greeting_command(connection_id, connection, state),
         :ok <- begin_greeting(command, state) do
      state = TurnState.put(state, command)
      first_message = %{state.first_message | status: :started, turn_key: TurnState.key(command)}
      {:ok, %{state | first_message: first_message}}
    else
      :opening_audio -> {:ok, state}
      :not_attached -> {:ok, state}
      {:error, %Error{}} = error -> error
      {:error, _reason} -> {:error, unavailable()}
    end
  end

  defp target_connection(state) do
    Enum.find_value(state.connections, :not_attached, fn {connection_id, connection} ->
      if connection.participant_id == state.first_message.target_participant_id do
        {:ok, connection_id, connection}
      end
    end)
  end

  defp greeting_command(connection_id, connection, state) do
    content =
      case state.first_message.mode do
        :fixed -> state.first_message.text
        :generated -> "Begin the conversation now with a brief greeting for the caller."
      end

    SendText.new(
      tenant_id: state.snapshot.tenant_id,
      actor_id: connection.actor_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: connection.participant_id,
      connection_id: connection_id,
      correlation_id: Id.generate(:turn),
      content: content,
      run_immediately: false,
      audio_response: true,
      deadline: DateTime.add(DateTime.utc_now(), 5, :second)
    )
  end

  defp begin_greeting(command, state) do
    case state.first_message.mode do
      :fixed ->
        TextCapability.fixed_greeting(state.text_capability, command, state.first_message.text)

      :generated ->
        TextCapability.generated_greeting(state.text_capability, command)
    end
  end

  def playing?(%{first_message: %__MODULE__{status: status}}), do: status in [:pending, :started]

  def respond(capability, command, state) do
    if playing?(state) do
      first = state.first_message

      if length(first.pending_commands) < 16,
        do:
          {:ok,
           %{
             state
             | first_message: %{first | pending_commands: first.pending_commands ++ [command]}
           }},
        else: {:error, :queue_full}
    else
      case TextCapability.respond(capability, command) do
        :ok -> {:ok, state}
        error -> error
      end
    end
  end

  def sts_started(%{first_message: %{status: :started, turn_key: nil} = first} = state, turn) do
    %{state | first_message: %{first | turn_key: {:sts, turn}}}
  end

  def sts_started(state, _turn), do: state

  def sts_completed(
        %{first_message: %{status: :started, turn_key: {:sts, turn}} = first} = state,
        turn
      ) do
    %{state | first_message: %{first | status: :completed, turn_key: nil}}
  end

  def sts_completed(state, _turn), do: state

  def complete(state, command) do
    first = state.first_message

    if first.status == :started and first.turn_key == TurnState.key(command) do
      pending = first.pending_commands

      state = %{
        state
        | first_message: %{first | status: :completed, pending_commands: [], turn_key: nil}
      }

      Enum.reduce(pending, state, fn queued, current ->
        connection = Map.get(current.connections, queued.connection_id)

        if connection != nil and connection.participant_id == queued.participant_id and
             not MapSet.member?(current.held_participant_ids, queued.participant_id) and
             TurnState.active?(current, queued) do
          command = %{queued | deadline: DateTime.add(DateTime.utc_now(), 5, :second)}

          case TextCapability.respond(current.text_capability, command) do
            :ok ->
              current

            {:error, reason} ->
              send(
                self(),
                {:vxpipe_capability_failed, current.text_capability.pid, command, reason}
              )

              current
          end
        else
          current
        end
      end)
    else
      state
    end
  end

  defp unavailable do
    Error.new(
      :first_message_unavailable,
      "The configured first message could not be started.",
      retryable: true
    )
  end
end
