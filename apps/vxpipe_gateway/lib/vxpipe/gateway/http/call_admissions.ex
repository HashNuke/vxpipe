defmodule Vxpipe.Gateway.HTTP.CallAdmissions do
  @moduledoc false

  import Plug.Conn

  alias Vxpipe.CallEngine.Participant.Snapshot, as: ParticipantSnapshot
  alias Vxpipe.Gateway.Session.Snapshot, as: SessionSnapshot
  alias Vxpipe.Gateway.{CallAdmission, SessionSupervisor}

  @default_session_ttl_ms 300_000
  @offer_endpoint "/api/rtvi/offer"
  @preparation_fields ["initial_variables", "join_token_ttl_seconds"]
  @token_fields ["join_token_ttl_seconds"]

  def init(options) do
    if Keyword.get(options, :enabled, false) do
      %{
        backend: Keyword.get(options, :backend, {CallAdmission, []}),
        clock: Keyword.get(options, :clock, &DateTime.utc_now/0),
        enabled: true,
        projection_supervisor:
          Keyword.get(
            options,
            :projection_supervisor,
            Vxpipe.Gateway.AdmissionTaskSupervisor
          ),
        session_ttl_ms: Keyword.get(options, :session_ttl_ms, @default_session_ttl_ms)
      }
    else
      %{enabled: false}
    end
  end

  def prepare(conn, %{enabled: false}, _tenant_key, _participant_key),
    do: send_resp(conn, 404, "not found")

  def prepare(conn, options, tenant_key, participant_key) do
    with {:ok, secret} <- bearer(conn),
         {:ok, principal} <- backend(options, :authenticate, [tenant_key, secret]),
         {:ok, input} <- preparation_input(conn.body_params),
         {:ok, call, token} <-
           backend(options, :prepare, [
             principal,
             participant_key,
             input.initial_variables,
             input.ttl_seconds
           ]) do
      send_json(conn, 201, %{
        "call" => prepared_call_public(call),
        "join_token" => token_public(token)
      })
    else
      {:error, reason} -> send_management_error(conn, reason)
    end
  end

  def issue_token(conn, %{enabled: false}, _tenant_key, _call_id, _participant_key),
    do: send_resp(conn, 404, "not found")

  def issue_token(conn, options, tenant_key, call_id, participant_key) do
    with {:ok, secret} <- bearer(conn),
         {:ok, principal} <- backend(options, :authenticate, [tenant_key, secret]),
         {:ok, ttl_seconds} <- token_input(conn.body_params),
         {:ok, token} <-
           backend(options, :issue_token, [principal, call_id, participant_key, ttl_seconds]) do
      send_json(conn, 201, %{
        "call_id" => token.call_id,
        "participant_key" => token.participant_key,
        "join_token" => token_public(token)
      })
    else
      {:error, reason} -> send_management_error(conn, reason)
    end
  end

  def create_session(conn, %{enabled: false}, _tenant_key, _call_id, _participant_key),
    do: send_resp(conn, 404, "not found")

  def create_session(conn, options, tenant_key, call_id, participant_key) do
    scope = %{tenant_key: tenant_key, call_id: call_id, participant_key: participant_key}

    with {:ok, token} <- bearer(conn),
         :ok <- empty_input(conn.body_params),
         {:ok, claim} <- backend(options, :claim_token, [token, scope]) do
      start_session(conn, options, claim)
    else
      {:error, reason} -> send_join_error(conn, reason)
    end
  end

  defp start_session(conn, options, claim) do
    case backend(options, :start_call, [claim]) do
      {:ok, room, participant} ->
        started_at = options.clock.()
        project(options, :mark_started, [claim, room.incarnation_id, started_at])
        send_live_session(conn, options, claim, room.incarnation_id, participant, started_at)

      {:joined, participant} ->
        send_live_session(
          conn,
          options,
          claim,
          claim.call.incarnation_id,
          participant,
          claim.call.started_at
        )

      {:transfer_pending, participant} ->
        send_pending_transfer_session(conn, options, claim, participant)

      {:started, room} ->
        started_at = options.clock.()
        project(options, :mark_started, [claim, room.incarnation_id, started_at])

        send_error(
          conn,
          503,
          "session_start_failed",
          "The gateway session could not be started.",
          true
        )

      {:error, _reason} ->
        project(options, :mark_failed, [claim, :room_start_failed])

        send_error(
          conn,
          503,
          "call_start_failed",
          "The call could not be started.",
          true
        )

      {:join_error, _reason} ->
        send_error(
          conn,
          503,
          "participant_start_failed",
          "The participant could not be started.",
          true
        )
    end
  end

  defp send_live_session(conn, options, claim, incarnation_id, participant, started_at) do
    case issue_session(options, claim, incarnation_id, participant) do
      {:ok, session} ->
        send_json(conn, 201, %{
          "call" => %{
            "call_id" => claim.call.id,
            "started_at" => DateTime.to_iso8601(started_at),
            "state" => "running"
          },
          "participant" => ParticipantSnapshot.to_public(participant),
          "session" => session_public(session)
        })

      {:error, _reason} ->
        send_error(
          conn,
          503,
          "session_start_failed",
          "The gateway session could not be started.",
          true
        )
    end
  end

  defp send_pending_transfer_session(conn, options, claim, participant) do
    case issue_pending_transfer_session(options, claim, participant) do
      {:ok, session} ->
        send_json(conn, 201, %{
          "call" => %{
            "call_id" => claim.call.id,
            "started_at" => DateTime.to_iso8601(claim.call.started_at),
            "state" => "running"
          },
          "participant" => %{
            "incarnation_id" => claim.call.incarnation_id,
            "participant_id" => participant.participant_id,
            "role" => Atom.to_string(participant.kind),
            "room_id" => claim.call.room_id,
            "state" => "pending_transfer"
          },
          "session" => session_public(session)
        })

      {:error, _reason} ->
        send_error(
          conn,
          503,
          "session_start_failed",
          "The gateway session could not be started.",
          true
        )
    end
  end

  defp issue_session(options, claim, incarnation_id, participant) do
    SessionSupervisor.issue(
      [
        tenant_id: participant.tenant_id,
        actor_id: claim.call.plan.actor_id,
        room_id: participant.room_id,
        incarnation_id: incarnation_id,
        participant_id: participant.participant_id,
        tool_visibility: claim.call.plan.tool_visibility
      ],
      options.session_ttl_ms
    )
  end

  defp issue_pending_transfer_session(options, claim, participant) do
    SessionSupervisor.issue(
      [
        tenant_id: claim.call.tenant_key,
        actor_id: claim.call.plan.actor_id,
        room_id: claim.call.room_id,
        incarnation_id: claim.call.incarnation_id,
        participant_id: participant.participant_id,
        tool_visibility: claim.call.plan.tool_visibility
      ],
      options.session_ttl_ms
    )
  end

  defp project(options, function, arguments) do
    _result =
      Task.Supervisor.start_child(options.projection_supervisor, fn ->
        try do
          _result = backend(options, function, arguments)
          :ok
        rescue
          _exception -> :ok
        catch
          _kind, _reason -> :ok
        end
      end)

    :ok
  end

  defp preparation_input(body) when is_map(body) do
    with :ok <- supported_fields(body, @preparation_fields),
         initial_variables when is_map(initial_variables) <-
           Map.get(body, "initial_variables", %{}),
         {:ok, ttl_seconds} <- ttl_seconds(Map.get(body, "join_token_ttl_seconds")) do
      {:ok, %{initial_variables: initial_variables, ttl_seconds: ttl_seconds}}
    else
      _invalid -> {:error, :invalid_request}
    end
  end

  defp preparation_input(_invalid), do: {:error, :invalid_request}

  defp token_input(body) when is_map(body) do
    with :ok <- supported_fields(body, @token_fields) do
      ttl_seconds(Map.get(body, "join_token_ttl_seconds"))
    end
  end

  defp token_input(_invalid), do: {:error, :invalid_request}

  defp empty_input(body) when body == %{}, do: :ok
  defp empty_input(_body), do: {:error, :invalid_request}

  defp supported_fields(body, fields) do
    if Enum.all?(Map.keys(body), &(&1 in fields)), do: :ok, else: {:error, :invalid_request}
  end

  defp ttl_seconds(nil), do: {:ok, nil}
  defp ttl_seconds(seconds) when is_integer(seconds) and seconds >= 300, do: {:ok, seconds}
  defp ttl_seconds(_invalid), do: {:error, :invalid_request}

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> secret] when byte_size(secret) > 0 -> {:ok, secret}
      _missing_or_invalid -> {:error, :missing_credentials}
    end
  end

  defp backend(options, function, arguments) do
    {module, context} = options.backend
    apply(module, function, [context | arguments])
  end

  defp prepared_call_public(call) do
    %{
      "call_id" => call.id,
      "created_at" => DateTime.to_iso8601(call.created_at),
      "started_at" => nil,
      "state" => "prepared"
    }
  end

  defp token_public(token) do
    %{
      "token" => token.secret,
      "expires_at" => DateTime.to_iso8601(token.expires_at)
    }
  end

  defp session_public(session) do
    session
    |> SessionSnapshot.to_public()
    |> Map.put("transport", %{
      "type" => "smallwebrtc",
      "endpoint" => @offer_endpoint,
      "request_data" => %{"session_id" => session.session_id}
    })
  end

  defp send_management_error(conn, reason)
       when reason in [:missing_credentials, :invalid_api_key] do
    send_error(conn, 401, "invalid_api_key", "The API key is invalid.", false)
  end

  defp send_management_error(conn, :not_authorized) do
    send_error(conn, 403, "not_authorized", "The API key cannot manage calls.", false)
  end

  defp send_management_error(conn, reason)
       when reason in [:not_found, :route_unavailable, :participant_not_found] do
    send_error(conn, 404, "call_route_not_found", "The call route does not exist.", false)
  end

  defp send_management_error(conn, :invalid_request) do
    send_error(conn, 400, "invalid_request", "The request is invalid.", false)
  end

  defp send_management_error(conn, %Vxpipe.CallEngine.Error{} = error) do
    send_json(conn, 400, %{"error" => Vxpipe.CallEngine.Error.to_public(error)})
  end

  defp send_management_error(conn, reason)
       when reason in [
              :call_unavailable,
              :participant_admission_pending,
              :participant_admission_unavailable,
              :participant_not_entry_caller
            ] do
    send_error(conn, 409, "call_unavailable", "The call cannot accept that request.", false)
  end

  defp send_management_error(conn, _reason) do
    send_error(conn, 503, "call_management_unavailable", "Call management is unavailable.", true)
  end

  defp send_join_error(conn, :invalid_request) do
    send_error(conn, 400, "invalid_request", "The request is invalid.", false)
  end

  defp send_join_error(conn, reason)
       when reason in [
              :missing_credentials,
              :token_not_found,
              :token_expired,
              :token_scope_mismatch
            ] do
    send_error(conn, 401, "invalid_join_token", "The join token is invalid or expired.", false)
  end

  defp send_join_error(conn, reason)
       when reason in [
              :call_unavailable,
              :participant_admission_pending,
              :participant_admission_unavailable,
              :token_already_claimed
            ] do
    send_error(conn, 409, "admission_unavailable", "The participant cannot be admitted.", false)
  end

  defp send_join_error(conn, _reason) do
    send_error(conn, 503, "admission_unavailable", "Call admission is unavailable.", true)
  end

  defp send_error(conn, status, code, message, retryable) do
    send_json(conn, status, %{
      "error" => %{
        "code" => code,
        "message" => message,
        "retryable" => retryable,
        "details" => %{}
      }
    })
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
