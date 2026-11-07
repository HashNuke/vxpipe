defmodule Vxpipe.Console.Test.MCPBrowserDirectoryProxy do
  @moduledoc "Loopback TLS fixture proxy for actual publisher responses and controlled outages."
  @behaviour Plug
  import Plug.Conn
  alias Vxpipe.Console.Test.MCPBrowserOutages

  @request_headers ~w(accept x-vxpipe-version if-none-match)
  @response_headers ~w(content-type etag cache-control vary retry-after)

  @impl true
  def init(options), do: options

  @impl true
  def call(%{method: "GET", path_info: ["v1" | _]} = conn, options) do
    case MCPBrowserOutages.request(options.state) do
      {"unavailable", _} -> fault(conn, 503)
      {"rate_limited", _} -> conn |> put_resp_header("retry-after", "60") |> fault(429)
      {"healthy", upstream} -> forward(conn, upstream, options)
    end
  end

  def call(conn, _options), do: send_resp(conn, 404, "")

  defp forward(conn, upstream, options) do
    suffix = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    headers = Enum.filter(conn.req_headers, fn {key, _} -> key in @request_headers end)

    request = [
      url: upstream <> conn.request_path <> suffix,
      headers: headers,
      redirect: false,
      retry: false,
      decode_body: false,
      compressed: false,
      receive_timeout: 5_000,
      finch: [
        request_timeout: 5_000,
        pool_timeout: 5_000,
        conn_opts: [transport_opts: [timeout: 5_000]]
      ],
      into: &receive_chunk/2
    ]

    case Req.get(Keyword.merge(request, Map.get(options, :http_options, []))) do
      {:ok, %{body: body, status: status} = response} when is_binary(body) ->
        Enum.reduce(@response_headers, conn, fn key, acc ->
          case Req.Response.get_header(response, key) do
            [value | _] -> put_resp_header(acc, key, value)
            [] -> acc
          end
        end)
        |> send_resp(status, body)

      _ ->
        fault(conn, 502)
    end
  end

  defp receive_chunk({:data, data}, {request, response}) do
    body = response.body || ""

    if byte_size(body) + byte_size(data) <= 1_048_576,
      do: {:cont, {request, %{response | body: body <> data}}},
      else: {:halt, {request, %{response | body: :too_large}}}
  end

  defp fault(conn, status),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, "{\"error\":\"controlled_directory_outage\"}")
end
