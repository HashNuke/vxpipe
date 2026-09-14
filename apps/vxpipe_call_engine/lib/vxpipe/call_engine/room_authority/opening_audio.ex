defmodule Vxpipe.CallEngine.RoomAuthority.OpeningAudio do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan.OpeningAudio, as: OpeningSource
  alias Vxpipe.CallEngine.RoomAuthority.Startup
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom}

  alias Vxpipe.CallEngine.OpeningAudio.{
    CachedPlaybackRequest,
    FilePlaybackRequest,
    PlaybackGate,
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
  defstruct @enforce_keys ++
              [
                capability: nil,
                gate: nil,
                gate_monitor: nil,
                monitor: nil,
                request: nil,
                started_at: nil,
                worker: nil
              ]

  @type phase :: :open | :awaiting_connection | :preparing | :ready | :playing
  @type request ::
          nil | TextToSpeechRequest.t() | FilePlaybackRequest.t() | CachedPlaybackRequest.t()
  @type t :: %__MODULE__{
          phase: phase(),
          source: nil | OpeningSource.t(),
          participant_id: nil | String.t(),
          target_participant_id: nil | String.t(),
          settings: nil | Settings.t(),
          capability: nil | map(),
          gate: nil | pid(),
          gate_monitor: nil | reference(),
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

    %__MODULE__{
      participant_id: caller.participant_id,
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

  @spec prepare(t(), nil | Vxpipe.CallEngine.TextToSpeechRuntime.t(), struct()) ::
          {:ok, t()} | {:error, term()}
  def prepare(opening, nil, _state), do: {:ok, opening}

  def prepare(%__MODULE__{} = opening, runtime, state) do
    with {:ok, capability} <-
           Startup.prepare_text_to_speech(runtime, opening.participant_id, state) do
      {:ok, %{opening | capability: Startup.activate_text_to_speech(capability)}}
    end
  end

  @spec capability?(t(), pid()) :: boolean()
  def capability?(%__MODULE__{capability: %{pid: pid}}, pid), do: true
  def capability?(%__MODULE__{}, _pid), do: false

  @spec start(t(), AttachConnection.t(), map(), struct(), pid()) ::
          {:ok, t()} | {:error, Error.t()}
  def start(%__MODULE__{phase: phase} = opening, _command, _connection, _snapshot, _owner)
      when phase != :awaiting_connection,
      do: {:ok, opening}

  def start(
        %__MODULE__{capability: nil, source: %OpeningSource{type: :text}} = opening,
        _command,
        _connection,
        _snapshot,
        _owner
      ),
      do: {:ok, opening}

  def start(opening, command, connection, snapshot, owner)
      when command.participant_id == opening.target_participant_id and
             is_pid(connection.output_sink) do
    options = [
      owner: owner,
      output_sink: connection.output_sink,
      connection_id: command.connection_id
    ]

    with {:ok, gate} <-
           RoomCapabilitySupervisor.start_opening_audio_gate(snapshot.incarnation_id, options),
         {:ok, opening} <-
           start_playback(opening, command, %{connection | output_sink: gate}, snapshot, owner) do
      {:ok, %{opening | gate: gate, gate_monitor: Process.monitor(gate), phase: :preparing}}
    else
      _failed -> {:error, unavailable()}
    end
  end

  def start(opening, _command, _connection, _snapshot, _owner), do: {:ok, opening}

  def ready(%__MODULE__{gate: gate, phase: :preparing} = opening, gate),
    do: %{opening | phase: :ready}

  def ready(opening, _gate), do: opening

  def release(%__MODULE__{gate: gate, phase: :ready} = opening) do
    case PlaybackGate.release(gate) do
      :ok -> {:ok, %{opening | phase: :playing}}
      _failed -> {:error, unavailable()}
    end
  catch
    :exit, _reason -> {:error, unavailable()}
  end

  defp start_playback(
         %__MODULE__{
           participant_id: participant_id,
           capability: %{asset_cache_identity: cache_identity, pid: capability},
           phase: :awaiting_connection,
           settings: %Settings{},
           source: %OpeningSource{type: :text, text: text}
         } = opening,
         %AttachConnection{} = command,
         %{output_sink: output_sink},
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
      participant_id: participant_id,
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

  defp start_playback(
         %__MODULE__{
           participant_id: participant_id,
           phase: :awaiting_connection,
           settings: %Settings{} = settings,
           source: %OpeningSource{type: :file_url, url: url}
         } = opening,
         %AttachConnection{} = command,
         %{output_sink: output_sink},
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
        %__MODULE__{request: expected, worker: worker},
        worker,
        request
      ) do
    matching_asset_request?(expected, request)
  end

  def asset_failure?(%__MODULE__{}, _worker, _request), do: false

  @spec worker_monitor?(t(), reference()) :: boolean()
  def worker_monitor?(%__MODULE__{capability: %{monitor: monitor}}, monitor)
      when is_reference(monitor),
      do: true

  def worker_monitor?(%__MODULE__{gate_monitor: monitor}, monitor)
      when is_reference(monitor),
      do: true

  def worker_monitor?(%__MODULE__{monitor: monitor}, monitor)
      when is_reference(monitor),
      do: true

  def worker_monitor?(%__MODULE__{}, _monitor), do: false

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
    release_capability(opening)
    Process.demonitor(opening.gate_monitor, [:flush])
    RoomCapabilitySupervisor.stop_capability(opening.request.incarnation_id, opening.gate)

    %{
      opening
      | capability: nil,
        gate: nil,
        gate_monitor: nil,
        monitor: nil,
        phase: :open,
        request: nil,
        started_at: nil,
        worker: nil
    }
  end

  defp release_capability(%__MODULE__{capability: nil}), do: :ok

  defp release_capability(%__MODULE__{capability: capability, request: request}) do
    Process.demonitor(capability.monitor, [:flush])
    RoomCapabilitySupervisor.stop_capability(request.incarnation_id, capability.pid)
  end

  defp unavailable do
    Error.new(
      :opening_audio_unavailable,
      "The configured opening audio could not be played.",
      retryable: true
    )
  end
end
