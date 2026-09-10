defmodule Vxpipe.CallEngine.RoomAuthority.OpeningAudio do
  @moduledoc false

  alias Vxpipe.CallEngine.CallDefinition.OpeningAudio, as: OpeningSource
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom}

  alias Vxpipe.CallEngine.OpeningAudio.{
    CachedPlaybackRequest,
    FilePlaybackRequest,
    Settings,
    TextPreparation
  }

  alias Vxpipe.CallEngine.{
    Error,
    Id,
    ResolvedCallPlan,
    RoomCapabilitySupervisor,
    Telemetry,
    TextToSpeechRequest
  }

  @derive {Inspect, only: [:phase, :target_participant_id]}
  @enforce_keys [:participant_id, :phase, :settings, :source, :target_participant_id]
  defstruct @enforce_keys ++ [monitor: nil, request: nil, started_at: nil, worker: nil]

  @type phase :: :open | :awaiting_connection | :playing
  @type request ::
          nil | TextToSpeechRequest.t() | FilePlaybackRequest.t() | CachedPlaybackRequest.t()
  @type t :: %__MODULE__{
          phase: phase(),
          source: nil | OpeningSource.t(),
          participant_id: nil | String.t(),
          target_participant_id: nil | String.t(),
          settings: nil | Settings.t(),
          request: request(),
          started_at: nil | integer(),
          worker: nil | pid(),
          monitor: nil | reference()
        }

  @spec new(CreateRoom.t() | ResolvedCallPlan.t(), nil | Settings.t()) :: t()
  def new(%CreateRoom{}, _settings), do: open()
  def new(%ResolvedCallPlan{opening_audio: nil}, _settings), do: open()

  def new(
        %ResolvedCallPlan{opening_audio: %OpeningSource{} = source} = plan,
        settings
      ) do
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    %__MODULE__{
      participant_id: receiver.participant_id,
      phase: :awaiting_connection,
      settings: settings,
      source: source,
      target_participant_id: caller.participant_id
    }
  end

  @spec open() :: t()
  def open do
    %__MODULE__{
      participant_id: nil,
      phase: :open,
      settings: nil,
      source: nil,
      target_participant_id: nil
    }
  end

  @spec admission(t()) :: :open | :opening_audio
  def admission(%__MODULE__{phase: :open}), do: :open
  def admission(%__MODULE__{}), do: :opening_audio

  @spec start(t(), AttachConnection.t(), map(), nil | map(), struct(), pid()) ::
          {:ok, t()} | {:error, Error.t()}
  def start(
        %__MODULE__{phase: :open} = opening,
        _command,
        _connection,
        _capability,
        _snapshot,
        _owner
      ),
      do: {:ok, opening}

  def start(
        %__MODULE__{phase: :awaiting_connection, target_participant_id: target} = opening,
        %AttachConnection{participant_id: participant_id},
        _connection,
        _capability,
        _snapshot,
        _owner
      )
      when participant_id != target,
      do: {:ok, opening}

  def start(
        %__MODULE__{
          participant_id: agent_participant_id,
          phase: :awaiting_connection,
          settings: %Settings{},
          source: %OpeningSource{type: :text, text: text}
        } = opening,
        %AttachConnection{} = command,
        %{output_sink: output_sink},
        %{asset_cache_identity: cache_identity, pid: capability},
        snapshot,
        owner
      )
      when is_pid(output_sink) and is_pid(capability) and is_pid(owner) and is_binary(text) and
             is_map(cache_identity) do
    options = [
      text: text,
      command: command,
      output_sink: output_sink,
      capability: capability,
      cache_identity: cache_identity,
      snapshot: snapshot,
      participant_id: agent_participant_id,
      owner: owner,
      settings: opening.settings
    ]

    started_at = Telemetry.started_at()

    case TextPreparation.start(options) do
      {:ok, request, nil} ->
        {:ok, %{opening | phase: :playing, request: request, started_at: started_at}}

      {:ok, request, worker} when is_pid(worker) ->
        {:ok,
         %{
           opening
           | monitor: Process.monitor(worker),
             phase: :playing,
             request: request,
             started_at: started_at,
             worker: worker
         }}

      {:error, :unavailable} ->
        Telemetry.opening_audio_stop(started_at, :text, :failed)
        {:error, unavailable()}
    end
  end

  def start(
        %__MODULE__{
          participant_id: participant_id,
          phase: :awaiting_connection,
          settings: %Settings{} = settings,
          source: %OpeningSource{type: :file_url, url: url}
        } = opening,
        %AttachConnection{} = command,
        %{output_sink: output_sink},
        _capability,
        snapshot,
        owner
      )
      when is_pid(output_sink) and is_pid(owner) and is_binary(url) do
    request = %FilePlaybackRequest{
      tenant_id: snapshot.tenant_id,
      room_id: snapshot.room_id,
      incarnation_id: snapshot.incarnation_id,
      participant_id: participant_id,
      connection_id: command.connection_id,
      command_id: Id.generate(:command),
      correlation_id: Id.generate(:turn),
      url: url,
      output_sink: output_sink
    }

    started_at = Telemetry.started_at()

    case RoomCapabilitySupervisor.start_opening_audio(
           snapshot.incarnation_id,
           owner,
           request,
           settings
         ) do
      {:ok, worker} ->
        {:ok,
         %{
           opening
           | monitor: Process.monitor(worker),
             phase: :playing,
             request: request,
             started_at: started_at,
             worker: worker
         }}

      {:error, _reason} ->
        Telemetry.opening_audio_stop(started_at, :file_url, :failed)
        {:error, unavailable()}
    end
  end

  def start(
        %__MODULE__{phase: :awaiting_connection},
        _command,
        _connection,
        _capability,
        _snapshot,
        _owner
      ) do
    {:error, unavailable()}
  end

  def start(
        %__MODULE__{phase: :playing} = opening,
        _command,
        _connection,
        _capability,
        _snapshot,
        _owner
      ),
      do: {:ok, opening}

  @spec playback(t(), TextToSpeechRequest.t(), :started | :completed | tuple()) ::
          :unrelated | {:handled, t()}
  def playback(
        %__MODULE__{phase: :playing, request: expected} = opening,
        %TextToSpeechRequest{purpose: :opening_audio} = request,
        status
      ) do
    if matching_text_request?(expected, request) do
      case status do
        :completed -> {:handled, opened(opening)}
        _started_or_progress -> {:handled, opening}
      end
    else
      :unrelated
    end
  end

  def playback(%__MODULE__{}, %TextToSpeechRequest{}, _status), do: :unrelated

  @spec asset_playback(
          t(),
          pid(),
          FilePlaybackRequest.t() | CachedPlaybackRequest.t(),
          :started | :completed | tuple()
        ) ::
          :unrelated | {:handled, t()}
  def asset_playback(
        %__MODULE__{phase: :playing, request: expected, worker: worker} = opening,
        worker,
        request,
        status
      ) do
    if matching_asset_request?(expected, request) do
      case status do
        :completed ->
          Process.demonitor(opening.monitor, [:flush])
          {:handled, opened(opening)}

        _started_or_progress ->
          {:handled, opening}
      end
    else
      :unrelated
    end
  end

  def asset_playback(%__MODULE__{}, _worker, _request, _status), do: :unrelated

  @spec asset_failure?(t(), pid(), FilePlaybackRequest.t() | CachedPlaybackRequest.t()) ::
          boolean()
  def asset_failure?(
        %__MODULE__{phase: :playing, request: expected, worker: worker},
        worker,
        request
      ) do
    matching_asset_request?(expected, request)
  end

  def asset_failure?(%__MODULE__{}, _worker, _request), do: false

  @spec worker_monitor?(t(), reference()) :: boolean()
  def worker_monitor?(%__MODULE__{phase: :playing, monitor: monitor}, monitor)
      when is_reference(monitor),
      do: true

  def worker_monitor?(%__MODULE__{}, _monitor), do: false

  @spec awaiting_text_playback?(t()) :: boolean()
  def awaiting_text_playback?(%__MODULE__{
        phase: :playing,
        request: %TextToSpeechRequest{}
      }),
      do: true

  def awaiting_text_playback?(%__MODULE__{}), do: false

  @spec failed(t()) :: :ok
  def failed(%__MODULE__{
        source: %OpeningSource{type: source},
        started_at: started_at
      })
      when source in [:file_url, :text] and is_integer(started_at) do
    Telemetry.opening_audio_stop(started_at, source, :failed)
  end

  def failed(%__MODULE__{}), do: :ok

  defp matching_text_request?(%TextToSpeechRequest{} = expected, request) do
    expected.correlation_id == request.correlation_id and
      expected.connection_id == request.connection_id and
      expected.output_sink == request.output_sink
  end

  defp matching_text_request?(_expected, _request), do: false

  defp matching_file_request?(%FilePlaybackRequest{} = expected, request) do
    expected.correlation_id == request.correlation_id and
      expected.connection_id == request.connection_id and
      expected.output_sink == request.output_sink
  end

  defp matching_file_request?(_expected, _request), do: false

  defp matching_asset_request?(
         %FilePlaybackRequest{} = expected,
         %FilePlaybackRequest{} = request
       ),
       do: matching_file_request?(expected, request)

  defp matching_asset_request?(
         %CachedPlaybackRequest{} = expected,
         %CachedPlaybackRequest{} = request
       ) do
    expected.correlation_id == request.correlation_id and
      expected.connection_id == request.connection_id and
      expected.output_sink == request.output_sink
  end

  defp matching_asset_request?(_expected, _request), do: false

  defp opened(%__MODULE__{source: %OpeningSource{type: source}, started_at: started_at} = opening) do
    Telemetry.opening_audio_stop(started_at, source, :completed)
    %{opening | monitor: nil, phase: :open, request: nil, started_at: nil, worker: nil}
  end

  defp unavailable do
    Error.new(
      :opening_audio_unavailable,
      "The configured opening audio could not be played.",
      retryable: true
    )
  end
end
