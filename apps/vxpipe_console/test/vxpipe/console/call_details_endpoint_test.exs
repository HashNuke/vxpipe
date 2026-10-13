defmodule Vxpipe.Console.CallDetailsEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2]

  alias Vxpipe.Calls.{CallDetailsDocument, CallDetailsRevision, CallDetailsRevisionPage}
  alias Vxpipe.Console.Test.FakeUserIdentity
  alias Vxpipe.Console.TestCallDetailsBackend

  @endpoint Vxpipe.Console.Endpoint
  @tenant_key "tenantkey1234567"
  @call_id "call-public-id"
  @publication_id "publication-public-id"

  setup do
    original_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_backend = Application.get_env(:vxpipe_console, :user_identity_backend)
    original_details = Application.get_env(:vxpipe_console, :call_details_backend)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original_calls)

      if original_backend,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, original_backend),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)

      case original_details do
        nil -> Application.delete_env(:vxpipe_console, :call_details_backend)
        value -> Application.put_env(:vxpipe_console, :call_details_backend, value)
      end
    end)

    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)
    :ok
  end

  test "requires an installation operator session for a call-details document" do
    assert redirected_to(https_get(route()), 302) == "/auth/login"
  end

  test "downloads the exact published JSON with private response headers" do
    contents = ~s({"call":{"id":"call-public-id"},"completeness":"complete"})
    configure_details(%{list: {:ok, revision_page()}, fetch: {:ok, document(contents)}})

    conn = authenticate() |> recycle() |> https_get(route())

    assert response(conn, 200) == contents
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

    assert get_resp_header(conn, "content-disposition") ==
             [~s(attachment; filename="details-20260912123456789.json")]

    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]

    assert_receive {:fetch_call_details, access, @call_id, @publication_id, []}
    assert {:ok, @tenant_key} = Vxpipe.Calls.CallReadAccess.tenant_key(access)
  end

  test "does not disclose why a document is unavailable" do
    configure_details(%{
      list: {:ok, revision_page()},
      fetch: {:error, :call_details_not_found}
    })

    conn = authenticate() |> recycle() |> https_get(route())

    assert response(conn, 404) == "Call details not found."
    refute conn.resp_body =~ "call_details_not_found"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  defp route,
    do: "/tenants/#{@tenant_key}/calls/#{@call_id}/details/#{@publication_id}"

  defp authenticate do
    post(build_conn(), "https://localhost/auth/api/login", %{
      "email" => FakeUserIdentity.email(),
      "password" => FakeUserIdentity.password()
    })
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")

  defp configure_details(responses) do
    Application.put_env(
      :vxpipe_console,
      :call_details_backend,
      {TestCallDetailsBackend, {self(), responses}}
    )
  end

  defp revision_page do
    %CallDetailsRevisionPage{revisions: [published_revision()], next_cursor: nil}
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
end
