defmodule Vxpipe.Console.DiagnosticsLive do
  @moduledoc false

  use Phoenix.LiveView, layout: false

  alias Vxpipe.CallEngine.Diagnostics.ModelFixture
  alias Vxpipe.Console.Diagnostics.MCPPanel
  alias Vxpipe.Console.Diagnostics.OpeningAudioPanel
  alias Vxpipe.Console.TelemetryReporter

  @refresh_interval_ms 1_000
  @snapshot_timeout_ms 250
  @stale_after_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)
    reporter = Keyword.get(diagnostics, :reporter, TelemetryReporter)

    socket =
      socket
      |> assign(:reporter, reporter)
      |> assign(:model_fixture, Keyword.get(diagnostics, :model_fixture))
      |> refresh_snapshot()
      |> refresh_fixture()

    if connected?(socket), do: schedule_refresh()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, socket |> refresh_snapshot() |> refresh_fixture()}
  end

  @impl true
  def handle_event(
        "arm-model-fixture",
        _params,
        %{assigns: %{model_fixture: nil}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("arm-model-fixture", %{"scenario" => scenario}, socket) do
    case fixture_scenario(scenario) do
      {:ok, scenario} -> _ = ModelFixture.arm(socket.assigns.model_fixture, scenario)
      :error -> :ok
    end

    {:noreply, refresh_fixture(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="diagnostics-board" class="diagnostics-shell">
      <header class="topbar">
        <div class="brand-lockup">
          <h1>Vxpipe <span>Diagnostics</span></h1>
          <p>Live, bounded observations from the gateway and call engine.</p>
        </div>
        <nav class="topnav" aria-label="Diagnostics navigation">
          <a class="nav-link" href="/pipecat-console">Voice console</a>
          <a class="nav-link nav-link--primary" href="/diagnostics/system">System dashboard</a>
        </nav>
      </header>

      <%= if @reporter_status == :available do %>
        <.collection_strip snapshot={@snapshot} />
        <div class="workbench">
          <div class="workbench-column">
            <.runtime_panel runtime={@snapshot.runtime} />
            <.fixture_panel :if={@fixture_status} status={@fixture_status} />
          </div>

          <div class="workbench-column">
            <.http_panel requests={@snapshot.http.requests} />
            <.model_panel
              first_token={@snapshot.model.first_token}
              requests={@snapshot.model.requests}
            />
            <MCPPanel.render metrics={@snapshot.mcp} />
          </div>

          <div class="workbench-column">
            <.speech_panel first_audio={@snapshot.tts.first_audio} />
            <OpeningAudioPanel.render metrics={@snapshot.opening_audio} />
            <.background_tools_panel metrics={@snapshot.background_tools} />
            <.failures_panel failures={@snapshot.provider_failures} />
          </div>
        </div>
      <% else %>
        <.unavailable_strip />
        <section id="diagnostics-unavailable" class="unavailable-panel" aria-labelledby="unavailable-title">
          <h2 id="unavailable-title">Reporter offline</h2>
          <p>
            The bounded diagnostics collector could not be reached. Call traffic is unaffected;
            check the Console supervision tree, then reload this page.
          </p>
        </section>
      <% end %>
    </main>
    """
  end

  attr :status, :map, required: true

  defp fixture_panel(assigns) do
    ~H"""
    <section id="model-fixture-controls" class="instrument-section" aria-labelledby="fixture-heading">
      <div class="section-heading">
        <h2 id="fixture-heading">Local model fixture</h2>
        <span class="section-note">One request</span>
      </div>
      <p class="fixture-status">
        Next request: <strong>{scenario_label(@status.next_scenario)}</strong>
      </p>
      <div class="fixture-actions" role="group" aria-label="Arm the next local model result">
        <button
          :for={scenario <- [:success, :delay, :failure, :missing]}
          type="button"
          phx-click="arm-model-fixture"
          phx-value-scenario={scenario}
          aria-pressed={to_string(@status.next_scenario == scenario)}
        >
          {scenario_label(scenario)}
        </button>
      </div>
      <p class="fixture-detail">
        Delay waits {format_integer(@status.delay_ms)} ms. Each selection resets to
        {scenario_label(@status.default_scenario)} after the next model request.
      </p>
    </section>
    """
  end

  attr :snapshot, :map, required: true

  defp collection_strip(assigns) do
    assigns =
      assigns
      |> assign(:state, collection_state(assigns.snapshot))
      |> assign(:label, collection_label(assigns.snapshot))

    ~H"""
    <section class="collection-strip" data-state={@state} aria-labelledby="collection-state">
      <div class="collection-primary">
        <span class="state-marker" aria-hidden="true"></span>
        <div>
          <h2 id="collection-state">{@label}</h2>
          <p>{collection_detail(@snapshot)}</p>
        </div>
      </div>
      <div class="collection-readout">
        <span class="readout-label">Observed</span>
        <span class="readout-value">{format_integer(@snapshot.received_events)}</span>
      </div>
      <div class="collection-readout">
        <span class="readout-label">Dropped</span>
        <span class={["readout-value", @snapshot.dropped_events > 0 && "outcome--fault"]}>
          {format_integer(@snapshot.dropped_events)}
        </span>
      </div>
      <div class="collection-readout">
        <span class="readout-label">Last signal</span>
        <span class="readout-value">{format_age(@snapshot.last_event_age_ms)}</span>
      </div>
    </section>
    """
  end

  defp unavailable_strip(assigns) do
    ~H"""
    <section class="collection-strip" data-state="unavailable" aria-labelledby="collection-state">
      <div class="collection-primary">
        <span class="state-marker" aria-hidden="true"></span>
        <div>
          <h2 id="collection-state">Collector unavailable</h2>
          <p>No diagnostic snapshot is available.</p>
        </div>
      </div>
      <div class="collection-readout">
        <span class="readout-label">Observed</span>
        <span class="readout-value">—</span>
      </div>
      <div class="collection-readout">
        <span class="readout-label">Dropped</span>
        <span class="readout-value">—</span>
      </div>
      <div class="collection-readout">
        <span class="readout-label">Last signal</span>
        <span class="readout-value">Unavailable</span>
      </div>
    </section>
    """
  end

  attr :runtime, :map, default: nil

  defp runtime_panel(assigns) do
    ~H"""
    <section class="instrument-section" aria-labelledby="runtime-heading">
      <div class="section-heading">
        <h2 id="runtime-heading">Runtime</h2>
        <span class="section-note">Latest sample</span>
      </div>

      <%= if @runtime do %>
        <div class="runtime-primary">
          <span
            id="metric-active-rooms"
            class="runtime-number"
            data-metric="active-rooms"
            phx-hook="MetricPulse"
          >
            {@runtime.active_rooms}
          </span>
          <span class="runtime-caption">active rooms</span>
        </div>
        <dl class="runtime-grid">
          <div>
            <dt>BEAM memory</dt>
            <dd id="metric-memory" data-metric="memory" phx-hook="MetricPulse">
              {format_memory(@runtime.memory_bytes)}
            </dd>
          </div>
          <div>
            <dt>Run queue</dt>
            <dd id="metric-run-queue" data-metric="run-queue" phx-hook="MetricPulse">
              {@runtime.run_queue}
            </dd>
          </div>
          <div>
            <dt>Sample age</dt>
            <dd>{format_age(@runtime.age_ms)}</dd>
          </div>
        </dl>
        <div class="state-line" data-state={runtime_state(@runtime.age_ms)}>
          {runtime_label(@runtime.age_ms)}
        </div>
      <% else %>
        <div class="empty-state">Waiting for the first engine runtime sample.</div>
        <div class="state-line" data-state="missing">No runtime sample</div>
      <% end %>
    </section>
    """
  end

  attr :requests, :map, required: true

  defp http_panel(assigns) do
    assigns = assign(assigns, :rows, sorted_entries(assigns.requests))

    ~H"""
    <section class="instrument-section" aria-labelledby="http-heading">
      <div class="section-heading">
        <h2 id="http-heading">Gateway requests</h2>
        <span class="section-note">End-to-end Plug time</span>
      </div>

      <%= if @rows == [] do %>
        <div class="empty-state">No gateway request observations yet.</div>
      <% else %>
        <table class="ledger">
          <caption class="visually-hidden">Gateway request timing by operation and outcome</caption>
          <thead>
            <tr><th>Operation</th><th>Outcome</th><th>Latest</th><th>Average</th></tr>
          </thead>
          <tbody>
            <tr
              :for={{{operation, outcome}, stats} <- @rows}
              id={series_id("http", [operation, outcome])}
            >
              <td><span class="series-name">{humanize(operation)}</span></td>
              <td class={outcome_class(outcome)}>{humanize(outcome)}</td>
              <td class="measure">{format_duration(stats.latest_us)}</td>
              <td class="measure">{format_duration(average_duration(stats))}</td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </section>
    """
  end

  attr :first_token, :map, required: true
  attr :requests, :map, required: true

  defp model_panel(assigns) do
    assigns =
      assigns
      |> assign(:timing_rows, sorted_entries(assigns.first_token))
      |> assign(:request_rows, sorted_entries(assigns.requests))

    ~H"""
    <section class="instrument-section" aria-labelledby="model-heading">
      <div class="section-heading">
        <h2 id="model-heading">Model</h2>
        <span class="section-note">Provider boundary</span>
      </div>

      <%= if @timing_rows == [] do %>
        <div class="empty-state">No first-output timing observed.</div>
      <% else %>
        <table class="ledger">
          <caption class="visually-hidden">Model time to first output by provider</caption>
          <thead><tr><th>Provider</th><th>Latest</th><th>Average</th></tr></thead>
          <tbody>
            <tr :for={{provider, stats} <- @timing_rows} id={series_id("model-first-token", [provider])}>
              <td><span class="series-name">{humanize(provider)}</span></td>
              <td class="measure">{format_duration(stats.latest_us)}</td>
              <td class="measure">{format_duration(average_duration(stats))}</td>
            </tr>
          </tbody>
        </table>
      <% end %>

      <div class="section-heading section-heading--spaced">
        <h3>Request outcomes</h3>
        <span class="section-note">Terminal results</span>
      </div>

      <%= if @request_rows == [] do %>
        <div class="empty-state">No terminal model requests observed.</div>
      <% else %>
        <table class="ledger">
          <caption class="visually-hidden">Terminal model request outcomes</caption>
          <thead><tr><th>Provider</th><th>Outcome</th><th>First output</th><th>Count</th></tr></thead>
          <tbody>
            <tr
              :for={{{provider, outcome, first_output}, count} <- @request_rows}
              id={series_id("model-request", [provider, outcome, first_output])}
            >
              <td><span class="series-name">{humanize(provider)}</span></td>
              <td class={outcome_class(outcome)}>{humanize(outcome)}</td>
              <td>{first_output_label(first_output)}</td>
              <td class="measure">{format_integer(count)}</td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </section>
    """
  end

  attr :first_audio, :map, required: true

  defp speech_panel(assigns) do
    assigns = assign(assigns, :rows, sorted_entries(assigns.first_audio))

    ~H"""
    <section class="instrument-section" aria-labelledby="speech-heading">
      <div class="section-heading">
        <h2 id="speech-heading">Speech output</h2>
        <span class="section-note">First provider audio</span>
      </div>

      <%= if @rows == [] do %>
        <div class="empty-state">No synthesized-audio timing observed.</div>
      <% else %>
        <table class="ledger">
          <caption class="visually-hidden">Text-to-speech time to first audio by provider</caption>
          <thead><tr><th>Provider</th><th>Latest</th><th>Average</th></tr></thead>
          <tbody>
            <tr :for={{provider, stats} <- @rows} id={series_id("tts-first-audio", [provider])}>
              <td><span class="series-name">{humanize(provider)}</span></td>
              <td class="measure">{format_duration(stats.latest_us)}</td>
              <td class="measure">{format_duration(average_duration(stats))}</td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </section>
    """
  end

  attr :metrics, :map, required: true

  defp background_tools_panel(assigns) do
    assigns =
      assigns
      |> assign(:admission_rows, sorted_entries(assigns.metrics.admissions))
      |> assign(:handoff_rows, sorted_entries(assigns.metrics.handoffs))
      |> assign(:stop_rows, sorted_entries(assigns.metrics.stops))

    ~H"""
    <section id="background-tool-metrics" class="instrument-section" aria-labelledby="background-tools-heading">
      <div class="section-heading">
        <h2 id="background-tools-heading">Background tools</h2>
        <span class="section-note">Bounded lifecycle</span>
      </div>

      <dl class="runtime-grid">
        <div>
          <dt>Reservations at admission</dt>
          <dd id="background-reservation-pressure">
            {format_pressure(@metrics.reservation_pressure, :reserved)}
          </dd>
        </div>
        <div>
          <dt>Mailbox at handoff</dt>
          <dd id="background-mailbox-pressure">
            {format_pressure(@metrics.mailbox_pressure, :depth)}
          </dd>
        </div>
      </dl>

      <div class="section-heading section-heading--spaced">
        <h3>Admissions</h3>
        <span class="section-note">Submission boundary</span>
      </div>

      <%= if @admission_rows == [] do %>
        <div class="empty-state">No background work submitted.</div>
      <% else %>
        <table class="ledger">
          <caption class="visually-hidden">Background tool admission outcomes</caption>
          <thead><tr><th>Outcome</th><th>Count</th></tr></thead>
          <tbody>
            <tr
              :for={{outcome, count} <- @admission_rows}
              id={series_id("background-admission", [outcome])}
            >
              <td class={outcome_class(outcome)}>{humanize(outcome)}</td>
              <td class="measure">{format_integer(count)}</td>
            </tr>
          </tbody>
        </table>
      <% end %>

      <div class="section-heading section-heading--spaced">
        <h3>Worker outcomes</h3>
        <span class="section-note">Terminal duration</span>
      </div>

      <%= if @stop_rows == [] do %>
        <div class="empty-state">No background worker has stopped.</div>
      <% else %>
        <table class="ledger">
          <caption class="visually-hidden">Background worker terminal outcomes and timing</caption>
          <thead><tr><th>Outcome</th><th>Latest</th><th>Count</th></tr></thead>
          <tbody>
            <tr
              :for={{outcome, stats} <- @stop_rows}
              id={series_id("background-worker", [outcome])}
            >
              <td class={outcome_class(outcome)}>{humanize(outcome)}</td>
              <td class="measure">{format_duration(stats.latest_us)}</td>
              <td class="measure">{format_integer(stats.count)}</td>
            </tr>
          </tbody>
        </table>
      <% end %>

      <div class="section-heading section-heading--spaced">
        <h3>Completion handoff</h3>
        <span class="section-note">Coordinator mailbox</span>
      </div>

      <%= if @handoff_rows == [] do %>
        <div class="empty-state">No completion handoff observed.</div>
      <% else %>
        <table class="ledger">
          <caption class="visually-hidden">Background completion handoff outcomes</caption>
          <thead><tr><th>Outcome</th><th>Count</th></tr></thead>
          <tbody>
            <tr
              :for={{outcome, count} <- @handoff_rows}
              id={series_id("background-handoff", [outcome])}
            >
              <td class={outcome_class(outcome)}>{humanize(outcome)}</td>
              <td class="measure">{format_integer(count)}</td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </section>
    """
  end

  attr :failures, :map, required: true

  defp failures_panel(assigns) do
    assigns = assign(assigns, :rows, sorted_entries(assigns.failures))

    ~H"""
    <section class="instrument-section" aria-labelledby="failures-heading">
      <div class="section-heading">
        <h2 id="failures-heading">Provider failures</h2>
        <span class="section-note">Safe categories</span>
      </div>

      <%= if @rows == [] do %>
        <div class="empty-state">No provider failures observed.</div>
      <% else %>
        <table class="ledger">
          <caption class="visually-hidden">Provider failure counts by capability and category</caption>
          <thead><tr><th>Capability</th><th>Provider / category</th><th>Count</th></tr></thead>
          <tbody>
            <tr
              :for={{{capability, provider, category}, count} <- @rows}
              id={series_id("provider-failure", [capability, provider, category])}
            >
              <td><span class="series-name">{humanize(capability)}</span></td>
              <td>
                <span class="outcome--fault">{humanize(category)}</span>
                <span class="series-detail">{humanize(provider)}</span>
              </td>
              <td class="measure outcome--fault">{format_integer(count)}</td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </section>
    """
  end

  defp refresh_snapshot(socket) do
    case read_snapshot(socket.assigns.reporter) do
      {:ok, snapshot} -> assign(socket, reporter_status: :available, snapshot: snapshot)
      :unavailable -> assign(socket, reporter_status: :unavailable, snapshot: nil)
    end
  end

  defp refresh_fixture(%{assigns: %{model_fixture: nil}} = socket) do
    assign(socket, :fixture_status, nil)
  end

  defp refresh_fixture(socket) do
    case ModelFixture.status(socket.assigns.model_fixture) do
      %{next_scenario: _scenario} = status -> assign(socket, :fixture_status, status)
      {:error, :unavailable} -> assign(socket, :fixture_status, nil)
    end
  end

  defp read_snapshot(reporter) do
    {:ok, TelemetryReporter.snapshot(reporter, @snapshot_timeout_ms)}
  catch
    :exit, _reason -> :unavailable
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
  end

  defp collection_state(%{dropped_events: dropped}) when dropped > 0, do: "degraded"
  defp collection_state(%{last_event_age_ms: nil}), do: "waiting"

  defp collection_state(%{last_event_age_ms: age_ms}) when age_ms > @stale_after_ms,
    do: "degraded"

  defp collection_state(_snapshot), do: "healthy"

  defp collection_label(%{dropped_events: dropped}) when dropped > 0, do: "Collecting with drops"
  defp collection_label(%{last_event_age_ms: nil}), do: "Waiting for signals"

  defp collection_label(%{last_event_age_ms: age_ms}) when age_ms > @stale_after_ms,
    do: "Collection stale"

  defp collection_label(_snapshot), do: "Collecting"

  defp collection_detail(%{dropped_events: dropped}) when dropped > 0 do
    "#{format_integer(dropped)} observations dropped at the pending-work limit."
  end

  defp collection_detail(%{last_event_age_ms: nil}), do: "No observations received yet."

  defp collection_detail(%{last_event_age_ms: age_ms}) when age_ms > @stale_after_ms do
    "Last observation arrived #{format_age(age_ms)}."
  end

  defp collection_detail(_snapshot), do: "Reporter is current and accepting bounded work."

  defp runtime_state(age_ms) when age_ms > @stale_after_ms, do: "stale"
  defp runtime_state(_age_ms), do: "fresh"

  defp runtime_label(age_ms) when age_ms > @stale_after_ms, do: "Runtime sample is stale"
  defp runtime_label(_age_ms), do: "Runtime sample is current"

  defp outcome_class(outcome) when outcome in [:ok, :accepted, :queued, :consumed],
    do: "outcome--ok"

  defp outcome_class(_outcome), do: "outcome--fault"

  defp first_output_label(:observed), do: "First output observed"
  defp first_output_label(:missing), do: "No first output"

  defp fixture_scenario("success"), do: {:ok, :success}
  defp fixture_scenario("delay"), do: {:ok, :delay}
  defp fixture_scenario("failure"), do: {:ok, :failure}
  defp fixture_scenario("missing"), do: {:ok, :missing}
  defp fixture_scenario(_scenario), do: :error

  defp scenario_label(:success), do: "Success"
  defp scenario_label(:delay), do: "Delay"
  defp scenario_label(:failure), do: "Failure"
  defp scenario_label(:missing), do: "No output"

  defp average_duration(%{count: count, total_us: total_us}), do: div(total_us, count)

  defp format_duration(microseconds) when microseconds < 1_000 do
    "#{microseconds} µs"
  end

  defp format_duration(microseconds) do
    milliseconds = microseconds / 1_000
    :erlang.float_to_binary(milliseconds, decimals: 1) <> " ms"
  end

  defp format_memory(bytes) do
    mebibytes = bytes / 1_048_576
    :erlang.float_to_binary(mebibytes, decimals: 1) <> " MiB"
  end

  defp format_pressure(nil, _key), do: "No observation"

  defp format_pressure(pressure, key) do
    "#{format_integer(Map.fetch!(pressure, key))} / #{format_integer(pressure.limit)}"
  end

  defp format_age(nil), do: "No signals"
  defp format_age(age_ms) when age_ms < 1_000, do: "< 1 s ago"
  defp format_age(age_ms), do: "#{div(age_ms, 1_000)} s ago"

  defp format_integer(integer), do: Integer.to_string(integer)

  defp sorted_entries(map) do
    map
    |> Map.to_list()
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp series_id(prefix, dimensions) do
    suffix = dimensions |> Enum.map_join("-", &slug/1)
    "#{prefix}-#{suffix}"
  end

  defp slug(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp humanize(:req_llm), do: "Req LLM"
  defp humanize(:local_fixture), do: "Local fixture"
  defp humanize(:stt), do: "STT"
  defp humanize(:tts), do: "TTS"

  defp humanize(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
