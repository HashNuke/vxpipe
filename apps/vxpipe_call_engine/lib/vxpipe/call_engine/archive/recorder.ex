defmodule Vxpipe.CallEngine.Archive.Recorder do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Port
  alias Vxpipe.CallEngine.LiveInspection.Buffer, as: LiveInspectionBuffer
  alias Vxpipe.CallEngine.Command.{CreateRoom, SendText}

  alias Vxpipe.CallEngine.{
    Id,
    ResolvedCallPlan,
    TextToSpeechRequest
  }

  alias Vxpipe.CallEngine.Participant.Snapshot, as: ParticipantSnapshot
  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot

  @derive {Inspect, except: [:port]}
  @enforce_keys [:port, :participant_activations]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          port: nil | Port.t(),
          participant_activations: %{optional(String.t()) => String.t()}
        }

  @spec new(CreateRoom.t() | ResolvedCallPlan.t(), String.t(), keyword()) :: t()
  def new(%CreateRoom{}, _incarnation_id, _options) do
    %__MODULE__{port: nil, participant_activations: %{}}
  end

  def new(%ResolvedCallPlan{} = plan, incarnation_id, options) do
    port =
      Port.new(
        Keyword.get(options, :archive_handoff),
        live_inspection_port(plan),
        %{
          tenant_id: plan.tenant_id,
          call_id: plan.call_id,
          room_id: plan.room_id,
          incarnation_id: incarnation_id
        },
        Keyword.get(options, :archive_source_policy, %{"revision" => 0})
      )

    participant_activations =
      plan.participants
      |> Map.values()
      |> Enum.reject(&is_nil(&1.activation_id))
      |> Map.new(&{&1.participant_id, &1.activation_id})

    %__MODULE__{port: port, participant_activations: participant_activations}
  end

  @doc false
  @spec bind_participant_activation(t(), String.t(), nil | String.t()) :: t()
  def bind_participant_activation(%__MODULE__{} = recorder, _participant_id, nil), do: recorder

  def bind_participant_activation(%__MODULE__{} = recorder, participant_id, activation_id)
      when is_binary(participant_id) and is_binary(activation_id) do
    %{
      recorder
      | participant_activations:
          Map.put(recorder.participant_activations, participant_id, activation_id)
    }
  end

  @spec room_opened(t(), RoomSnapshot.t()) :: t()
  def room_opened(%__MODULE__{} = recorder, %RoomSnapshot{} = snapshot) do
    emit(recorder, :room_opened,
      id: Id.generate(:event),
      command_id: snapshot.created_by_command_id,
      occurred_at: DateTime.utc_now(:millisecond),
      payload: %{
        "created_by_actor_id" => snapshot.created_by_actor_id,
        "lifecycle" => snapshot.lifecycle
      }
    )
  end

  @spec participant_joined(t(), ParticipantSnapshot.t()) :: t()
  def participant_joined(%__MODULE__{} = recorder, %ParticipantSnapshot{} = participant) do
    emit(recorder, :participant_joined,
      id: Id.generate(:event),
      participant_id: participant.participant_id,
      activation_id: activation(recorder, participant.participant_id),
      command_id: participant.created_by_command_id,
      occurred_at: DateTime.utc_now(:millisecond),
      payload: %{
        "created_by_actor_id" => participant.created_by_actor_id,
        "role" => participant.role,
        "state" => participant.state
      }
    )
  end

  @spec participant_left(t(), String.t(), term()) :: t()
  def participant_left(%__MODULE__{} = recorder, participant_id, reason)
      when is_binary(participant_id) do
    emit(recorder, :participant_left,
      id: Id.generate(:event),
      participant_id: participant_id,
      activation_id: activation(recorder, participant_id),
      occurred_at: DateTime.utc_now(:millisecond),
      payload: %{"reason" => reason}
    )
  end

  @spec connection_attached(t(), struct(), atom()) :: t()
  def connection_attached(%__MODULE__{} = recorder, command, role) when is_atom(role) do
    emit(recorder, :connection_attached,
      id: Id.generate(:event),
      participant_id: command.participant_id,
      activation_id: activation(recorder, command.participant_id),
      connection_id: command.connection_id,
      command_id: command.id,
      occurred_at: DateTime.utc_now(:millisecond),
      payload: %{"actor_id" => command.actor_id, "role" => role}
    )
  end

  @spec connection_detached(t(), String.t(), map(), keyword()) :: t()
  def connection_detached(%__MODULE__{} = recorder, connection_id, connection, attributes \\ [])
      when is_binary(connection_id) and is_map(connection) and is_list(attributes) do
    emit(recorder, :connection_detached,
      id: Id.generate(:event),
      participant_id: connection.participant_id,
      activation_id: activation(recorder, connection.participant_id),
      connection_id: connection_id,
      command_id: Keyword.get(attributes, :command_id),
      occurred_at: DateTime.utc_now(:millisecond),
      payload: %{
        "reason" => Keyword.get(attributes, :reason),
        "role" => connection.role
      }
    )
  end

  @spec accepted_input(t(), SendText.t(), :audio | :text, map()) :: t()
  def accepted_input(
        %__MODULE__{} = recorder,
        %SendText{} = command,
        modality,
        source_policy \\ %{}
      )
      when modality in [:audio, :text] and is_map(source_policy) do
    emit(recorder, :accepted_input,
      id: Id.generate(:event),
      participant_id: command.participant_id,
      activation_id: activation(recorder, command.participant_id),
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id,
      occurred_at: DateTime.utc_now(:millisecond),
      source_policy: source_policy,
      payload: %{"content" => command.content, "modality" => modality}
    )
  end

  @spec delivered_output(t(), TextToSpeechRequest.t()) :: t()
  def delivered_output(%__MODULE__{} = recorder, %TextToSpeechRequest{} = request) do
    emit(recorder, :agent_output_delivered,
      id: Id.generate(:event),
      participant_id: request.participant_id,
      activation_id: activation(recorder, request.participant_id),
      source_participant_id: request.source_participant_id,
      connection_id: request.connection_id,
      command_id: request.command_id,
      correlation_id: request.correlation_id,
      occurred_at: DateTime.utc_now(:millisecond),
      source_policy: request.source_policy,
      payload: %{"output_id" => request.output_id, "text" => request.text}
    )
  end

  @spec event(t(), struct(), keyword()) :: t()
  def event(%__MODULE__{} = recorder, event, attributes \\ []) when is_list(attributes) do
    attributes =
      Keyword.put_new(attributes, :activation_id, activation(recorder, event.participant_id))

    %{recorder | port: Port.emit_event(recorder.port, event, attributes)}
  end

  @doc false
  @spec internal_fact(t(), atom(), keyword()) :: t()
  def internal_fact(%__MODULE__{} = recorder, kind, attributes)
      when is_atom(kind) and is_list(attributes) do
    emit(recorder, kind, attributes)
  end

  defp emit(recorder, kind, attributes) do
    %{recorder | port: Port.emit(recorder.port, kind, attributes)}
  end

  defp activation(recorder, participant_id) do
    Map.get(recorder.participant_activations, participant_id)
  end

  defp live_inspection_port(plan) do
    case LiveInspectionBuffer.port(plan.tenant_id, plan.call_id) do
      {:ok, port} -> port
      {:error, :unavailable} -> nil
    end
  end
end
