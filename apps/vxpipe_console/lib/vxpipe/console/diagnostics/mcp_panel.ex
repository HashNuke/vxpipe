defmodule Vxpipe.Console.Diagnostics.MCPPanel do
  @moduledoc false

  use Phoenix.Component

  attr :metrics, :map, required: true

  def render(assigns) do
    assigns =
      assigns
      |> assign(:connection_rows, sorted_entries(assigns.metrics.connections))
      |> assign(:request_rows, sorted_entries(assigns.metrics.requests))

    ~H"""
    <section id="mcp-metrics" class="instrument-section" aria-labelledby="mcp-heading">
      <div class="section-heading">
        <h2 id="mcp-heading">Remote MCP</h2>
        <span class="section-note">Client boundary</span>
      </div>

      <dl class="runtime-grid">
        <div>
          <dt>Active connections</dt>
          <dd id="mcp-active-connections">{format_connections(@metrics.active_connections)}</dd>
        </div>
        <div>
          <dt>Queue pressure</dt>
          <dd id="mcp-queue-pressure">{queue_pressure_label(@metrics.queue_pressure)}</dd>
        </div>
      </dl>

      <div class="section-heading section-heading--spaced">
        <h3>Connection lifecycle</h3>
        <span class="section-note">Terminal duration</span>
      </div>

      <%= if @connection_rows == [] do %>
        <div class="empty-state">No MCP connection activity observed.</div>
      <% else %>
        <table class="ledger">
          <caption class="visually-hidden">MCP connection lifecycle outcomes and timing</caption>
          <thead><tr><th>Operation</th><th>Outcome</th><th>Latest</th><th>Count</th></tr></thead>
          <tbody>
            <tr
              :for={{{operation, outcome}, stats} <- @connection_rows}
              id={series_id("mcp-connection", [operation, outcome])}
            >
              <td><span class="series-name">{humanize(operation)}</span></td>
              <td class={outcome_class(outcome)}>{humanize(outcome)}</td>
              <td class="measure">{format_duration(stats.latest_us)}</td>
              <td class="measure">{Integer.to_string(stats.count)}</td>
            </tr>
          </tbody>
        </table>
      <% end %>

      <div class="section-heading section-heading--spaced">
        <h3>Requests</h3>
        <span class="section-note">Discovery and invocation</span>
      </div>

      <%= if @request_rows == [] do %>
        <div class="empty-state">No MCP requests observed.</div>
      <% else %>
        <table class="ledger">
          <caption class="visually-hidden">MCP request outcomes and timing</caption>
          <thead><tr><th>Operation</th><th>Outcome</th><th>Latest</th><th>Count</th></tr></thead>
          <tbody>
            <tr
              :for={{{operation, outcome}, stats} <- @request_rows}
              id={series_id("mcp-request", [operation, outcome])}
            >
              <td><span class="series-name">{humanize(operation)}</span></td>
              <td class={outcome_class(outcome)}>{humanize(outcome)}</td>
              <td class="measure">{format_duration(stats.latest_us)}</td>
              <td class="measure">{Integer.to_string(stats.count)}</td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </section>
    """
  end

  defp format_connections(nil), do: "No observation"
  defp format_connections(count), do: Integer.to_string(count)

  defp queue_pressure_label(:not_applicable), do: "Not applicable"

  defp outcome_class(outcome) when outcome in [:ok, :opened, :reused, :closed],
    do: "outcome--ok"

  defp outcome_class(_outcome), do: "outcome--fault"

  defp format_duration(microseconds) when microseconds < 1_000, do: "#{microseconds} µs"

  defp format_duration(microseconds) do
    milliseconds = microseconds / 1_000
    :erlang.float_to_binary(milliseconds, decimals: 1) <> " ms"
  end

  defp sorted_entries(map) do
    map
    |> Map.to_list()
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp series_id(prefix, dimensions) do
    suffix = Enum.map_join(dimensions, "-", &slug/1)
    "#{prefix}-#{suffix}"
  end

  defp slug(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp humanize(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
