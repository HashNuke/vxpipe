defmodule Vxpipe.CallEngine.RoomAuthority.FirstMessage do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.{CreateRoom, SendText}
  alias Vxpipe.CallEngine.{Error, Id, ResolvedCallPlan}
  alias Vxpipe.CallEngine.RoomAuthority.{OpeningAudio, TextCapability, TurnState}

  @derive {Inspect, only: [:mode, :status, :target_participant_id]}
  @enforce_keys [:mode, :status, :target_participant_id, :text]
  defstruct @enforce_keys

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

    %__MODULE__{
      mode: receiver.first_message,
      status: if(receiver.first_message == :wait_for_input, do: :completed, else: :pending),
      target_participant_id: caller.participant_id,
      text: receiver.first_message_text
    }
  end

  @spec completed() :: t()
  def completed do
    %__MODULE__{
      mode: :wait_for_input,
      status: :completed,
      target_participant_id: nil,
      text: nil
    }
  end

  @spec start(map()) :: {:ok, map()} | {:error, Error.t()}
  def start(%{first_message: %__MODULE__{status: status}} = state)
      when status in [:completed, :started],
      do: {:ok, state}

  def start(%{startup_ready?: false} = state), do: {:ok, state}

  def start(state) do
    with :open <- OpeningAudio.admission(state.opening_audio),
         {:ok, connection_id, connection} <- target_connection(state),
         {:ok, command} <- greeting_command(connection_id, connection, state),
         :ok <- begin_greeting(command, state) do
      state = TurnState.put(state, command)
      first_message = %{state.first_message | status: :started}
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

  defp unavailable do
    Error.new(
      :first_message_unavailable,
      "The configured first message could not be started.",
      retryable: true
    )
  end
end
