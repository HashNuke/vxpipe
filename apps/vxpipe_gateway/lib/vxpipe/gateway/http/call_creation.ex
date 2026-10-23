defmodule Vxpipe.Gateway.HTTP.CallCreation do
  @moduledoc "HTTP adapter for the shared published-spec call workflow."

  import Plug.Conn
  alias Vxpipe.Gateway.{CallAdmission, CallCreation, CallCreationErrors, CallCreationJSON}
  alias Vxpipe.Gateway.HTTP.ProductAuthentication

  def init(options) do
    backend =
      case Keyword.get(options, :backend, {CallAdmission, []}) do
        {CallAdmission, context} -> {CallCreation, context}
        custom -> custom
      end

    %{
      enabled: Keyword.get(options, :enabled, false),
      browser_auth: Keyword.get(options, :browser_auth),
      backend: backend
    }
  end

  def create(conn, %{enabled: false}, _tenant, _specification),
    do: send_resp(conn, 404, "not found")

  def create(conn, options, tenant, specification) do
    case safely(fn ->
           ProductAuthentication.authenticate(conn, options.browser_auth, fn secret ->
             backend(options, :authenticate, [secret])
           end)
         end) do
      {:ok, conn, actor} ->
        result =
          with {:ok, variables, to} <- request(conn.body_params),
               {:ok, key} <- idempotency_key(conn) do
            backend(options, :create, [actor, tenant, specification, variables, to, key])
          end

        respond(conn, result)

      {:halt, conn} ->
        conn

      {:error, reason} ->
        respond(conn, {:error, reason})

      _invalid ->
        respond(conn, {:error, :call_management_unavailable})
    end
  end

  defp request(body) when is_map(body) do
    variables = Map.get(body, "variables", %{})
    to = Map.get(body, "to")

    if is_map(variables) and (is_nil(to) or is_binary(to)) and
         Enum.all?(Map.keys(body), &(&1 in ["variables", "to"])),
       do: {:ok, variables, to},
       else: {:error, :invalid_request}
  end

  defp request(_body), do: {:error, :invalid_request}

  defp idempotency_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [] -> {:ok, nil}
      [key] -> {:ok, key}
      _multiple -> {:error, :invalid_idempotency_key}
    end
  end

  defp backend(options, operation, arguments) do
    safely(fn ->
      {module, context} = options.backend
      apply(module, operation, [context | arguments])
    end)
  end

  defp safely(operation) do
    operation.()
  rescue
    error in Plug.CSRFProtection.InvalidCSRFTokenError -> reraise error, __STACKTRACE__
    _error -> {:error, :call_management_unavailable}
  catch
    _kind, _reason -> {:error, :call_management_unavailable}
  end

  defp respond(conn, {:ok, outcome, call}) when outcome in [:created, :replayed] do
    status = if outcome == :created, do: 201, else: 200
    json(conn, status, %{call: CallCreationJSON.call(call)})
  end

  defp respond(conn, {:error, reason}) do
    {status, error} = CallCreationErrors.response(reason)
    json(conn, status, %{error: error})
  end

  defp respond(conn, _invalid), do: respond(conn, {:error, :call_management_unavailable})

  defp json(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
