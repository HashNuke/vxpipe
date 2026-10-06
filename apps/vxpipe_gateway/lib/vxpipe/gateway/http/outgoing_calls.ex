defmodule Vxpipe.Gateway.HTTP.OutgoingCalls do
  @moduledoc false

  import Plug.Conn
  alias Vxpipe.Gateway.{CallAdmission, OutgoingCallAdmission}

  def init(options) do
    backend =
      case Keyword.get(options, :backend, {CallAdmission, []}) do
        {CallAdmission, context} -> {OutgoingCallAdmission, context}
        custom -> custom
      end

    %{enabled: Keyword.get(options, :enabled, false), backend: backend}
  end

  def create(conn, %{enabled: false}, _tenant, _specification),
    do: send_resp(conn, 404, "not found")

  def create(conn, options, tenant, specification) do
    with {:ok, secret} <- bearer(conn),
         {:ok, principal} <- backend(options, :authenticate, [tenant, secret]),
         {:ok, variables} <- variables(conn.body_params),
         {:ok, key} <- idempotency_key(conn) do
      case backend(options, :claim, [principal, specification, variables, key]) do
        {:ok, call} ->
          case backend(options, :start, [call]) do
            {:ok, call} -> send_json(conn, 201, %{"call" => public_call(call)})
            {:error, reason} -> error(conn, reason)
          end

        {:duplicate, %{state: :failed, terminal_reason: :startup_unknown}} ->
          error(conn, :outgoing_submission_unknown)

        {:duplicate, %{state: :failed}} ->
          error(conn, :outgoing_call_start_failed)

        {:duplicate, call} ->
          send_json(conn, 200, %{"call" => public_call(call)})

        {:error, reason} ->
          error(conn, reason)
      end
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> secret] when byte_size(secret) > 0 -> {:ok, secret}
      _invalid -> {:error, :invalid_api_key}
    end
  end

  defp variables(body) when is_map(body) do
    value = Map.get(body, "initial_variables", %{})

    if is_map(value) and Enum.all?(Map.keys(body), &(&1 == "initial_variables")),
      do: {:ok, value},
      else: {:error, :invalid_request}
  end

  defp variables(_body), do: {:error, :invalid_request}

  defp idempotency_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [] -> {:ok, nil}
      [key] -> {:ok, key}
      _multiple -> {:error, :invalid_idempotency_key}
    end
  end

  defp public_call(call) do
    %{
      "id" => call.id,
      "call_spec_id" => call.call_spec_id,
      "revision" => call.call_spec_revision,
      "state" => Atom.to_string(call.state),
      "outgoing_outcome" => call.outgoing_outcome && Atom.to_string(call.outgoing_outcome)
    }
  end

  defp backend(options, operation, arguments) do
    {module, context} = options.backend
    apply(module, operation, [context | arguments])
  end

  defp error(conn, %Vxpipe.CallEngine.Error{} = reason),
    do: send_json(conn, 422, %{"error" => Vxpipe.CallEngine.Error.to_public(reason)})

  defp error(conn, reason) do
    {status, code, message, retryable} =
      case reason do
        :invalid_api_key ->
          {401, "invalid_api_key", "The API key is invalid.", false}

        forbidden when forbidden in [:not_authorized, :insufficient_scope] ->
          {403, "not_authorized", "The API key cannot manage calls.", false}

        :not_found ->
          {404, "call_spec_not_found", "The call spec does not exist.", false}

        :call_spec_not_published ->
          {422, "call_spec_not_published", "The call spec has no published revision.", false}

        :call_spec_not_outgoing ->
          {422, "call_spec_not_outgoing", "The call spec cannot start an outgoing call.", false}

        :idempotency_conflict ->
          {409, "idempotency_conflict", "The key was used for a different request.", false}

        invalid
        when invalid in [:invalid_request, :invalid_idempotency_key, :invalid_outgoing_call] ->
          {400, "invalid_request", "The request is invalid.", false}

        :outgoing_call_start_failed ->
          {503, "outgoing_call_start_failed", "The outgoing call could not be started.", false}

        :outgoing_submission_unknown ->
          {503, "outgoing_submission_unknown", "The dial submission could not be confirmed.",
           false}

        _unavailable ->
          {503, "call_management_unavailable", "Call management is unavailable.", true}
      end

    send_json(conn, status, %{
      "error" => %{
        "code" => code,
        "message" => message,
        "retryable" => retryable,
        "details" => %{}
      }
    })
  end

  defp send_json(conn, status, body),
    do: conn |> put_resp_content_type("application/json") |> send_resp(status, JSON.encode!(body))
end
