defmodule Vxpipe.Console.Diagnostics.OpeningAudioPanel do
  @moduledoc false

  use Phoenix.Component

  attr :metrics, :map, required: true

  def render(assigns) do
    assigns = assign(assigns, :rows, sorted_entries(assigns.metrics.stops))

    ~H"""
    <section id="opening-audio-metrics" class="instrument-section" aria-labelledby="opening-audio-heading">
      <div class="section-heading">
        <h2 id="opening-audio-heading">Opening audio</h2>
        <span class="section-note">Caller gate</span>
      </div>

      <%= if @rows == [] do %>
        <div class="empty-state">No opening playback observed.</div>
      <% else %>
        <table class="ledger">
          <caption class="visually-hidden">Opening audio outcomes and playback timing</caption>
          <thead><tr><th>Source</th><th>Outcome</th><th>Latest</th><th>Count</th></tr></thead>
          <tbody>
            <tr
              :for={{{source, outcome}, stats} <- @rows}
              id={series_id(source, outcome)}
            >
              <td><span class="series-name">{humanize(source)}</span></td>
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

  defp outcome_class(:completed), do: "outcome--ok"
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

  defp series_id(source, outcome) do
    "opening-audio-#{slug(source)}-#{slug(outcome)}"
  end

  defp slug(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp humanize(:file_url), do: "File URL"

  defp humanize(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
