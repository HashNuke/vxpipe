defmodule Vxpipe.Console.CallInspectionComponents do
  @moduledoc false

  use Phoenix.Component

  alias Vxpipe.Console.CallInspectionDetailComponents
  alias Vxpipe.Console.CallInspectionFormat

  attr :principal, Vxpipe.Calls.Principal, required: true
  attr :page, Vxpipe.Calls.CallListPage, default: nil
  attr :status, :atom, required: true
  attr :selected_id, :string, default: nil
  attr :persisted, Vxpipe.Calls.CallDetailPage, default: nil
  attr :live, Vxpipe.Calls.LiveCallInspection, default: nil
  attr :detail_status, :atom, default: :none
  attr :list_cursor, :string, default: nil
  attr :history_cursor, :string, default: nil
  attr :selected_event_id, :string, default: nil
  attr :recordings, :list, default: []
  attr :recordings_status, :atom, default: :unavailable
  attr :usage_report, Vxpipe.Calls.UsageReport, default: nil
  attr :usage_status, :atom, default: :unavailable

  def index(assigns) do
    ~H"""
    <main id="call-inspection" class="inspection-shell">
      <header class="inspection-topbar">
        <div class="inspection-brand">
          <h1>Vxpipe <span>Calls</span></h1>
          <p>Inspect and debug voice calls with a bounded event timeline and source revisions.</p>
        </div>
        <div class="inspection-actions">
          <a class="nav-link" href="/">Voice console</a>
          <a class="nav-link nav-link--primary" href="/diagnostics">Diagnostics</a>
          <div class="operator-readout">
            <span>Tenant</span>
            <span>{@principal.tenant_key}</span>
          </div>
          <form class="sign-out-form" action="/operator/sign-out" method="post">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <button class="button" type="submit">Sign out</button>
          </form>
        </div>
      </header>

      <.status_strip status={@status} page={@page} />
      <.matrix
        status={@status}
        page={@page}
        selected_id={@selected_id}
        selected_event_id={@selected_event_id}
        list_cursor={@list_cursor}
        history_cursor={@history_cursor}
      />
      <CallInspectionDetailComponents.workbench
        :if={@selected_id}
        selected_id={@selected_id}
        selected_event_id={@selected_event_id}
        list_cursor={@list_cursor}
        history_cursor={@history_cursor}
        status={@detail_status}
        persisted={@persisted}
        live={@live}
        recordings={@recordings}
        recordings_status={@recordings_status}
        usage_report={@usage_report}
        usage_status={@usage_status}
      />
    </main>
    """
  end

  attr :page, Vxpipe.Calls.CallListPage, default: nil
  attr :status, :atom, required: true

  defp status_strip(assigns) do
    assigns =
      assigns
      |> assign(:state, if(assigns.status == :available, do: "available", else: "unavailable"))
      |> assign(:call_count, call_count(assigns.page))

    ~H"""
    <section class="inspection-status" data-state={@state} aria-labelledby="archive-state">
      <div class="status-primary">
        <span class="status-marker" aria-hidden="true"></span>
        <div>
          <h2 id="archive-state">{archive_label(@status)}</h2>
          <p>{archive_detail(@status)}</p>
        </div>
      </div>
      <div class="status-readout">
        <span class="readout-label">Calls on page</span>
        <span class="readout-value">{@call_count}</span>
      </div>
      <div class="status-readout">
        <span class="readout-label">History source</span>
        <span class="readout-value">{source_label(@status)}</span>
      </div>
    </section>
    """
  end

  attr :page, Vxpipe.Calls.CallListPage, default: nil
  attr :status, :atom, required: true
  attr :selected_id, :string, default: nil
  attr :selected_event_id, :string, default: nil
  attr :list_cursor, :string, default: nil
  attr :history_cursor, :string, default: nil

  defp matrix(%{status: :unavailable} = assigns) do
    ~H"""
    <section class="matrix-surface">
      <div id="call-archive-unavailable" class="matrix-unavailable" role="status">
        <div>
          <h2><strong>Call archive unavailable</strong></h2>
          <p>Calls in progress are unaffected. Reload after the history service recovers.</p>
        </div>
      </div>
    </section>
    """
  end

  defp matrix(%{page: %{calls: []}} = assigns) do
    ~H"""
    <section class="matrix-surface">
      <div id="calls-empty" class="matrix-empty" role="status">
        <div>
          <h2>No calls to inspect</h2>
          <p>This tenant has no retained call records on this page.</p>
        </div>
      </div>
    </section>
    """
  end

  defp matrix(assigns) do
    ~H"""
    <section class="matrix-surface" aria-label="Call history">
      <div class="matrix-scroll">
        <table class="matrix-table">
          <thead>
            <tr>
              <th>Call</th>
              <th>Definition</th>
              <th>State</th>
              <th>Started</th>
              <th>Variables</th>
              <th>Archive</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={call <- @page.calls} data-selected={to_string(call.id == @selected_id)}>
              <td class="cell-primary">
                <.link patch={call_path(call.id, @list_cursor)}>{call.id}</.link>
              </td>
              <td class="definition-cell">
                <span>{call.definition_id}</span>
                <small>revision {call.definition_revision}</small>
              </td>
              <td>
                <span class="state-cell" data-state={call.state}>
                  <span class="state-marker" aria-hidden="true"></span>
                  {CallInspectionFormat.state(call.state)}
                </span>
              </td>
              <td>{CallInspectionFormat.timestamp(call.started_at)}</td>
              <td>{CallInspectionFormat.revision(call.latest_variable_revision)}</td>
              <td>Not checked</td>
            </tr>
          </tbody>
        </table>
      </div>
      <footer class="matrix-footer">
        <span>Showing at most 25 calls. Times are UTC.</span>
        <.link
          :if={@page.next_cursor}
          class="button"
          patch={
            next_page_path(
              @selected_id,
              @page.next_cursor,
              @history_cursor,
              @selected_event_id
            )
          }
        >
          Load older calls
        </.link>
      </footer>
    </section>
    """
  end

  defp archive_label(:available), do: "Call archive available"
  defp archive_label(:unavailable), do: "Call archive unavailable"

  defp archive_detail(:available), do: "One bounded tenant history page is loaded."
  defp archive_detail(:unavailable), do: "No persisted call list is available."

  defp source_label(:available), do: "Persisted"
  defp source_label(:unavailable), do: "Unavailable"

  defp call_count(nil), do: "—"
  defp call_count(page), do: length(page.calls)

  defp next_page_path(nil, cursor, _history_cursor, _selected_event_id),
    do: path_with_query("/calls", %{"cursor" => cursor})

  defp next_page_path(call_id, cursor, history_cursor, selected_event_id) do
    call_path(call_id, cursor,
      history_cursor: history_cursor,
      selected_event_id: selected_event_id
    )
  end

  defp call_path(call_id, list_cursor, options \\ []) do
    path_with_query("/calls/" <> URI.encode_www_form(call_id), %{
      "cursor" => list_cursor,
      "history_cursor" => Keyword.get(options, :history_cursor),
      "event" => Keyword.get(options, :selected_event_id)
    })
  end

  defp path_with_query(path, values) do
    query =
      values
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> URI.encode_query()

    if query == "", do: path, else: path <> "?" <> query
  end
end
