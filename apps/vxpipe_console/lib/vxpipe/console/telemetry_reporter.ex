defmodule Vxpipe.Console.TelemetryReporter do
  @moduledoc """
  Collects bounded, payload-free operational aggregates for Console diagnostics.

  Telemetry handlers execute in the process emitting an event, so the handler only
  performs atomic admission and sends an admitted event to this process. The
  reporter keeps finite aggregates rather than event history.
  """

  use GenServer

  @events [
    [:vxpipe, :gateway, :http, :request, :stop],
    [:vxpipe, :call_engine, :model, :first_token],
    [:vxpipe, :call_engine, :model, :request, :stop],
    [:vxpipe, :call_engine, :tts, :first_audio],
    [:vxpipe, :call_engine, :provider, :failure],
    [:vxpipe, :call_engine, :runtime, :sample]
  ]

  @gateway_operations [
    :cors_preflight,
    :health_check,
    :room_create,
    :session_create,
    :rtvi_offer,
    :rtvi_candidates,
    :unknown
  ]
  @gateway_outcomes [:ok, :client_error, :server_error, :exception, :unknown]
  @model_outcomes [:ok, :unavailable, :timeout, :invalid_response, :cancelled]
  @failure_categories [:unavailable, :timeout, :invalid_response, :output_failure, :unknown]

  @type option ::
          {:handler_id, term()}
          | {:max_pending_events, pos_integer()}
          | {:name, GenServer.name() | nil}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(options) do
    case Keyword.get(options, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, options)
      name -> GenServer.start_link(__MODULE__, options, name: name)
    end
  end

  @spec snapshot(GenServer.server(), timeout()) :: map()
  def snapshot(server \\ __MODULE__, timeout \\ 1_000) do
    GenServer.call(server, :snapshot, timeout)
  end

  @spec events() :: [nonempty_list(atom())]
  def events, do: @events

  @doc false
  def handle_event(event, measurements, metadata, config) do
    pending_count = :atomics.add_get(config.pending, 1, 1)

    if pending_count <= config.max_pending_events do
      send(config.reporter, {:vxpipe_telemetry_event, event, measurements, metadata})
    else
      :atomics.add_get(config.pending, 1, -1)
      :atomics.add_get(config.dropped, 1, 1)
    end

    :ok
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    handler_id = Keyword.get(options, :handler_id, {__MODULE__, :events})
    max_pending_events = Keyword.fetch!(options, :max_pending_events)

    if not is_integer(max_pending_events) or max_pending_events <= 0 do
      raise ArgumentError, "max_pending_events must be a positive integer"
    end

    pending = :atomics.new(1, [])
    dropped = :atomics.new(1, [])

    handler_config = %{
      dropped: dropped,
      max_pending_events: max_pending_events,
      pending: pending,
      reporter: self()
    }

    :telemetry.detach(handler_id)

    :ok =
      :telemetry.attach_many(
        handler_id,
        @events,
        &__MODULE__.handle_event/4,
        handler_config
      )

    {:ok,
     %{
       dropped: dropped,
       handler_id: handler_id,
       http_requests: %{},
       last_event_at: nil,
       model_first_token: %{},
       model_requests: %{},
       pending: pending,
       provider_failures: %{},
       received_events: 0,
       runtime: nil,
       runtime_sampled_at: nil,
       tts_first_audio: %{}
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      dropped_events: :atomics.get(state.dropped, 1),
      http: %{requests: state.http_requests},
      last_event_age_ms: age_ms(state.last_event_at),
      model: %{
        first_token: state.model_first_token,
        requests: state.model_requests
      },
      provider_failures: state.provider_failures,
      received_events: state.received_events,
      runtime: runtime_snapshot(state.runtime, state.runtime_sampled_at),
      tts: %{first_audio: state.tts_first_audio}
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_info({:vxpipe_telemetry_event, event, measurements, metadata}, state) do
    :atomics.add_get(state.pending, 1, -1)

    state = %{
      project(event, measurements, metadata, state)
      | last_event_at: System.monotonic_time(),
        received_events: state.received_events + 1
    }

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(state.handler_id)
    :ok
  end

  defp project(
         [:vxpipe, :gateway, :http, :request, :stop],
         %{duration: duration},
         metadata,
         state
       )
       when is_integer(duration) and duration >= 0 do
    operation = normalize(metadata, :operation, @gateway_operations, :unknown)
    outcome = normalize(metadata, :outcome, @gateway_outcomes, :unknown)

    update_in(state.http_requests, fn requests ->
      update_duration(requests, {operation, outcome}, duration)
    end)
  end

  defp project(
         [:vxpipe, :call_engine, :model, :first_token],
         %{duration: duration},
         metadata,
         state
       )
       when is_integer(duration) and duration >= 0 do
    provider = normalize_provider(metadata)

    update_in(state.model_first_token, fn timings ->
      update_duration(timings, provider, duration)
    end)
  end

  defp project(
         [:vxpipe, :call_engine, :model, :request, :stop],
         %{duration: duration},
         metadata,
         state
       )
       when is_integer(duration) and duration >= 0 do
    provider = normalize_provider(metadata)
    outcome = normalize(metadata, :outcome, @model_outcomes, :invalid_response)
    first_output = normalize(metadata, :first_output, [:observed, :missing], :missing)

    update_in(state.model_requests, fn requests ->
      Map.update(requests, {provider, outcome, first_output}, 1, &(&1 + 1))
    end)
  end

  defp project(
         [:vxpipe, :call_engine, :tts, :first_audio],
         %{duration: duration},
         metadata,
         state
       )
       when is_integer(duration) and duration >= 0 do
    provider = normalize_provider(metadata)

    update_in(state.tts_first_audio, fn timings ->
      update_duration(timings, provider, duration)
    end)
  end

  defp project(
         [:vxpipe, :call_engine, :provider, :failure],
         %{count: count},
         metadata,
         state
       )
       when is_integer(count) and count > 0 do
    capability = normalize(metadata, :capability, [:model, :stt, :tts], :other)
    provider = normalize_provider(metadata)
    category = normalize(metadata, :category, @failure_categories, :unknown)

    update_in(state.provider_failures, fn failures ->
      Map.update(failures, {capability, provider, category}, count, &(&1 + count))
    end)
  end

  defp project(
         [:vxpipe, :call_engine, :runtime, :sample],
         %{active_rooms: active_rooms, memory_bytes: memory_bytes, run_queue: run_queue},
         _metadata,
         state
       )
       when is_integer(active_rooms) and active_rooms >= 0 and is_integer(memory_bytes) and
              memory_bytes >= 0 and is_integer(run_queue) and run_queue >= 0 do
    %{
      state
      | runtime: %{
          active_rooms: active_rooms,
          memory_bytes: memory_bytes,
          run_queue: run_queue
        },
        runtime_sampled_at: System.monotonic_time()
    }
  end

  defp project(_event, _measurements, _metadata, state), do: state

  defp normalize(metadata, key, allowed, fallback) when is_map(metadata) do
    value = Map.get(metadata, key)

    if value in allowed, do: value, else: fallback
  end

  defp normalize(_metadata, _key, _allowed, fallback), do: fallback

  defp normalize_provider(metadata) do
    normalize(metadata, :provider, [:req_llm, :deepgram, :local_fixture, :other], :other)
  end

  defp update_duration(aggregates, key, native_duration) do
    duration_us = System.convert_time_unit(native_duration, :native, :microsecond)

    Map.update(
      aggregates,
      key,
      duration_stats(duration_us),
      &%{
        count: &1.count + 1,
        total_us: &1.total_us + duration_us,
        minimum_us: min(&1.minimum_us, duration_us),
        maximum_us: max(&1.maximum_us, duration_us),
        latest_us: duration_us
      }
    )
  end

  defp duration_stats(duration_us) do
    %{
      count: 1,
      total_us: duration_us,
      minimum_us: duration_us,
      maximum_us: duration_us,
      latest_us: duration_us
    }
  end

  defp runtime_snapshot(nil, _sampled_at), do: nil

  defp runtime_snapshot(runtime, sampled_at) do
    Map.put(runtime, :age_ms, age_ms(sampled_at))
  end

  defp age_ms(nil), do: nil

  defp age_ms(monotonic_time) do
    elapsed = System.monotonic_time() - monotonic_time
    max(System.convert_time_unit(elapsed, :native, :millisecond), 0)
  end
end
