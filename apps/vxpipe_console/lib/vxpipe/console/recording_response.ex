defmodule Vxpipe.Console.RecordingResponse do
  @moduledoc "Streams a bounded virtual recording file with single-range semantics."

  import Plug.Conn

  alias Vxpipe.Console.{HTTPByteRange, RecordingWave}

  @maximum_chunk_bytes 1_048_576

  @spec stream(Plug.Conn.t(), RecordingWave.t()) :: Plug.Conn.t()
  def stream(conn, %RecordingWave{} = wave) do
    with {:ok, range_header} <- range_header(conn),
         {:ok, selection} <- HTTPByteRange.parse(range_header, wave.total_bytes),
         {:ok, first_chunk} <- read(wave, selection.first, selection.last) do
      conn
      |> response_headers(selection, wave.total_bytes)
      |> send_chunked(selection.status)
      |> stream_chunks(wave, selection.last, selection.first, first_chunk)
    else
      {:error, :range_not_satisfiable} -> range_not_satisfiable(conn, wave.total_bytes)
      {:error, _reason} -> storage_unavailable(conn)
    end
  end

  defp range_header(conn) do
    case get_req_header(conn, "range") do
      [] -> {:ok, nil}
      [header] -> {:ok, header}
      _multiple -> {:error, :range_not_satisfiable}
    end
  end

  defp response_headers(conn, selection, total_bytes) do
    content_length = selection.last - selection.first + 1

    conn
    |> put_resp_header("accept-ranges", "bytes")
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("content-disposition", "inline")
    |> put_resp_header("content-length", Integer.to_string(content_length))
    |> put_resp_header("content-type", "audio/wav")
    |> maybe_put_content_range(selection, total_bytes)
  end

  defp maybe_put_content_range(conn, %{status: 200}, _total_bytes), do: conn

  defp maybe_put_content_range(conn, selection, total_bytes) do
    put_resp_header(
      conn,
      "content-range",
      "bytes #{selection.first}-#{selection.last}/#{total_bytes}"
    )
  end

  defp stream_chunks(conn, wave, last, offset, payload) do
    case chunk(conn, payload) do
      {:ok, conn} ->
        next_offset = offset + byte_size(payload)

        if next_offset > last do
          conn
        else
          stream_next(conn, wave, last, next_offset)
        end

      {:error, _reason} ->
        halt(conn)
    end
  end

  defp stream_next(conn, wave, last, offset) do
    case read(wave, offset, last) do
      {:ok, payload} -> stream_chunks(conn, wave, last, offset, payload)
      {:error, _reason} -> halt(conn)
    end
  end

  defp read(wave, offset, last) do
    maximum_bytes = min(@maximum_chunk_bytes, last - offset + 1)

    case RecordingWave.read_chunk(wave, offset, maximum_bytes) do
      {:ok, payload}
      when is_binary(payload) and byte_size(payload) > 0 and
             byte_size(payload) <= maximum_bytes ->
        {:ok, payload}

      _invalid ->
        {:error, :recording_read_failed}
    end
  end

  defp range_not_satisfiable(conn, total_bytes) do
    conn
    |> put_resp_header("accept-ranges", "bytes")
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("content-range", "bytes */#{total_bytes}")
    |> send_resp(416, "Requested recording range is unavailable.")
  end

  defp storage_unavailable(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(502, "Recording storage is temporarily unavailable.")
  end
end
