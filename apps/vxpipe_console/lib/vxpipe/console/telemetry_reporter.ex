defmodule Vxpipe.Console.TelemetryReporter do
  @moduledoc """
  Collects bounded, payload-free operational aggregates for Console diagnostics.

  Telemetry handlers execute in the process emitting an event, so the handler only
  performs atomic admission and sends an admitted event to this process. The
  reporter keeps finite aggregates rather than event history.
  """

  use GenServer

  alias Vxpipe.Console.TelemetryReporter.MCPProjection
  alias Vxpipe.Console.TelemetryReporter.OpeningAudioProjection
  alias Vxpipe.Console.TelemetryReporter.StartupProjection
  alias Vxpipe.Console.TelemetryReporter.TransferProjection

  @events [
    [:vxpipe, :gateway, :http, :request, :stop],
    [:vxpipe, :call_engine, :model, :first_token],
    [:vxpipe, :call_engine, :model, :request, :stop],
    [:vxpipe, :call_engine, :tts, :first_audio],
    [:vxpipe, :call_engine, :transfer, :phase, :stop],
    [:vxpipe, :call_engine, :provider, :failure],
    [:vxpipe, :call_engine, :background_tool, :admission],
    [:vxpipe, :call_engine, :background_tool, :stop],
    [:vxpipe, :call_engine, :background_tool, :handoff],
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
  @background_admission_outcomes [
    :accepted,
    :saturated,
    :start_failed,
    :unavailable,
    :invalid_tool
  ]
  @background_stop_outcomes [:ok, :failed, :unknown, :terminated]
  @background_handoff_outcomes [:queued, :duplicate, :overflow, :consumed]
  @transfer_phases [:audience, :prepare, :release, :recover, :briefing, :acceptance, :cue]
  @transfer_outcomes [:ok, :failed, :timeout, :terminated, :cancelled]

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
  def events,
    do:
      @events ++
        MCPProjection.events() ++
        OpeningAudioProjection.events() ++
        StartupProjection.events() ++
        TransferProjection.events()

  @doc false
  def handle_event(event, measurements, metadata, config) do
    pending_count = :atomics.add_get(config.pending, 1, 1)

    if pending_count <= config.max_pending_events do
      {measurements, metadata} = sanitize_event(event, measurements, metadata)
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
        events(),
        &__MODULE__.handle_event/4,
        handler_config
      )

    {:ok,
     %{
       dropped: dropped,
       handler_id: handler_id,
       background_tool_admissions: %{},
       background_tool_handoffs: %{},
       background_tool_mailbox_pressure: nil,
       background_tool_reservation_pressure: nil,
       background_tool_stops: %{},
       http_requests: %{},
       last_event_at: nil,
       model_first_token: %{},
       model_requests: %{},
       mcp: MCPProjection.new(),
       opening_audio: OpeningAudioProjection.new(),
       startup: StartupProjection.new(),
       transfer_observations: TransferProjection.new(),
       pending: pending,
       provider_failures: %{},
       received_events: 0,
       runtime: nil,
       runtime_sampled_at: nil,
       tts_first_audio: %{},
       transfer_phases: %{}
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      background_tools: %{
        admissions: state.background_tool_admissions,
        handoffs: state.background_tool_handoffs,
        mailbox_pressure: state.background_tool_mailbox_pressure,
        reservation_pressure: state.background_tool_reservation_pressure,
        stops: state.background_tool_stops
      },
      dropped_events: :atomics.get(state.dropped, 1),
      http: %{requests: state.http_requests},
      last_event_age_ms: age_ms(state.last_event_at),
      model: %{
        first_token: state.model_first_token,
        requests: state.model_requests
      },
      mcp: state.mcp,
      opening_audio: state.opening_audio,
      startup: state.startup,
      provider_failures: state.provider_failures,
      received_events: state.received_events,
      runtime: runtime_snapshot(state.runtime, state.runtime_sampled_at),
      tts: %{first_audio: state.tts_first_audio},
      transfers: Map.put(state.transfer_observations, :phases, state.transfer_phases)
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
         [:vxpipe, :call_engine, :background_tool, :admission],
         %{count: count, reserved: reserved, limit: limit},
         metadata,
         state
       )
       when is_integer(count) and count > 0 and is_integer(reserved) and reserved >= 0 and
              is_integer(limit) and limit >= 0 do
    outcome = normalize(metadata, :outcome, @background_admission_outcomes, :unavailable)

    state
    |> update_in([:background_tool_admissions], fn outcomes ->
      Map.update(outcomes, outcome, count, &(&1 + count))
    end)
    |> Map.put(:background_tool_reservation_pressure, %{reserved: reserved, limit: limit})
  end

  defp project(
         [:vxpipe, :call_engine, :background_tool, :stop],
         %{count: 1, duration: duration},
         metadata,
         state
       )
       when is_integer(duration) and duration >= 0 do
    outcome = normalize(metadata, :outcome, @background_stop_outcomes, :failed)

    update_in(state.background_tool_stops, fn outcomes ->
      update_duration(outcomes, outcome, duration)
    end)
  end

  defp project(
         [:vxpipe, :call_engine, :background_tool, :handoff],
         %{count: count, depth: depth, limit: limit},
         metadata,
         state
       )
       when is_integer(count) and count > 0 and is_integer(depth) and depth >= 0 and
              is_integer(limit) and limit > 0 do
    outcome = normalize(metadata, :outcome, @background_handoff_outcomes, :overflow)

    state
    |> update_in([:background_tool_handoffs], fn outcomes ->
      Map.update(outcomes, outcome, count, &(&1 + count))
    end)
    |> Map.put(:background_tool_mailbox_pressure, %{depth: depth, limit: limit})
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

  defp project(
         [:vxpipe, :call_engine, :transfer, :phase, :stop],
         %{count: 1, duration: duration},
         metadata,
         state
       )
       when is_integer(duration) and duration >= 0 do
    phase = normalize(metadata, :phase, @transfer_phases, :unknown)
    outcome = normalize(metadata, :outcome, @transfer_outcomes, :failed)
    update_in(state.transfer_phases, &update_duration(&1, {phase, outcome}, duration))
  end

  defp project(event, measurements, metadata, state) do
    case TransferProjection.project(event, measurements, metadata, state.transfer_observations) do
      {:ok, transfers} -> %{state | transfer_observations: transfers}
      :unhandled -> project_opening(event, measurements, metadata, state)
    end
  end

  defp project_opening(event, measurements, metadata, state) do
    case OpeningAudioProjection.project(event, measurements, metadata, state.opening_audio) do
      {:ok, opening_audio} -> %{state | opening_audio: opening_audio}
      :unhandled -> project_startup(event, measurements, metadata, state)
    end
  end

  defp project_startup(event, measurements, metadata, state) do
    case StartupProjection.project(event, measurements, metadata, state.startup) do
      {:ok, startup} -> %{state | startup: startup}
      :unhandled -> project_mcp(event, measurements, metadata, state)
    end
  end

  defp project_mcp(event, measurements, metadata, state) do
    case MCPProjection.project(event, measurements, metadata, state.mcp) do
      {:ok, mcp} -> %{state | mcp: mcp}
      :unhandled -> state
    end
  end

  defp sanitize_event(
         [:vxpipe, :gateway, :http, :request, :stop],
         measurements,
         metadata
       ) do
    {
      sanitize_duration(measurements),
      %{
        operation: normalize(metadata, :operation, @gateway_operations, :unknown),
        outcome: normalize(metadata, :outcome, @gateway_outcomes, :unknown)
      }
    }
  end

  defp sanitize_event(
         [:vxpipe, :call_engine, :model, :first_token],
         measurements,
         metadata
       ) do
    {sanitize_duration(measurements), %{provider: normalize_provider(metadata)}}
  end

  defp sanitize_event(
         [:vxpipe, :call_engine, :model, :request, :stop],
         measurements,
         metadata
       ) do
    {
      sanitize_duration(measurements),
      %{
        provider: normalize_provider(metadata),
        outcome: normalize(metadata, :outcome, @model_outcomes, :invalid_response),
        first_output: normalize(metadata, :first_output, [:observed, :missing], :missing)
      }
    }
  end

  defp sanitize_event(
         [:vxpipe, :call_engine, :tts, :first_audio],
         measurements,
         metadata
       ) do
    {sanitize_duration(measurements), %{provider: normalize_provider(metadata)}}
  end

  defp sanitize_event(
         [:vxpipe, :call_engine, :provider, :failure],
         measurements,
         metadata
       ) do
    {
      sanitize_count(measurements),
      %{
        capability: normalize(metadata, :capability, [:model, :stt, :tts], :other),
        provider: normalize_provider(metadata),
        category: normalize(metadata, :category, @failure_categories, :unknown)
      }
    }
  end

  defp sanitize_event(
         [:vxpipe, :call_engine, :background_tool, :admission],
         measurements,
         metadata
       ) do
    {
      sanitize_reservation_pressure(measurements),
      %{
        outcome: normalize(metadata, :outcome, @background_admission_outcomes, :unavailable)
      }
    }
  end

  defp sanitize_event(
         [:vxpipe, :call_engine, :background_tool, :stop],
         measurements,
         metadata
       ) do
    {
      sanitize_counted_duration(measurements),
      %{outcome: normalize(metadata, :outcome, @background_stop_outcomes, :failed)}
    }
  end

  defp sanitize_event(
         [:vxpipe, :call_engine, :background_tool, :handoff],
         measurements,
         metadata
       ) do
    {
      sanitize_mailbox_pressure(measurements),
      %{outcome: normalize(metadata, :outcome, @background_handoff_outcomes, :overflow)}
    }
  end

  defp sanitize_event(
         [:vxpipe, :call_engine, :runtime, :sample],
         measurements,
         _metadata
       ) do
    {sanitize_runtime(measurements), %{}}
  end

  defp sanitize_event([:vxpipe, :call_engine, :transfer, :phase, :stop], measurements, metadata) do
    {sanitize_counted_duration(measurements),
     %{
       phase: normalize(metadata, :phase, @transfer_phases, :unknown),
       outcome: normalize(metadata, :outcome, @transfer_outcomes, :failed)
     }}
  end

  defp sanitize_event(event, measurements, metadata) do
    case TransferProjection.sanitize(event, measurements, metadata) do
      {:ok, measurements, metadata} -> {measurements, metadata}
      :unhandled -> sanitize_opening(event, measurements, metadata)
    end
  end

  defp sanitize_opening(event, measurements, metadata) do
    case OpeningAudioProjection.sanitize(event, measurements, metadata) do
      {:ok, measurements, metadata} -> {measurements, metadata}
      :unhandled -> sanitize_startup(event, measurements, metadata)
    end
  end

  defp sanitize_startup(event, measurements, metadata) do
    case StartupProjection.sanitize(event, measurements, metadata) do
      {:ok, measurements, metadata} -> {measurements, metadata}
      :unhandled -> sanitize_mcp(event, measurements, metadata)
    end
  end

  defp sanitize_mcp(event, measurements, metadata) do
    case MCPProjection.sanitize(event, measurements, metadata) do
      {:ok, measurements, metadata} -> {measurements, metadata}
      :unhandled -> {%{}, %{}}
    end
  end

  defp sanitize_duration(%{duration: duration}) when is_integer(duration) and duration >= 0,
    do: %{duration: duration}

  defp sanitize_duration(_measurements), do: %{}

  defp sanitize_count(%{count: count}) when is_integer(count) and count > 0,
    do: %{count: count}

  defp sanitize_count(_measurements), do: %{}

  defp sanitize_counted_duration(%{count: 1, duration: duration})
       when is_integer(duration) and duration >= 0,
       do: %{count: 1, duration: duration}

  defp sanitize_counted_duration(_measurements), do: %{}

  defp sanitize_reservation_pressure(%{count: count, reserved: reserved, limit: limit})
       when is_integer(count) and count > 0 and is_integer(reserved) and reserved >= 0 and
              is_integer(limit) and limit >= 0,
       do: %{count: count, reserved: reserved, limit: limit}

  defp sanitize_reservation_pressure(_measurements), do: %{}

  defp sanitize_mailbox_pressure(%{count: count, depth: depth, limit: limit})
       when is_integer(count) and count > 0 and is_integer(depth) and depth >= 0 and
              is_integer(limit) and limit > 0,
       do: %{count: count, depth: depth, limit: limit}

  defp sanitize_mailbox_pressure(_measurements), do: %{}

  defp sanitize_runtime(%{
         active_rooms: active_rooms,
         memory_bytes: memory_bytes,
         run_queue: run_queue
       })
       when is_integer(active_rooms) and active_rooms >= 0 and is_integer(memory_bytes) and
              memory_bytes >= 0 and is_integer(run_queue) and run_queue >= 0 do
    %{active_rooms: active_rooms, memory_bytes: memory_bytes, run_queue: run_queue}
  end

  defp sanitize_runtime(_measurements), do: %{}

  defp normalize(metadata, key, allowed, fallback) when is_map(metadata) do
    value = Map.get(metadata, key)

    if value in allowed, do: value, else: fallback
  end

  defp normalize(_metadata, _key, _allowed, fallback), do: fallback

  defp normalize_provider(metadata) do
    normalize(metadata, :provider, [:req_llm, :deepgram, :local_fixture, :morse, :other], :other)
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
