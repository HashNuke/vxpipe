defmodule Vxpipe.Console.CallDetailsEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2]

  alias Vxpipe.Calls.{
    ArchiveStatus,
    CallDetailPage,
    CallDetailsDocument,
    CallDetailsRevision,
    CallDetailsRevisionPage,
    CallListPage,
    CallSummary
  }

  alias Vxpipe.Console.{
    TestCallDetailsBackend,
    TestCallInspectionBackend,
    TestCallRecordingBackend,
    TestOperatorAuthenticator
  }

  @endpoint Vxpipe.Console.Endpoint
  @tenant_key "tenantkey1234567"
  @call_id "call-public-id"
  @publication_id "publication-public-id"

  setup do
    original = %{
      authenticator: Application.fetch_env!(:vxpipe_console, :operator_authenticator),
      details: Application.get_env(:vxpipe_console, :call_details_backend),
      inspection: Application.fetch_env!(:vxpipe_console, :call_inspection_backend),
      recording: Application.fetch_env!(:vxpipe_console, :call_recording_backend)
    }

    on_exit(fn -> restore_configuration(original) end)

    Application.put_env(
      :vxpipe_console,
      :operator_authenticator,
      {TestOperatorAuthenticator, self()}
    )

    configure_inspection()
    configure_recordings()
    :ok
  end

  test "requires an operator session for a call-details document" do
    route = "/calls/#{@call_id}/details/#{@publication_id}"

    assert redirected_to(get(build_conn(), route), 302) == "/operator/sign-in"
  end

  test "downloads the exact published JSON with private response headers" do
    contents = ~s({"call":{"id":"call-public-id"},"completeness":"complete"})
    configure_details(%{list: {:ok, revision_page()}, fetch: {:ok, document(contents)}})

    route = "/calls/#{@call_id}/details/#{@publication_id}"
    conn = sign_in() |> recycle() |> get(route)

    assert response(conn, 200) == contents
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

    assert get_resp_header(conn, "content-disposition") ==
             [~s(attachment; filename="details-20260912123456789.json")]

    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]

    assert_receive {:fetch_call_details, principal, @call_id, @publication_id, []}
    assert principal.tenant_key == @tenant_key
  end

  test "does not disclose why a document is unavailable" do
    configure_details(%{
      list: {:ok, revision_page()},
      fetch: {:error, :call_details_not_found}
    })

    route = "/calls/#{@call_id}/details/#{@publication_id}"
    conn = sign_in() |> recycle() |> get(route)

    assert response(conn, 404) == "Call details not found."
    refute conn.resp_body =~ "call_details_not_found"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "presents published and pending revisions without storage references" do
    configure_details(%{list: {:ok, revision_page()}, fetch: {:ok, document("{}")}})

    html = sign_in() |> recycle() |> get("/calls/#{@call_id}") |> html_response(200)

    assert html =~ "Call details"
    assert html =~ "2 revisions"
    assert html =~ "Latest"
    assert html =~ "Complete"
    assert html =~ "Incomplete"
    assert html =~ "Delivery pending"
    assert html =~ "details-20260912123456789.json"
    assert html =~ "/calls/#{@call_id}/details/#{@publication_id}"
    assert length(Regex.scan(~r/>Download JSON</, html)) == 1
    refute html =~ "private/call-details/object-key"

    assert_receive {:list_call_details, principal, @call_id, [limit: 25]}
    assert principal.tenant_key == @tenant_key
  end

  test "keeps existing inspection state while paging through immutable revisions" do
    configure_details(%{
      list: {:ok, %{revision_page() | next_cursor: "older-details"}},
      fetch: {:ok, document("{}")}
    })

    query =
      URI.encode_query(%{
        "cursor" => "call-page",
        "details_cursor" => "current-details",
        "event" => "persisted:event-public-id",
        "history_cursor" => "history-page"
      })

    html =
      sign_in()
      |> recycle()
      |> get("/calls/#{@call_id}?#{query}")
      |> html_response(200)

    assert html =~ "Load older publications"
    assert html =~ "details_cursor=older-details"
    assert html =~ "cursor=call-page"
    assert html =~ "history_cursor=history-page"
    assert html =~ "event=persisted%3Aevent-public-id"

    assert_receive {:list_call_details, _, @call_id, [limit: 25, cursor: "current-details"]}
  end

  defp sign_in do
    post(build_conn(), "/operator/session", %{
      "operator" => %{
        "tenant_key" => @tenant_key,
        "api_key" => "valid-api-key"
      }
    })
  end

  defp configure_details(responses) do
    Application.put_env(
      :vxpipe_console,
      :call_details_backend,
      {TestCallDetailsBackend, {self(), responses}}
    )
  end

  defp configure_inspection do
    call = call_summary()

    responses = %{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call:
        {:ok,
         %CallDetailPage{
           call: call,
           timeline: [],
           next_cursor: nil,
           archive_status: ArchiveStatus.from_facts([]),
           persisted_variable_revision: 0
         }}
    }

    Application.put_env(
      :vxpipe_console,
      :call_inspection_backend,
      {TestCallInspectionBackend, {self(), responses}}
    )
  end

  defp configure_recordings do
    Application.put_env(
      :vxpipe_console,
      :call_recording_backend,
      {TestCallRecordingBackend, {self(), {:ok, []}}}
    )
  end

  defp call_summary do
    %CallSummary{
      id: @call_id,
      tenant_key: @tenant_key,
      definition_id: "definition-public-id",
      definition_revision: 3,
      state: :ended,
      created_at: ~U[2026-09-12 12:30:00Z],
      started_at: ~U[2026-09-12 12:30:01Z],
      ended_at: ~U[2026-09-12 12:34:00Z],
      terminal_reason: "ended",
      latest_variable_revision: 0
    }
  end

  defp revision_page do
    %CallDetailsRevisionPage{
      revisions: [published_revision(), pending_revision()],
      next_cursor: nil
    }
  end

  defp published_revision do
    %CallDetailsRevision{
      id: @publication_id,
      recorded_at: ~U[2026-09-12 12:34:56.789Z],
      filename: "details-20260912123456789.json",
      completeness: :complete,
      status: :published,
      checksum: String.duplicate("a", 64),
      size_bytes: 1_024,
      published_at: ~U[2026-09-12 12:34:57Z],
      latest?: true
    }
  end

  defp pending_revision do
    %CallDetailsRevision{
      id: "pending-publication-id",
      recorded_at: ~U[2026-09-12 12:34:55.123Z],
      filename: "details-20260912123455123.json",
      completeness: :incomplete,
      status: :pending,
      checksum: String.duplicate("b", 64),
      size_bytes: 512,
      published_at: nil,
      latest?: false
    }
  end

  defp document(contents) do
    %CallDetailsDocument{
      id: @publication_id,
      recorded_at: ~U[2026-09-12 12:34:56.789Z],
      filename: "details-20260912123456789.json",
      completeness: :complete,
      checksum: String.duplicate("a", 64),
      contents: contents,
      published_at: ~U[2026-09-12 12:34:57Z]
    }
  end

  defp restore_configuration(original) do
    Application.put_env(:vxpipe_console, :operator_authenticator, original.authenticator)
    Application.put_env(:vxpipe_console, :call_inspection_backend, original.inspection)
    Application.put_env(:vxpipe_console, :call_recording_backend, original.recording)

    case original.details do
      nil -> Application.delete_env(:vxpipe_console, :call_details_backend)
      value -> Application.put_env(:vxpipe_console, :call_details_backend, value)
    end
  end
end
