defmodule Vxpipe.CallEngine.RoomAuthority.OpeningAudio do
  @moduledoc false

  alias Vxpipe.CallEngine.CallDefinition.OpeningAudio, as: OpeningSource
  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom}
  alias Vxpipe.CallEngine.{Error, Id, ResolvedCallPlan, TextToSpeechRequest}

  @derive {Inspect, only: [:phase, :target_participant_id]}
  @enforce_keys [:phase, :source, :target_participant_id]
  defstruct @enforce_keys ++ [request: nil]

  @type phase :: :open | :awaiting_connection | :playing
  @type t :: %__MODULE__{
          phase: phase(),
          source: nil | OpeningSource.t(),
          target_participant_id: nil | String.t(),
          request: nil | TextToSpeechRequest.t()
        }

  @spec new(CreateRoom.t() | ResolvedCallPlan.t()) :: t()
  def new(%CreateRoom{}) do
    open()
  end

  def new(%ResolvedCallPlan{opening_audio: nil}) do
    open()
  end

  def new(%ResolvedCallPlan{opening_audio: %OpeningSource{} = source} = plan) do
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    %__MODULE__{
      phase: :awaiting_connection,
      source: source,
      target_participant_id: caller.participant_id
    }
  end

  @spec open() :: t()
  def open, do: %__MODULE__{phase: :open, source: nil, target_participant_id: nil}

  @spec admission(t()) :: :open | :opening_audio
  def admission(%__MODULE__{phase: :open}), do: :open
  def admission(%__MODULE__{}), do: :opening_audio

  @spec start(t(), AttachConnection.t(), map(), nil | map(), struct()) ::
          {:ok, t()} | {:error, Error.t()}
  def start(%__MODULE__{phase: :open} = opening, _command, _connection, _capability, _snapshot),
    do: {:ok, opening}

  def start(
        %__MODULE__{phase: :awaiting_connection, target_participant_id: target} = opening,
        %AttachConnection{participant_id: participant_id},
        _connection,
        _capability,
        _snapshot
      )
      when participant_id != target,
      do: {:ok, opening}

  def start(
        %__MODULE__{
          phase: :awaiting_connection,
          source: %OpeningSource{type: :text, text: text}
        } = opening,
        %AttachConnection{} = command,
        %{output_sink: output_sink},
        %{participant_id: agent_participant_id, pid: capability},
        snapshot
      )
      when is_pid(output_sink) and is_pid(capability) and is_binary(text) do
    request = %TextToSpeechRequest{
      tenant_id: snapshot.tenant_id,
      room_id: snapshot.room_id,
      incarnation_id: snapshot.incarnation_id,
      participant_id: agent_participant_id,
      source_participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: Id.generate(:command),
      correlation_id: Id.generate(:turn),
      output_id: Id.generate(:event),
      text: text,
      output_sink: output_sink,
      purpose: :opening_audio
    }

    case TextToSpeech.synthesize(capability, request) do
      :ok -> {:ok, %{opening | phase: :playing, request: request}}
      {:error, _reason} -> {:error, unavailable()}
    end
  end

  def start(
        %__MODULE__{phase: :awaiting_connection},
        _command,
        _connection,
        _capability,
        _snapshot
      ) do
    {:error, unavailable()}
  end

  def start(
        %__MODULE__{phase: :playing} = opening,
        _command,
        _connection,
        _capability,
        _snapshot
      ),
      do: {:ok, opening}

  @spec playback(t(), TextToSpeechRequest.t(), :started | :completed | tuple()) ::
          :unrelated | {:handled, t()}
  def playback(
        %__MODULE__{phase: :playing, request: expected} = opening,
        %TextToSpeechRequest{purpose: :opening_audio} = request,
        status
      ) do
    if matching_request?(expected, request) do
      case status do
        :completed -> {:handled, %{opening | phase: :open, request: nil}}
        _started_or_progress -> {:handled, opening}
      end
    else
      :unrelated
    end
  end

  def playback(%__MODULE__{}, %TextToSpeechRequest{}, _status), do: :unrelated

  @spec awaiting_playback?(t()) :: boolean()
  def awaiting_playback?(%__MODULE__{phase: :playing}), do: true
  def awaiting_playback?(%__MODULE__{}), do: false

  defp matching_request?(expected, request) do
    expected != nil and expected.correlation_id == request.correlation_id and
      expected.connection_id == request.connection_id and
      expected.output_sink == request.output_sink
  end

  defp unavailable do
    Error.new(
      :opening_audio_unavailable,
      "The configured opening audio could not be played.",
      retryable: true
    )
  end
end
