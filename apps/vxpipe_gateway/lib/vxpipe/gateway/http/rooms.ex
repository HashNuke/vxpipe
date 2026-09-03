defmodule Vxpipe.Gateway.HTTP.Rooms do
  @moduledoc false

  import Plug.Conn

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{CreateRoom, JoinParticipant}
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Participant.Snapshot, as: ParticipantSnapshot
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.Gateway.Session.Snapshot, as: SessionSnapshot
  alias Vxpipe.Gateway.SessionSupervisor

  @create_scope "rooms:create"
  @join_scope "rooms:join"
  @command_timeout_seconds 5
  @default_session_ttl_ms 300_000
  @offer_endpoint "/api/rtvi/offer"

  def init(options) do
    if Keyword.get(options, :enabled, false) do
      principal = Keyword.fetch!(options, :principal)

      %{
        enabled: true,
        tenant_id: Keyword.fetch!(principal, :tenant_id),
        actor_id: Keyword.fetch!(principal, :actor_id),
        agent: Keyword.get(options, :agent),
        scopes: Keyword.get(principal, :scopes, []),
        session_ttl_ms: Keyword.get(options, :session_ttl_ms, @default_session_ttl_ms)
      }
    else
      %{enabled: false}
    end
  end

  def create_session(conn, %{enabled: false}, _room_id), do: send_resp(conn, 404, "not found")

  def create_session(conn, %{enabled: true} = options, room_id) do
    if @join_scope in options.scopes do
      create_session_authorized(conn, options, room_id)
    else
      send_json(conn, 403, %{
        "error" => %{
          "code" => "not_authorized",
          "message" => "The actor cannot join rooms.",
          "retryable" => false,
          "details" => %{}
        }
      })
    end
  end

  def create(conn, %{enabled: false}), do: send_resp(conn, 404, "not found")

  def create(conn, %{enabled: true} = options) do
    if @create_scope in options.scopes do
      create_authorized(conn, options)
    else
      send_json(conn, 403, %{
        "error" => %{
          "code" => "not_authorized",
          "message" => "The actor cannot create rooms.",
          "retryable" => false,
          "details" => %{}
        }
      })
    end
  end

  defp create_authorized(conn, principal) do
    deadline = DateTime.add(DateTime.utc_now(), @command_timeout_seconds, :second)

    with {:ok, command} <-
           CreateRoom.new(
             tenant_id: principal.tenant_id,
             actor_id: principal.actor_id,
             room_id: Map.get(conn.body_params, "room_id"),
             agent: principal.agent,
             deadline: deadline
           ),
         {:ok, snapshot} <- CallEngine.create_room(command) do
      send_json(conn, 201, %{"room" => Snapshot.to_public(snapshot)})
    else
      {:error, %Error{} = error} -> send_error(conn, status(error), error)
    end
  end

  defp create_session_authorized(conn, principal, room_id) do
    deadline = DateTime.add(DateTime.utc_now(), @command_timeout_seconds, :second)

    with {:ok, command} <-
           JoinParticipant.new(
             tenant_id: principal.tenant_id,
             actor_id: principal.actor_id,
             room_id: room_id,
             role: :human,
             deadline: deadline
           ),
         {:ok, participant} <- CallEngine.join_participant(command),
         {:ok, session} <-
           SessionSupervisor.issue(
             [
               tenant_id: participant.tenant_id,
               actor_id: principal.actor_id,
               room_id: participant.room_id,
               incarnation_id: participant.incarnation_id,
               participant_id: participant.participant_id
             ],
             principal.session_ttl_ms
           ) do
      send_json(conn, 201, %{
        "participant" => ParticipantSnapshot.to_public(participant),
        "session" => session_public(session)
      })
    else
      {:error, %Error{} = error} -> send_error(conn, status(error), error)
      {:error, :session_start_failed} -> send_session_start_error(conn)
    end
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

  defp send_session_start_error(conn) do
    send_json(conn, 503, %{
      "error" => %{
        "code" => "session_start_failed",
        "message" => "The gateway session could not be started.",
        "retryable" => true,
        "details" => %{}
      }
    })
  end

  defp send_error(conn, status, error) do
    send_json(conn, status, %{"error" => Error.to_public(error)})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end

  defp status(%Error{code: :room_already_exists}), do: 409
  defp status(%Error{code: :participant_already_exists}), do: 409
  defp status(%Error{code: :room_not_found}), do: 404
  defp status(%Error{code: :invalid_command}), do: 400
  defp status(%Error{}), do: 503
end
