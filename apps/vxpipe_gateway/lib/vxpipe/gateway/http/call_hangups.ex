defmodule Vxpipe.Gateway.HTTP.CallHangups do
  @moduledoc "HTTP adapter for authorized durable whole-call shutdown."
  import Plug.Conn
  alias Vxpipe.Calls
  alias Vxpipe.Gateway.{CallAdmission, CallHangup, CallHangupErrors}
  alias Vxpipe.Gateway.HTTP.ProductAuthentication

  def init(options) do
    context =
      case Keyword.get(options, :backend, {CallAdmission, []}) do
        {CallAdmission, context} when is_list(context) -> context
        _custom -> []
      end

    %{
      enabled: Keyword.get(options, :enabled, false),
      browser_auth: Keyword.get(options, :browser_auth),
      calls_options: Keyword.get(options, :calls_options, context)
    }
  end

  def request(conn, %{enabled: false}, _tenant, _call), do: send_resp(conn, 404, "not found")

  def request(conn, options, tenant, call) do
    case safely(fn ->
           ProductAuthentication.authenticate(
             conn,
             options.browser_auth,
             &Calls.authenticate_api_key(&1, options.calls_options)
           )
         end) do
      {:ok, conn, actor} ->
        result =
          if conn.body_params == %{},
            do: CallHangup.request(actor, tenant, call, options.calls_options),
            else: {:error, :invalid_request}

        respond(conn, result)

      {:halt, conn} ->
        conn

      error ->
        respond(conn, error)
    end
  end

  defp respond(conn, {:ok, result}), do: json(conn, 200, result)

  defp respond(conn, {:error, reason}) do
    {status, error} = CallHangupErrors.response(reason)
    json(conn, status, %{error: error})
  end

  defp respond(conn, _invalid), do: respond(conn, {:error, :call_hangup_unavailable})

  defp json(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end

  defp safely(operation) do
    operation.()
  rescue
    error in Plug.CSRFProtection.InvalidCSRFTokenError -> reraise error, __STACKTRACE__
    _error -> {:error, :call_hangup_unavailable}
  catch
    _kind, _reason -> {:error, :call_hangup_unavailable}
  end
end
