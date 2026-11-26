defmodule Vxpipe.Console.CallRecordingController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  alias Vxpipe.Console.{CallRecording, RecordingMatroska, RecordingResponse, RecordingWave}

  def show(conn, %{"artifact_id" => artifact_id, "call_id" => call_id}) do
    with {:ok, source} <-
           CallRecording.open(conn.assigns.call_read_access, call_id, artifact_id),
         {:ok, wave} <- RecordingWave.new(source) do
      RecordingResponse.stream(conn, wave)
    else
      {:error, reason} when reason in [:call_not_found, :call_artifact_not_found] ->
        not_found(conn)

      {:error, reason}
      when reason in [
             :recording_unavailable,
             :unsupported_recording_layout,
             :invalid_recording_source
           ] ->
        unavailable(conn)

      {:error, _reason} ->
        metadata_unavailable(conn)
    end
  end

  def download(conn, %{"call_id" => call_id}) do
    with {:ok, sources} <- CallRecording.open_all(conn.assigns.call_read_access, call_id),
         {:ok, matroska} <- RecordingMatroska.new(sources) do
      RecordingResponse.stream_matroska(conn, matroska, call_id)
    else
      {:error, reason}
      when reason in [:call_not_found, :call_artifact_not_found, :no_recording_artifacts] ->
        not_found(conn)

      {:error, reason}
      when reason in [
             :recording_unavailable,
             :unsupported_recording_layout,
             :invalid_recording_source
           ] ->
        unavailable(conn)

      {:error, _reason} ->
        metadata_unavailable(conn)
    end
  end

  defp not_found(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(404, "Recording not found.")
  end

  defp unavailable(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(409, "Recording is unavailable.")
  end

  defp metadata_unavailable(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(503, "Recording metadata is temporarily unavailable.")
  end
end
