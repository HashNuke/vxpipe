defmodule Vxpipe.Console.CallDetailsComponents do
  @moduledoc false

  use Phoenix.Component

  alias Vxpipe.Calls.{CallDetailsRevision, CallDetailsRevisionPage}
  alias Vxpipe.Console.CallInspectionFormat

  attr :call_id, :string, required: true
  attr :calls_path, :string, required: true
  attr :page, CallDetailsRevisionPage, default: nil
  attr :status, :atom, required: true
  attr :list_cursor, :string, default: nil
  attr :history_cursor, :string, default: nil
  attr :details_cursor, :string, default: nil
  attr :selected_event_id, :string, default: nil

  def panel(assigns) do
    ~H"""
    <section class="details-bay" data-state={@status} aria-labelledby="details-bay-heading">
      <header class="details-bay-heading">
        <div>
          <h3 id="details-bay-heading">Call details</h3>
          <p>Immutable post-call evidence. New facts produce another revision.</p>
        </div>
        <span>{revision_count(@status, @page)}</span>
      </header>

      <div :if={@status == :unavailable} class="details-notice" data-state="unavailable" role="status">
        <strong>Call details unavailable</strong>
        <span>Reload after publication storage recovers. Retained call evidence is unaffected.</span>
      </div>

      <div
        :if={@status == :available and empty_page?(@page)}
        class="details-notice"
        data-state="empty"
        role="status"
      >
        <strong>No publications yet</strong>
        <span>A revision will appear after this call ends and publication begins.</span>
      </div>

      <div :if={@status == :available and not empty_page?(@page)} class="details-list">
        <article
          :for={revision <- @page.revisions}
          class="details-row"
          data-state={revision_state(revision)}
        >
          <div class="details-identity">
            <div>
              <strong>{revision.filename}</strong>
              <span :if={revision.latest?} class="details-latest">Latest</span>
            </div>
            <span class="details-id" title={revision.id}>{revision.id}</span>
          </div>

          <dl class="details-readouts">
            <div><dt>Recorded</dt><dd>{CallInspectionFormat.timestamp(revision.recorded_at)}</dd></div>
            <div><dt>Evidence</dt><dd data-state={revision.completeness}>{completeness(revision)}</dd></div>
            <div><dt>Delivery</dt><dd data-state={revision.status}>{delivery(revision)}</dd></div>
            <div><dt>Document</dt><dd>{document_size(revision.size_bytes)}</dd></div>
            <div class="details-checksum">
              <dt>SHA-256</dt><dd title={revision.checksum}>{short_checksum(revision.checksum)}</dd>
            </div>
          </dl>

          <div class="details-action">
            <a
              :if={revision.status == :published}
              class="button"
              href={document_path(@calls_path, @call_id, revision.id)}
            >Download JSON</a>
            <span :if={revision.status == :pending}>Delivery pending</span>
          </div>
        </article>

        <footer :if={@page.next_cursor} class="details-footer">
          <span>Showing at most 25 immutable revisions.</span>
          <.link
            class="button"
            patch={
              page_path(
                @calls_path,
                @call_id,
                @page.next_cursor,
                @list_cursor,
                @history_cursor,
                @selected_event_id
              )
            }
          >
            Load older publications
          </.link>
        </footer>
      </div>
    </section>
    """
  end

  defp empty_page?(nil), do: true
  defp empty_page?(%CallDetailsRevisionPage{revisions: revisions}), do: revisions == []

  defp revision_count(:unavailable, _page), do: "Unavailable"
  defp revision_count(:available, nil), do: "No revisions"
  defp revision_count(:available, %CallDetailsRevisionPage{revisions: []}), do: "No revisions"

  defp revision_count(:available, %CallDetailsRevisionPage{revisions: [_revision]}),
    do: "1 revision"

  defp revision_count(:available, %CallDetailsRevisionPage{revisions: revisions}),
    do: "#{length(revisions)} revisions"

  defp revision_state(%CallDetailsRevision{status: :pending}), do: :pending
  defp revision_state(%CallDetailsRevision{completeness: completeness}), do: completeness

  defp completeness(%CallDetailsRevision{completeness: :complete}), do: "Complete"
  defp completeness(%CallDetailsRevision{completeness: :incomplete}), do: "Incomplete"

  defp delivery(%CallDetailsRevision{status: :published}), do: "Published"
  defp delivery(%CallDetailsRevision{status: :pending}), do: "Pending"

  defp document_size(size_bytes) when size_bytes < 1_024, do: "#{size_bytes} B"

  defp document_size(size_bytes) do
    kibibytes = size_bytes / 1_024
    :erlang.float_to_binary(kibibytes, decimals: 1) <> " KiB"
  end

  defp short_checksum(checksum) when byte_size(checksum) > 12,
    do: binary_part(checksum, 0, 12) <> "…"

  defp short_checksum(checksum), do: checksum

  defp document_path(calls_path, call_id, publication_id) do
    "#{calls_path}/#{URI.encode_www_form(call_id)}/details/#{URI.encode_www_form(publication_id)}"
  end

  defp page_path(
         calls_path,
         call_id,
         details_cursor,
         list_cursor,
         history_cursor,
         selected_event_id
       ) do
    path_with_query(calls_path, call_id, %{
      "cursor" => list_cursor,
      "details_cursor" => details_cursor,
      "event" => selected_event_id,
      "history_cursor" => history_cursor
    })
  end

  defp path_with_query(calls_path, call_id, values) do
    query =
      values
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> URI.encode_query()

    path = calls_path <> "/" <> URI.encode_www_form(call_id)
    if query == "", do: path, else: path <> "?" <> query
  end
end
