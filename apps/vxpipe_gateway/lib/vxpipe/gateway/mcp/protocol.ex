defmodule Vxpipe.Gateway.MCP.Protocol do
  @moduledoc false

  @version "2025-11-25"
  @methods ["initialize", "notifications/initialized", "ping", "tools/list", "tools/call"]

  def version, do: @version

  def validate(conn, %{"id" => id} = request) do
    if valid_id?(id),
      do: validate_method(conn, request),
      else: {:error, -32600, "Invalid request ID"}
  end

  def validate(conn, request), do: validate_method(conn, request)

  defp validate_method(conn, %{"method" => method} = request) do
    params = Map.get(request, "params", %{})

    cond do
      method not in @methods ->
        {:error, -32601, "Method not found"}

      not is_map(params) ->
        {:error, -32602, "Invalid params"}

      modern_metadata?(params) ->
        {:error, -32600, "Unsupported protocol version"}

      not valid_version?(conn, method, params) ->
        {:error, -32600, "Unsupported protocol version"}

      true ->
        :ok
    end
  end

  defp validate_method(_conn, _request), do: :ok

  def response_id(request) do
    id = Map.get(request, "id")
    if valid_id?(id), do: id, else: nil
  end

  def notification?(%{"jsonrpc" => "2.0", "method" => method} = request)
      when is_binary(method) do
    params = Map.get(request, "params", %{})
    not Map.has_key?(request, "id") and (is_map(params) or is_list(params))
  end

  def notification?(_request), do: false

  defp valid_id?(id) when is_binary(id), do: byte_size(id) <= 256
  defp valid_id?(id) when is_integer(id), do: abs(id) <= 9_007_199_254_740_991
  defp valid_id?(_id), do: false

  def valid_delete?(conn),
    do: Plug.Conn.get_req_header(conn, "mcp-protocol-version") == [@version]

  defp valid_version?(conn, "initialize", params) do
    Map.get(params, "protocolVersion") == @version and
      Plug.Conn.get_req_header(conn, "mcp-protocol-version") in [[], [@version]]
  end

  defp valid_version?(conn, _method, _params), do: valid_delete?(conn)

  defp modern_metadata?(%{"_meta" => meta}) when is_map(meta) do
    Map.has_key?(meta, "io.modelcontextprotocol/protocolVersion") or
      Map.has_key?(meta, "io.modelcontextprotocol/clientCapabilities")
  end

  defp modern_metadata?(_params), do: false
end
