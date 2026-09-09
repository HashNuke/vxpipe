defmodule Vxpipe.Console.CallInspectionDetailComponents do
  @moduledoc false

  use Phoenix.Component

  alias Vxpipe.Console.{CallInspectionFormat, CallInspectionTimeline, CallVariableDiff}

  attr :selected_id, :string, required: true
  attr :selected_event_id, :string, default: nil
  attr :list_cursor, :string, default: nil
  attr :history_cursor, :string, default: nil
  attr :status, :atom, required: true
  attr :persisted, Vxpipe.Calls.CallDetailPage, default: nil
  attr :live, Vxpipe.Calls.LiveCallInspection, default: nil

  def workbench(assigns) do
    timeline = CallInspectionTimeline.combine(assigns.persisted, assigns.live)
    selected_event = CallInspectionTimeline.select(timeline, assigns.selected_event_id)

    assigns =
      assigns
      |> assign(:timeline, timeline)
      |> assign(:selected_event, selected_event)
      |> assign(:variable_diff, variable_diff(assigns.persisted, assigns.live))
      |> assign(:participant_summary, participant_summary(timeline))
      |> assign(:timeline_notice, timeline_notice(assigns.persisted, assigns.live))

    ~H"""
    <section class="call-workbench" aria-labelledby="selected-call-heading">
      <header class="selected-call-heading">
        <div>
          <h2 id="selected-call-heading">
            Call {@selected_id}
            <span class="selected-call-state" data-state={@status}>{call_state(@status)}</span>
          </h2>
        </div>
        <div class="evidence-source">
          <span>Persisted revision <strong>{persisted_revision(@persisted)}</strong></span>
          <span>Live revision <strong>{live_revision(@live)}</strong></span>
          <span>Revision delta <strong>{revision_delta(@persisted, @live)}</strong></span>
          <span>Archive latency <strong>Unavailable</strong></span>
          <span class="sr-only">{source_status(@status)}</span>
        </div>
      </header>

      <%= if @status in [:not_found, :unavailable] do %>
        <div class="detail-unavailable" role="status">
          <h3>{unavailable_heading(@status)}</h3>
          <p>{unavailable_detail(@status)}</p>
        </div>
      <% else %>
        <.call_context persisted={@persisted} live={@live} participants={@participant_summary} />

        <div class="evidence-grid">
          <section class="event-ledger" aria-labelledby="event-ledger-heading">
            <div class="section-heading">
              <h3 id="event-ledger-heading">Event ledger</h3>
              <span>{length(@timeline)} bounded events</span>
            </div>
            <p :if={@timeline_notice} class="ledger-notice">{@timeline_notice}</p>
            <div :if={@timeline == []} class="detail-empty">No retained events on this page.</div>
            <ol :if={@timeline != []} class="event-list">
              <li :for={event <- @timeline} data-selected={to_string(event == @selected_event)}>
                <.link
                  patch={event_path(@selected_id, event, @list_cursor, @history_cursor)}
                  data-event-key={CallInspectionTimeline.selection_key(event)}
                  aria-current={to_string(event == @selected_event)}
                >
                  <time datetime={DateTime.to_iso8601(event.occurred_at)}>
                    {CallInspectionFormat.timestamp(event.occurred_at)}
                  </time>
                  <span class="event-source" data-source={event.source}>
                    {source_label(event.source)} · {source_position(event)}
                  </span>
                  <strong>{kind_label(event.kind)}</strong>
                  <span>{participant_label(event.participant_id)}</span>
                  <small>{duration_label(event.observed_duration_ms)}</small>
                </.link>
              </li>
            </ol>
            <footer class="ledger-footer">
              <span>Newest first. Source time shown in UTC.</span>
              <.link
                :if={next_history_cursor(@persisted)}
                class="button"
                patch={
                  history_path(
                    @selected_id,
                    next_history_cursor(@persisted),
                    @list_cursor,
                    @selected_event
                  )
                }
              >
                Load earlier events
              </.link>
            </footer>
          </section>

          <section class="event-evidence" aria-labelledby="event-evidence-heading">
            <div class="section-heading">
              <h3 id="event-evidence-heading">
                Call evidence — {event_kind(@selected_event)}
              </h3>
              <span>{event_source(@selected_event)}</span>
            </div>
            <%= if @selected_event do %>
              <dl class="evidence-list">
                <div><dt>Event ID</dt><dd>{@selected_event.id}</dd></div>
                <div><dt>Source</dt><dd>{source_label(@selected_event.source)}</dd></div>
                <div><dt>Source sequence</dt><dd>{value(@selected_event.source_sequence)}</dd></div>
                <div><dt>Occurred</dt><dd>{CallInspectionFormat.timestamp(@selected_event.occurred_at)}</dd></div>
                <div><dt>Participant</dt><dd>{value(@selected_event.participant_id)}</dd></div>
                <div><dt>Activation</dt><dd>{value(@selected_event.activation_id)}</dd></div>
                <div><dt>Source participant</dt><dd>{value(@selected_event.source_participant_id)}</dd></div>
                <div><dt>Connection</dt><dd>{value(@selected_event.connection_id)}</dd></div>
                <div><dt>Command</dt><dd>{value(@selected_event.command_id)}</dd></div>
                <div><dt>Turn</dt><dd>{value(@selected_event.correlation_id)}</dd></div>
                <div><dt>Tool call</dt><dd>{value(@selected_event.tool_call_id)}</dd></div>
                <div><dt>Variable revision</dt><dd>{revision_value(@selected_event.variable_revision)}</dd></div>
                <div><dt>Section revision</dt><dd>{revision_value(@selected_event.section_revision)}</dd></div>
                <div><dt>Observed duration</dt><dd>{duration_label(@selected_event.observed_duration_ms)}</dd></div>
                <div><dt>Duration basis</dt><dd>{duration_basis(@selected_event.duration_basis)}</dd></div>
              </dl>
              <pre class="payload-readout">{payload_json(@selected_event.payload)}</pre>
            <% else %>
              <div class="detail-empty">Select a page with retained evidence to inspect it.</div>
            <% end %>
          </section>
        </div>

        <section class="variable-diff" data-state={variable_diff_state(@variable_diff)}>
          <div>
            <span class="readout-label">Variables changed</span>
            <strong>{variable_diff_revision(@variable_diff)}</strong>
          </div>
          <pre :if={@variable_diff}>{payload_json(@variable_diff.changes)}</pre>
          <p :if={is_nil(@variable_diff)}>
            A comparable persisted and live variable snapshot is unavailable on this page.
          </p>
        </section>

        <footer class="revision-strip">
          <div>
            <span class="readout-label">Persisted revision</span>
            <strong>{persisted_revision(@persisted)}</strong>
          </div>
          <div>
            <span class="readout-label">Live revision</span>
            <strong>{live_revision(@live)}</strong>
          </div>
          <div>
            <span class="readout-label">Archive state</span>
            <strong>{archive_label(@persisted)}</strong>
          </div>
          <div>
            <span class="readout-label">Live loss</span>
            <strong>{loss_label(@live)}</strong>
          </div>
        </footer>
      <% end %>
    </section>
    """
  end

  attr :persisted, Vxpipe.Calls.CallDetailPage, default: nil
  attr :live, Vxpipe.Calls.LiveCallInspection, default: nil
  attr :participants, :string, required: true

  defp call_context(assigns) do
    ~H"""
    <dl class="call-context">
      <div>
        <dt>Definition</dt>
        <dd>{definition_label(@persisted)}</dd>
      </div>
      <div><dt>Room</dt><dd>{live_value(@live, :room_id)}</dd></div>
      <div><dt>Incarnation</dt><dd>{live_value(@live, :incarnation_id)}</dd></div>
      <div><dt>Started</dt><dd>{started_label(@persisted)}</dd></div>
      <div><dt>Duration</dt><dd>{call_duration(persisted_call(@persisted))}</dd></div>
      <div class="call-context-participants"><dt>Participants</dt><dd>{@participants}</dd></div>
    </dl>
    """
  end

  defp variable_diff(persisted, live) do
    case CallVariableDiff.between(persisted, live) do
      {:ok, diff} -> diff
      :unavailable -> nil
    end
  end

  defp source_status(:live), do: "Live and persisted evidence available"
  defp source_status(:live_only), do: "Live evidence available"
  defp source_status(:persisted), do: "Persisted evidence selected"
  defp source_status(:not_found), do: "Call not found"
  defp source_status(:unavailable), do: "Evidence unavailable"

  defp call_state(:live), do: "Live"
  defp call_state(:live_only), do: "Live only"
  defp call_state(:persisted), do: "Persisted"
  defp call_state(:not_found), do: "Not found"
  defp call_state(:unavailable), do: "Unavailable"

  defp unavailable_heading(:not_found), do: "Call not found"
  defp unavailable_heading(:unavailable), do: "Call evidence unavailable"

  defp unavailable_detail(:not_found), do: "No retained call is visible to this tenant."

  defp unavailable_detail(:unavailable),
    do:
      "The call history service could not return this evidence. Calls in progress are unaffected."

  defp participant_summary([]), do: "Unavailable"

  defp participant_summary(timeline) do
    timeline
    |> Enum.flat_map(&[&1.participant_id, &1.source_participant_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> "Call-wide only"
      participants -> Enum.join(participants, ", ")
    end
  end

  defp timeline_notice(persisted, live) do
    [archive_gap(persisted), live_gap(live)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
    |> case do
      "" -> nil
      notice -> notice
    end
  end

  defp archive_gap(nil), do: nil

  defp archive_gap(%{archive_status: status}) do
    details =
      [
        count_label(status.missing_sequence_count, "missing sequence"),
        count_label(status.duplicate_id_count, "duplicate ID"),
        count_label(status.duplicate_sequence_count, "duplicate sequence")
      ]
      |> Enum.reject(&is_nil/1)

    if details == [], do: nil, else: "Archive gap: " <> Enum.join(details, " · ")
  end

  defp live_gap(nil), do: nil
  defp live_gap(%{dropped_records: 0, rejected_records: 0}), do: nil
  defp live_gap(live), do: "Live projection gap: #{loss_label(live)}"

  defp count_label(0, _label), do: nil
  defp count_label(1, label), do: "1 #{label}"
  defp count_label(count, label), do: "#{count} #{label}s"

  defp kind_label(kind), do: kind |> Atom.to_string() |> String.replace("_", " ")
  defp participant_label(nil), do: "Call-wide"
  defp participant_label(participant_id), do: participant_id
  defp duration_label(nil), do: "Timing unavailable"
  defp duration_label(duration_ms), do: "#{duration_ms} ms observed"
  defp event_source(nil), do: "No event"
  defp event_source(event), do: source_label(event.source)
  defp event_kind(nil), do: "no event"
  defp event_kind(event), do: kind_label(event.kind)
  defp source_label(:persisted), do: "Persisted"
  defp source_label(:live), do: "Live"

  defp source_position(%{variable_revision: revision}) when is_integer(revision),
    do: "r#{revision}"

  defp source_position(%{source_sequence: sequence}) when is_integer(sequence),
    do: "seq #{sequence}"

  defp source_position(_event), do: "position unavailable"

  defp value(nil), do: "Not attributed"
  defp value(value), do: value
  defp revision_value(nil), do: "Not attributed"
  defp revision_value(value), do: CallInspectionFormat.revision(value)
  defp duration_basis(nil), do: "Unavailable"
  defp duration_basis(:source_timestamps), do: "source timestamps"
  defp payload_json(payload), do: JSON.encode!(payload)

  defp persisted_revision(nil), do: "Unavailable"

  defp persisted_revision(persisted),
    do: CallInspectionFormat.revision(persisted.persisted_variable_revision)

  defp live_revision(nil), do: "Unavailable"
  defp live_revision(live), do: CallInspectionFormat.revision(live.live_variable_revision)

  defp revision_delta(nil, _live), do: "Unavailable"
  defp revision_delta(_persisted, nil), do: "Unavailable"

  defp revision_delta(persisted, live) do
    "#{persisted_revision(persisted)} → #{live_revision(live)}"
  end

  defp archive_label(nil), do: "Unavailable"
  defp archive_label(%{archive_status: %{state: :complete}}), do: "Complete"
  defp archive_label(%{archive_status: %{state: :incomplete}}), do: "Archive incomplete"
  defp archive_label(%{archive_status: %{state: :unconfirmed}}), do: "Archive not yet confirmed"

  defp loss_label(nil), do: "Unavailable"

  defp loss_label(%{dropped_records: dropped, rejected_records: rejected}) do
    case {dropped, rejected} do
      {0, 0} -> "None observed"
      {1, 0} -> "1 record dropped"
      {dropped, 0} -> "#{dropped} records dropped"
      {0, 1} -> "1 record rejected"
      {0, rejected} -> "#{rejected} records rejected"
      {dropped, rejected} -> "#{dropped} dropped · #{rejected} rejected"
    end
  end

  defp live_value(nil, _field), do: "Unavailable"
  defp live_value(live, :room_id), do: live.room_id
  defp live_value(live, :incarnation_id), do: live.incarnation_id

  defp definition_label(nil), do: "Unavailable"

  defp definition_label(persisted) do
    "#{persisted.call.definition_id} · r#{persisted.call.definition_revision}"
  end

  defp started_label(nil), do: "Unavailable"
  defp started_label(persisted), do: CallInspectionFormat.timestamp(persisted.call.started_at)

  defp persisted_call(nil), do: nil
  defp persisted_call(persisted), do: persisted.call

  defp call_duration(nil), do: "Unavailable"
  defp call_duration(%{started_at: nil}), do: "Not started"
  defp call_duration(%{started_at: _started_at, ended_at: nil}), do: "In progress"

  defp call_duration(%{started_at: started_at, ended_at: ended_at}) do
    seconds = DateTime.diff(ended_at, started_at, :second)
    "#{seconds} seconds"
  end

  defp variable_diff_state(nil), do: "unavailable"
  defp variable_diff_state(_diff), do: "available"
  defp variable_diff_revision(nil), do: "Unavailable"

  defp variable_diff_revision(diff) do
    "r#{diff.from_revision} → r#{diff.to_revision}"
  end

  defp event_path(call_id, event, list_cursor, history_cursor) do
    path_with_query(call_id, %{
      "cursor" => list_cursor,
      "event" => CallInspectionTimeline.selection_key(event),
      "history_cursor" => history_cursor
    })
  end

  defp history_path(call_id, history_cursor, list_cursor, selected_event) do
    path_with_query(call_id, %{
      "cursor" => list_cursor,
      "event" => selected_event_key(selected_event),
      "history_cursor" => history_cursor
    })
  end

  defp selected_event_key(nil), do: nil
  defp selected_event_key(event), do: CallInspectionTimeline.selection_key(event)

  defp next_history_cursor(nil), do: nil
  defp next_history_cursor(persisted), do: persisted.next_cursor

  defp path_with_query(call_id, values) do
    query =
      values
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> URI.encode_query()

    path = "/calls/" <> URI.encode_www_form(call_id)
    if query == "", do: path, else: path <> "?" <> query
  end
end
