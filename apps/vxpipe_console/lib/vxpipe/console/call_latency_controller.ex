defmodule Vxpipe.Console.CallLatencyController do
  @moduledoc "Session-authorized optional call diagnostics, separate from conversation reads."
  use Phoenix.Controller, formats: [:json]
  alias Vxpipe.Calls
  alias Vxpipe.Console.CallLatencyPresenter

  def show(conn, %{"call_id" => call_id} = params) do
    result =
      with {:ok, options} <- page_options(params),
           {:ok, report} <-
             Calls.fetch_latency_report(conn.assigns.call_read_access, call_id, options) do
        {:ok, CallLatencyPresenter.report(report)}
      end

    respond(conn, result)
  end

  def turns(conn, %{"call_id" => call_id, "run_id" => run_id} = params) do
    result =
      with {:ok, options} <- page_options(params),
           {:ok, page} <-
             Calls.fetch_latency_turns(conn.assigns.call_read_access, call_id, run_id, options) do
        {:ok, CallLatencyPresenter.turns(run_id, page)}
      end

    respond(conn, result)
  end

  defp page_options(params) do
    case Map.get(params, "limit", "50") do
      limit when is_binary(limit) and byte_size(limit) <= 3 ->
        case Integer.parse(limit) do
          {value, ""} when value in 1..100 ->
            {:ok, [limit: value, cursor: Map.get(params, "cursor")]}

          _ ->
            {:error, :invalid_latency_request}
        end

      _ ->
        {:error, :invalid_latency_request}
    end
  end

  defp respond(conn, {:ok, body}), do: respond(conn, :ok, body)

  defp respond(conn, {:error, reason}) do
    {status, code} =
      case reason do
        missing when missing in [:call_not_found, :latency_run_not_found] ->
          {:not_found, "call_diagnostics_not_found"}

        :invalid_latency_request ->
          {:bad_request, "invalid_latency_request"}

        _ ->
          {:service_unavailable, "call_diagnostics_unavailable"}
      end

    respond(conn, status, %{error: %{code: code}})
  end

  defp respond(conn, status, body) do
    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "private, no-store")
    |> json(body)
  end
end
