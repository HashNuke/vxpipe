defmodule Vxpipe.CallEngine.OpeningAudio.Player do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, OutputSink}
  alias Vxpipe.CallEngine.OpeningAudio.{Asset, AssetLoader, FilePlaybackRequest, Settings}

  @frame_bytes 1_920

  @derive {Inspect, only: [:phase, :request]}
  @enforce_keys [:owner, :phase, :request, :settings]
  defstruct @enforce_keys

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    request = Keyword.fetch!(options, :request)

    %{
      id: {__MODULE__, request.correlation_id},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @impl true
  def init(options) do
    owner = Keyword.get(options, :owner)
    request = Keyword.get(options, :request)
    settings = Keyword.get(options, :settings)

    if is_pid(owner) and FilePlaybackRequest.valid?(request) and match?(%Settings{}, settings) do
      {:ok,
       %__MODULE__{
         owner: owner,
         phase: :preparing,
         request: request,
         settings: settings
       }, {:continue, :prepare}}
    else
      {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_continue(:prepare, state) do
    with {:ok, %Asset{} = asset} <-
           AssetLoader.load(state.request.tenant_id, state.request.url, state.settings),
         :ok <- push_audio(asset, state.request),
         :ok <-
           OutputSink.finish(
             state.request.output_sink,
             state.request.correlation_id,
             self()
           ) do
      {:noreply, %{state | phase: :awaiting_playback}}
    else
      _error -> unavailable(state)
    end
  end

  @impl true
  def handle_info(
        {:vxpipe_audio_playback, sink, correlation_id, :started},
        %{phase: :awaiting_playback, request: request} = state
      )
      when sink == request.output_sink and correlation_id == request.correlation_id do
    notify(state, :started)
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_audio_playback, sink, correlation_id, {:progress, played_ms, total_ms}},
        %{phase: :awaiting_playback, request: request} = state
      )
      when sink == request.output_sink and correlation_id == request.correlation_id and
             is_integer(played_ms) and played_ms > 0 and is_integer(total_ms) and
             total_ms > played_ms do
    notify(state, {:progress, played_ms, total_ms})
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_audio_playback, sink, correlation_id, {:completed, total_ms}},
        %{phase: :awaiting_playback, request: request} = state
      )
      when sink == request.output_sink and correlation_id == request.correlation_id and
             is_integer(total_ms) and total_ms >= 0 do
    notify(state, :completed)
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp push_audio(%Asset{payload: payload} = asset, request) do
    push_frames(payload, asset, request)
  end

  defp push_frames(<<>>, _asset, _request), do: :ok

  defp push_frames(payload, asset, request) do
    frame_size = min(byte_size(payload), @frame_bytes)
    <<frame_payload::binary-size(frame_size), remainder::binary>> = payload

    case OutputSink.push(request.output_sink, output_frame(frame_payload, asset, request)) do
      :ok -> push_frames(remainder, asset, request)
      {:error, _reason} = error -> error
    end
  end

  defp output_frame(payload, asset, request) do
    %AudioOutputFrame{
      tenant_id: request.tenant_id,
      room_id: request.room_id,
      incarnation_id: request.incarnation_id,
      participant_id: request.participant_id,
      connection_id: request.connection_id,
      command_id: request.command_id,
      correlation_id: request.correlation_id,
      codec: asset.codec,
      sample_rate: asset.sample_rate,
      channels: asset.channels,
      byte_order: asset.byte_order,
      payload: payload,
      reply_to: self()
    }
  end

  defp unavailable(state) do
    send(
      state.owner,
      {:vxpipe_opening_audio_unavailable, self(), state.request, :playback_failed}
    )

    {:stop, :normal, state}
  end

  defp notify(state, status) do
    send(state.owner, {:vxpipe_opening_audio_playback, self(), state.request, status})
  end
end
