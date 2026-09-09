defmodule Vxpipe.Gateway.HTTP.StandaloneIntegrationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Gateway.HTTP.Supervisor, as: HTTPSupervisor

  @moduletag :integration
  @origin "https://standalone-client.example.test"

  test "standalone listener preserves CORS and participant-session admission" do
    supervisor =
      start_supervised!(
        {HTTPSupervisor,
         ip: {127, 0, 0, 1},
         port: 0,
         cors: [
           allowed_origins: [@origin],
           allowed_methods: ["POST", "OPTIONS"],
           allowed_headers: ["content-type"],
           allow_credentials: false
         ],
         room_creation: [
           enabled: true,
           principal: [
             tenant_id: "tenant-standalone-test",
             actor_id: "actor-standalone-test",
             scopes: ["rooms:create", "rooms:join"]
           ]
         ]}
      )

    port = listener_port(supervisor)
    room_id = "room-standalone-#{System.unique_integer([:positive, :monotonic])}"

    {204, preflight_headers, ""} =
      request(
        :options,
        port,
        "/api/rooms",
        [
          {"origin", @origin},
          {"access-control-request-method", "POST"},
          {"access-control-request-headers", "content-type"}
        ]
      )

    assert preflight_headers["access-control-allow-origin"] == @origin

    {201, _create_headers, _create_body} =
      request(:post, port, "/api/rooms", [], JSON.encode!(%{"room_id" => room_id}))

    {201, _session_headers, session_body} =
      request(:post, port, "/api/rooms/#{room_id}/sessions")

    assert %{
             "participant" => %{"room_id" => ^room_id, "state" => "joined"},
             "session" => %{
               "session_id" => session_id,
               "transport" => %{"request_data" => %{"session_id" => session_id}}
             }
           } = JSON.decode!(session_body)
  end

  defp listener_port(supervisor) do
    [{_id, bandit, :supervisor, _modules}] = Supervisor.which_children(supervisor)
    {:ok, {_address, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  defp request(method, port, path, headers \\ [], body \\ "") do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: :raw], 2_000)

    request_headers =
      [{"host", "127.0.0.1:#{port}"}, {"connection", "close"} | headers]
      |> add_body_headers(body)
      |> Enum.map(fn {name, value} -> [name, ": ", value, "\r\n"] end)

    request = [
      method |> Atom.to_string() |> String.upcase(),
      " ",
      path,
      " HTTP/1.1\r\n",
      request_headers,
      "\r\n",
      body
    ]

    :ok = :gen_tcp.send(socket, request)

    response = receive_response(socket, [])
    :ok = :gen_tcp.close(socket)

    [head, response_body] = :binary.split(response, "\r\n\r\n")
    [status_line | response_header_lines] = String.split(head, "\r\n")
    ["HTTP/1.1", status_text, _reason] = String.split(status_line, " ", parts: 3)
    {status, ""} = Integer.parse(status_text)

    response_headers = Map.new(response_header_lines, &parse_header/1)

    {status, response_headers, response_body}
  end

  defp add_body_headers(headers, ""), do: headers

  defp add_body_headers(headers, body) do
    [
      {"content-type", "application/json"},
      {"content-length", byte_size(body) |> Integer.to_string()} | headers
    ]
  end

  defp receive_response(socket, chunks) do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, chunk} -> receive_response(socket, [chunk | chunks])
      {:error, :closed} -> chunks |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end

  defp parse_header(line) do
    [name, value] = String.split(line, ":", parts: 2)
    {String.downcase(name), String.trim(value)}
  end
end
