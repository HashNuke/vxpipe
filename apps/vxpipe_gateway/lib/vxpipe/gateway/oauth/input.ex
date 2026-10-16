defmodule Vxpipe.Gateway.OAuth.Input do
  @moduledoc "Bounded OAuth request decoding before credentials reach the protocol backend."

  import Plug.Conn
  @limit 16_384

  def read(conn, operation) do
    with :ok <- content_type(conn, operation) do
      case read_body(conn, length: @limit, read_length: @limit, read_timeout: 5_000) do
        {:ok, body, conn} -> decoded_body(body, operation, conn)
        {:more, _body, conn} -> {:error, 413, conn}
        {:error, :timeout} -> {:error, 408, conn}
        _invalid -> {:error, 400, conn}
      end
    else
      {:error, :unsupported_media_type} -> {:error, 415, conn}
    end
  end

  defp decoded_body(body, _operation, conn) when byte_size(body) > @limit,
    do: {:error, 413, conn}

  defp decoded_body(body, operation, conn) do
    case decode(body, operation) do
      {:ok, params} -> {:ok, params, conn}
      {:error, _reason} -> {:error, 400, conn}
    end
  end

  defp content_type(conn, operation) do
    expected = if operation == :register, do: "json", else: "x-www-form-urlencoded"

    case get_req_header(conn, "content-type") do
      [type] ->
        case Plug.Conn.Utils.content_type(type) do
          {:ok, "application", ^expected, _params} -> :ok
          _invalid -> {:error, :unsupported_media_type}
        end

      _invalid ->
        {:error, :unsupported_media_type}
    end
  end

  defp decode(body, :register) do
    decoders = [
      object_start: fn _acc -> %{} end,
      object_push: fn key, value, acc ->
        if Map.has_key?(acc, key), do: throw(:duplicate_parameter), else: Map.put(acc, key, value)
      end,
      object_finish: fn acc, previous -> {acc, previous} end
    ]

    case JSON.decode(body, nil, decoders) do
      {params, nil, rest} when is_map(params) ->
        if String.trim(rest) == "", do: {:ok, params}, else: {:error, :invalid_request}

      _invalid ->
        {:error, :invalid_request}
    end
  catch
    :duplicate_parameter -> {:error, :invalid_request}
  end

  defp decode(body, _form) do
    if String.valid?(body) and not Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, body) do
      body
      |> URI.query_decoder()
      |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, params} ->
        if Map.has_key?(params, key) or not String.valid?(key) or not String.valid?(value),
          do: {:halt, {:error, :invalid_request}},
          else: {:cont, {:ok, Map.put(params, key, value)}}
      end)
    else
      {:error, :invalid_request}
    end
  rescue
    _error -> {:error, :invalid_request}
  end
end
