defmodule Vxpipe.Gateway.HTTP.CallJoinTokens do
  @moduledoc "Authenticated HTTP token issuance for a call's pinned web participants."

  import Plug.Conn

  alias Vxpipe.Calls
  alias Vxpipe.Gateway.{CallAdmission, CallJoinTokenErrors, CallJoinTokenJSON}
  alias Vxpipe.Gateway.HTTP.ProductAuthentication

  def init(options) do
    calls_options =
      case Keyword.get(options, :backend, {CallAdmission, []}) do
        {CallAdmission, context} when is_list(context) -> context
        _custom -> []
      end

    %{
      enabled: Keyword.get(options, :enabled, false),
      browser_auth: Keyword.get(options, :browser_auth),
      calls_options: Keyword.get(options, :calls_options, calls_options)
    }
  end

  def issue(conn, options, tenant, call), do: perform(conn, options, tenant, call, :optional)

  def issue_explicit(conn, options, tenant, call, participant),
    do: perform(conn, options, tenant, call, {:explicit, participant})

  defp perform(conn, %{enabled: false}, _tenant, _call, _selector),
    do: send_resp(conn, 404, "not found")

  defp perform(conn, options, tenant, call, selector) do
    case safely(fn ->
           ProductAuthentication.authenticate(conn, options.browser_auth, fn secret ->
             Calls.authenticate_api_key(secret, options.calls_options)
           end)
         end) do
      {:ok, conn, actor} ->
        result =
          safely(fn ->
            with {:ok, participant, ttl} <- input(conn.body_params, selector) do
              Calls.issue_call_join_token(
                actor,
                tenant,
                call,
                participant,
                Keyword.put(options.calls_options, :join_token_ttl_seconds, ttl)
              )
            end
          end)

        respond(conn, result)

      {:halt, conn} ->
        conn

      error ->
        respond(conn, error)
    end
  end

  defp input(body, selector) when is_map(body) do
    fields =
      if selector == :optional,
        do: ["participant_key", "join_token_ttl_seconds"],
        else: ["join_token_ttl_seconds"]

    participant =
      case selector do
        :optional -> Map.get(body, "participant_key")
        {:explicit, participant} -> participant
      end

    ttl = Map.get(body, "join_token_ttl_seconds", 300)
    omitted? = selector == :optional and not Map.has_key?(body, "participant_key")

    if Enum.all?(Map.keys(body), &(&1 in fields)) and
         (omitted? or valid_participant?(participant)) and is_integer(ttl) and
         ttl in 300..86_400,
       do: {:ok, participant, ttl},
       else: {:error, :invalid_request}
  end

  defp input(_body, _selector), do: {:error, :invalid_request}

  defp valid_participant?(key) when is_binary(key) and byte_size(key) in 1..128,
    do: String.valid?(key) and not String.contains?(key, [<<0>>, "\n", "\r"])

  defp valid_participant?(_key), do: false

  defp respond(conn, {:ok, token}), do: json(conn, 201, CallJoinTokenJSON.issued(token))

  defp respond(conn, {:error, reason}) do
    {status, error} = CallJoinTokenErrors.response(reason)
    json(conn, status, %{error: error})
  end

  defp respond(conn, _invalid), do: respond(conn, {:error, :repository_unavailable})

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
    _error -> {:error, :repository_unavailable}
  catch
    _kind, _reason -> {:error, :repository_unavailable}
  end
end
