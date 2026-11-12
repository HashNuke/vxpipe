defmodule Vxpipe.Gateway.MCP.Protocol do
  @moduledoc "Application request limits and exposed methods; ExMCP owns version negotiation."

  @methods ["initialize", "notifications/initialized", "ping", "tools/list", "tools/call"]

  def validate(%{"id" => id} = request) do
    if valid_id?(id),
      do: validate_method(request),
      else: {:error, -32600, "Invalid request ID"}
  end

  def validate(request), do: validate_method(request)

  defp validate_method(%{"method" => method} = request) do
    params = Map.get(request, "params", %{})

    cond do
      method not in @methods ->
        {:error, -32601, "Method not found"}

      not is_map(params) ->
        {:error, -32602, "Invalid params"}

      true ->
        :ok
    end
  end

  defp validate_method(_request), do: :ok

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
end
