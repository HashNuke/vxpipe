defmodule Vxpipe.CallEngine.OpeningAudio.TextCacheSink do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, OutputSink}
  alias Vxpipe.CallEngine.OpeningAudio.{Asset, AssetCache, Settings}

  @derive {Inspect, only: [:phase, :total_bytes]}
  @enforce_keys [
    :cache,
    :cache_key,
    :command_id,
    :connection_id,
    :correlation_id,
    :maximum_bytes,
    :maximum_duration_ms,
    :phase,
    :target_sink
  ]
  defstruct @enforce_keys ++
              [chunks: [], format: nil, total_bytes: 0, upstream_callback: nil]

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :correlation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @impl true
  def init(options) do
    settings = Keyword.get(options, :settings)

    with %Settings{} <- settings,
         cache when is_pid(cache) or is_atom(cache) <- settings.cache,
         cache_key when is_binary(cache_key) <- Keyword.get(options, :cache_key),
         command_id when is_binary(command_id) <- Keyword.get(options, :command_id),
         connection_id when is_binary(connection_id) <- Keyword.get(options, :connection_id),
         correlation_id when is_binary(correlation_id) <- Keyword.get(options, :correlation_id),
         target_sink when is_pid(target_sink) <- Keyword.get(options, :target_sink) do
      {:ok,
       %__MODULE__{
         cache: cache,
         cache_key: cache_key,
         command_id: command_id,
         connection_id: connection_id,
         correlation_id: correlation_id,
         maximum_bytes: settings.maximum_bytes,
         maximum_duration_ms: settings.maximum_duration_ms,
         phase: :collecting,
         target_sink: target_sink
       }}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call(
        {:vxpipe_audio_output, %AudioOutputFrame{} = frame},
        _from,
        %{phase: :collecting} = state
      ) do
    with :ok <- validate_frame(frame, state),
         :ok <- within_limits(frame, state),
         :ok <- OutputSink.push(state.target_sink, %{frame | reply_to: self()}) do
      format = state.format || media_format(frame)

      {:reply, :ok,
       %{
         state
         | chunks: [frame.payload | state.chunks],
           format: format,
           total_bytes: state.total_bytes + byte_size(frame.payload),
           upstream_callback: frame.reply_to
       }}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_audio_output, %AudioOutputFrame{}}, _from, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call(
        {:vxpipe_audio_output_finish, turn, callback},
        _from,
        %{phase: :collecting} = state
      ) do
    with :ok <- validate_finish(turn, callback, state),
         :ok <- OutputSink.finish(state.target_sink, turn, self()) do
      cache(state)
      {:reply, :ok, %{state | phase: :draining}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_audio_output_finish, _turn, _callback}, _from, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:vxpipe_audio_output_interrupt, turn, callback}, _from, state) do
    if turn == state.correlation_id and callback == state.upstream_callback do
      {:reply, OutputSink.interrupt(state.target_sink, turn, self()), state}
    else
      {:reply, {:error, :wrong_turn}, state}
    end
  end

  @impl true
  def handle_info({:vxpipe_audio_playback, sink, turn, :started}, state)
      when sink == state.target_sink and turn == state.correlation_id do
    forward_playback(:started, state)
    {:noreply, state}
  end

  def handle_info({:vxpipe_audio_playback, sink, turn, {:progress, played_ms, total_ms}}, state)
      when sink == state.target_sink and turn == state.correlation_id and
             is_integer(played_ms) and played_ms > 0 and is_integer(total_ms) and
             total_ms > played_ms do
    forward_playback({:progress, played_ms, total_ms}, state)
    {:noreply, state}
  end

  def handle_info({:vxpipe_audio_playback, sink, turn, {:completed, total_ms}}, state)
      when sink == state.target_sink and turn == state.correlation_id and
             is_integer(total_ms) and total_ms >= 0 do
    forward_playback({:completed, total_ms}, state)
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp validate_frame(frame, state) do
    format = media_format(frame)

    cond do
      frame.connection_id != state.connection_id ->
        {:error, :wrong_connection}

      frame.command_id != state.command_id ->
        {:error, :wrong_turn}

      frame.correlation_id != state.correlation_id ->
        {:error, :wrong_turn}

      not is_pid(frame.reply_to) ->
        {:error, :invalid_frame}

      not is_binary(frame.payload) or byte_size(frame.payload) == 0 ->
        {:error, :invalid_frame}

      frame.codec != :linear16 ->
        {:error, :unsupported_audio}

      frame.channels != 1 ->
        {:error, :unsupported_audio}

      frame.byte_order != :little ->
        {:error, :unsupported_audio}

      not is_integer(frame.sample_rate) or frame.sample_rate <= 0 ->
        {:error, :unsupported_audio}

      state.format != nil and state.format != format ->
        {:error, :unsupported_audio}

      state.upstream_callback != nil and state.upstream_callback != frame.reply_to ->
        {:error, :wrong_turn}

      true ->
        :ok
    end
  end

  defp within_limits(frame, state) do
    total_bytes = state.total_bytes + byte_size(frame.payload)
    byte_rate = frame.sample_rate * frame.channels * 2
    duration_within_limit? = total_bytes * 1_000 <= state.maximum_duration_ms * byte_rate

    if total_bytes <= state.maximum_bytes and duration_within_limit? do
      :ok
    else
      {:error, :asset_too_large}
    end
  end

  defp validate_finish(turn, callback, state) do
    if turn == state.correlation_id and callback == state.upstream_callback and
         state.total_bytes > 0 do
      :ok
    else
      {:error, :wrong_turn}
    end
  end

  defp media_format(frame) do
    %{
      byte_order: frame.byte_order,
      channels: frame.channels,
      codec: frame.codec,
      sample_rate: frame.sample_rate
    }
  end

  defp cache(state) do
    format = state.format
    byte_rate = format.sample_rate * format.channels * 2

    asset = %Asset{
      byte_order: format.byte_order,
      channels: format.channels,
      codec: format.codec,
      duration_ms: div(state.total_bytes * 1_000, byte_rate),
      payload: state.chunks |> Enum.reverse() |> IO.iodata_to_binary(),
      sample_rate: format.sample_rate
    }

    try do
      _result = AssetCache.put(state.cache, state.cache_key, asset)
      :ok
    catch
      :exit, _reason -> :ok
    end
  end

  defp forward_playback(status, state) do
    if is_pid(state.upstream_callback) do
      send(
        state.upstream_callback,
        {:vxpipe_audio_playback, self(), state.correlation_id, status}
      )
    end
  end
end
