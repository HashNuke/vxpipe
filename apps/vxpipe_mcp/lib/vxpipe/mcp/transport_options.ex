defmodule Vxpipe.MCP.TransportOptions do
  @moduledoc false

  @defaults [
    max_request_bytes: 262_144,
    max_response_bytes: 262_144,
    max_stream_buffer_bytes: 262_144,
    dns_timeout_ms: 1_000,
    connect_timeout_ms: 5_000,
    request_timeout_ms: 30_000,
    stream_handshake_timeout_ms: 15_000,
    stream_idle_timeout_ms: 60_000
  ]

  @type limit_name ::
          :connect_timeout_ms
          | :dns_timeout_ms
          | :max_request_bytes
          | :max_response_bytes
          | :max_stream_buffer_bytes
          | :request_timeout_ms
          | :stream_handshake_timeout_ms
          | :stream_idle_timeout_ms
  @type error :: {:invalid_limit, limit_name() | term()}

  @spec build(keyword()) :: {:ok, keyword()} | {:error, error()}
  def build(config) when is_list(config) do
    limits = Keyword.get(config, :limits, [])

    with :ok <- validate_keyword(limits),
         :ok <- validate_known(limits),
         merged = Keyword.merge(@defaults, limits),
         :ok <- validate_positive(merged) do
      {:ok,
       [
         max_request_bytes: merged[:max_request_bytes],
         max_response_bytes: merged[:max_response_bytes],
         max_stream_buffer_bytes: merged[:max_stream_buffer_bytes],
         dns_timeout_ms: merged[:dns_timeout_ms],
         timeout: merged[:connect_timeout_ms],
         request_timeout: merged[:request_timeout_ms],
         stream_handshake_timeout: merged[:stream_handshake_timeout_ms],
         stream_idle_timeout: merged[:stream_idle_timeout_ms]
       ]}
    end
  end

  defp validate_keyword(value) do
    if Keyword.keyword?(value), do: :ok, else: {:error, {:invalid_limit, :limits}}
  end

  defp validate_known(limits) do
    case Enum.find(Keyword.keys(limits), &(&1 not in Keyword.keys(@defaults))) do
      nil -> :ok
      unknown -> {:error, {:invalid_limit, unknown}}
    end
  end

  defp validate_positive(limits) do
    case Enum.find(limits, fn {_name, value} -> not (is_integer(value) and value > 0) end) do
      nil -> :ok
      {name, _value} -> {:error, {:invalid_limit, name}}
    end
  end
end
