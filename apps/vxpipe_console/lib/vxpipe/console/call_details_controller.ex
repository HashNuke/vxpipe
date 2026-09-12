defmodule Vxpipe.Console.CallDetailsController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  alias Vxpipe.Console.CallDetails

  @filename_pattern ~r/\Adetails-\d{17}\.json\z/

  def show(conn, %{"call_id" => call_id, "publication_id" => publication_id}) do
    with {:ok, document} <-
           CallDetails.fetch(conn.assigns.operator_principal, call_id, publication_id),
         :ok <- validate_filename(document.filename) do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{document.filename}"))
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(200, document.contents)
    else
      {:error, :call_details_not_found} -> not_found(conn)
      {:error, _reason} -> unavailable(conn)
    end
  end

  defp validate_filename(filename) when is_binary(filename) do
    if Regex.match?(@filename_pattern, filename),
      do: :ok,
      else: {:error, :invalid_call_details_response}
  end

  defp validate_filename(_filename), do: {:error, :invalid_call_details_response}

  defp not_found(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(404, "Call details not found.")
  end

  defp unavailable(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(503, "Call details are temporarily unavailable.")
  end
end
