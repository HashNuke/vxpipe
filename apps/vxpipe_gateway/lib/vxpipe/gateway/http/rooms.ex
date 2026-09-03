defmodule Vxpipe.Gateway.HTTP.Rooms do
  @moduledoc false

  import Plug.Conn

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Room.Snapshot

  @create_scope "rooms:create"
  @command_timeout_seconds 5

  def init(options) do
    if Keyword.get(options, :enabled, false) do
      principal = Keyword.fetch!(options, :principal)

      %{
        enabled: true,
        tenant_id: Keyword.fetch!(principal, :tenant_id),
        actor_id: Keyword.fetch!(principal, :actor_id),
        scopes: Keyword.get(principal, :scopes, [])
      }
    else
      %{enabled: false}
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
             deadline: deadline
           ),
         {:ok, snapshot} <- CallEngine.create_room(command) do
      send_json(conn, 201, %{"room" => Snapshot.to_public(snapshot)})
    else
      {:error, %Error{} = error} -> send_error(conn, status(error), error)
    end
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
  defp status(%Error{code: :invalid_command}), do: 400
  defp status(%Error{}), do: 503
end
