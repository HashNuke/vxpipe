defmodule Vxpipe.Console.Test.MCPBrowserConsent do
  @moduledoc "Explicit, one-use consent UI for the controlled browser acceptance peer."
  @behaviour Plug
  import Plug.Conn
  alias Vxpipe.Console.Test.OutboundMCPOAuthServer

  @impl true
  def init(options) do
    Agent.update(options.state, &Map.put_new(&1, :browser_pending, %{}))
    options
  end

  @impl true
  def call(%{method: "GET", request_path: "/authorize"} = conn, options) do
    conn = fetch_query_params(conn)
    request = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    now = System.monotonic_time(:millisecond)

    accepted =
      Agent.get_and_update(options.state, fn state ->
        pending = Map.reject(state.browser_pending, fn {_, {deadline, _}} -> deadline <= now end)

        if map_size(pending) < 32 do
          {true,
           %{
             state
             | browser_pending: Map.put(pending, request, {now + 300_000, conn.query_params})
           }}
        else
          {false, %{state | browser_pending: pending}}
        end
      end)

    if accepted do
      conn
      |> put_resp_content_type("text/html")
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
      |> send_resp(200, """
      <!doctype html><html lang="en"><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Fixture calendar consent</title>
      <main><h1>Connect Fixture calendar</h1>
      <p>This local acceptance server will allow Vxpipe to read its fixture tools.</p>
      <form method="post" action="/consent">
      <input type="hidden" name="request" value="#{request}">
      <button name="decision" value="allow">Allow access</button>
      <button name="decision" value="deny">Deny access</button>
      </form></main></html>
      """)
    else
      send_resp(conn, 429, "Too many pending fixture approvals")
    end
  end

  def call(%{method: "POST", request_path: "/consent"} = conn, options) do
    with {:ok, body, conn} <- read_body(conn, length: 2048),
         %{"request" => request, "decision" => decision} when decision in ["allow", "deny"] <-
           URI.decode_query(body) do
      pending =
        Agent.get_and_update(options.state, fn state ->
          {pending, rest} = Map.pop(state.browser_pending, request)
          {pending, %{state | browser_pending: rest}}
        end)

      complete(conn, options, pending, decision)
    else
      _ -> send_resp(conn, 400, "Invalid fixture approval")
    end
  end

  def call(conn, options), do: OutboundMCPOAuthServer.call(conn, options.state)

  defp complete(conn, options, {deadline, params}, decision) do
    cond do
      deadline <= System.monotonic_time(:millisecond) ->
        send_resp(conn, 410, "Fixture approval expired")

      decision == "allow" and not metadata_valid?(options, params) ->
        send_resp(conn, 400, "Client metadata rejected")

      true ->
        conn = %{
          conn
          | method: "GET",
            request_path: "/authorize",
            query_string: URI.encode_query(params),
            query_params: %Plug.Conn.Unfetched{aspect: :query_params}
        }

        conn
        |> assign(:fixture_consent, if(decision == "allow", do: :allow, else: :deny))
        |> OutboundMCPOAuthServer.call(options.state)
    end
  end

  defp complete(conn, _options, nil, _decision),
    do: send_resp(conn, 410, "Fixture approval unavailable")

  defp metadata_valid?(options, params) do
    {mode, origin} = Agent.get(options.state, &{&1.mode, &1.origin})

    if mode == "cimd" do
      expected = origin <> "/oauth/client-metadata.json"
      fetch = Map.get(options, :metadata_fetch, fn _ -> {:error, :unconfigured} end)

      with true <- params["client_id"] == expected,
           {:ok, %{"client_id" => ^expected, "redirect_uris" => callbacks}} <- fetch.(expected),
           true <- callbacks == [origin <> "/oauth/mcp/callback"] do
        true
      else
        _ -> false
      end
    else
      true
    end
  end
end
