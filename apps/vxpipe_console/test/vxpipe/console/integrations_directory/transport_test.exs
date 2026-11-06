defmodule Vxpipe.Console.IntegrationsDirectory.TransportTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias Vxpipe.Console.IntegrationsDirectory.{Request, Transport}

  setup do
    Req.Test.verify_on_exit!()
    {:ok, request} = Request.build(:integrations, %{"q" => "calendar", "scope" => "platform"})
    %{request: request}
  end

  test "sends a public versioned request and returns raw JSON with cache metadata", %{
    request: request
  } do
    Req.Test.expect(__MODULE__, fn conn ->
      conn = fetch_query_params(conn)
      assert conn.query_params == %{"q" => "calendar", "scope" => "platform", "limit" => "20"}
      assert conn.request_path == "/v1/integrations"
      assert get_req_header(conn, "x-vxpipe-version") == [Request.installation_version()]
      assert get_req_header(conn, "authorization") == []
      assert get_req_header(conn, "cookie") == []
      conn |> put_resp_header("etag", "\"revision\"") |> Req.Test.json(%{items: []})
    end)

    assert {:ok, %{body: %{"items" => []}, etag: "\"revision\""}} = fetch(request)
  end

  test "does not follow redirects or retry unavailable responses", %{request: request} do
    Req.Test.expect(__MODULE__, fn conn ->
      conn |> put_resp_header("location", "https://other.example") |> send_resp(302, "private")
    end)

    assert {:error, :unexpected_status} = fetch(request)

    Req.Test.expect(__MODULE__, fn conn -> send_resp(conn, 503, "private upstream diagnostic") end)

    assert {:error, :unavailable} = fetch(request)
  end

  test "rejects invalid JSON without exposing the response", %{request: request} do
    Req.Test.expect(__MODULE__, fn conn ->
      conn |> put_resp_content_type("application/json") |> send_resp(200, "not json")
    end)

    assert {:error, :invalid_response} = fetch(request)
  end

  test "rejects oversized valid JSON at the streaming byte limit", %{request: request} do
    body = JSON.encode!(%{"data" => String.duplicate("x", 1_048_577)})

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> put_resp_content_type("application/json") |> send_resp(200, body)
    end)

    assert {:error, :response_too_large} = fetch(request)
  end

  test "returns an explicit not-modified result without inventing a cached page", %{
    request: request
  } do
    Req.Test.expect(__MODULE__, fn conn ->
      assert get_req_header(conn, "if-none-match") == ["\"cached\""]
      send_resp(conn, 304, "")
    end)

    assert :not_modified = fetch(request, etag: "\"cached\"")
  end

  test "rate limits return bounded Retry-After delays without upstream bodies", %{
    request: request
  } do
    for {header, delay} <- [
          {"12", 12_000},
          {"malformed-private", 60_000},
          {"Fri, 01 Jan 2100 00:00:00 GMT", 86_400_000},
          {"999999999", 86_400_000}
        ] do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> put_resp_header("retry-after", header) |> send_resp(429, "private diagnostic")
      end)

      assert {:error, {:rate_limited, ^delay}} = fetch(request)
    end
  end

  defp fetch(request, options \\ []) do
    Transport.fetch(request, Keyword.put(options, :plug, {Req.Test, __MODULE__}))
  end

  test "distinguishes documented bad-request codes without exposing upstream diagnostics", %{
    request: request
  } do
    for {code, expected} <- [
          {"invalid_version", :invalid_version},
          {"invalid_cursor", :invalid_cursor},
          {"cursor_mismatch", :cursor_mismatch},
          {"private_unknown_code", :invalid_query}
        ] do
      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> put_status(400)
        |> Req.Test.json(%{error: %{code: code, message: "private diagnostic"}})
      end)

      assert {:error, ^expected} = fetch(request)
    end
  end
end
