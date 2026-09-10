defmodule Vxpipe.MCP.TelemetryTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{
    Catalog,
    Connection,
    ConnectionKey,
    Connections,
    Discovery,
    Invocation,
    ReadyClientRuntime,
    ScriptedProtocolClient
  }

  @connection_stop [:vxpipe, :mcp, :connection, :stop]
  @request_stop [:vxpipe, :mcp, :request, :stop]

  test "reports opened, reused, and closed connection states without external identity" do
    attach(@connection_stop)
    key = connection_key()
    on_exit(fn -> Connections.close(key) end)

    assert {:ok, connection} =
             Connections.open(
               key,
               [
                 endpoint: "https://mcp.example.test/rpc",
                 authentication: [type: :bearer, token: "private-secret"]
               ],
               runtime: ReadyClientRuntime
             )

    client = Connection.client(connection)

    assert_receive {@connection_stop, opened_measurements, opened_metadata}
    assert opened_metadata == %{operation: :open, outcome: :opened, client: client}

    assert_counted_duration(opened_measurements)
    assert is_integer(opened_measurements.active_connections)
    assert opened_measurements.active_connections >= 1

    assert {:ok, reused} =
             Connections.open(
               key,
               [endpoint: "https://mcp.example.test/different"],
               runtime: ReadyClientRuntime
             )

    assert Connection.client(reused) == client

    assert_receive {@connection_stop, reused_measurements, reused_metadata}
    assert reused_metadata == %{operation: :open, outcome: :reused, client: client}

    assert_counted_duration(reused_measurements)

    assert :ok = Connections.close(connection)

    assert_receive {@connection_stop, closed_measurements, closed_metadata}
    assert closed_metadata == %{operation: :close, outcome: :closed, client: client}

    assert_counted_duration(closed_measurements)

    refute inspect({opened_measurements, reused_measurements, closed_measurements}) =~
             "private-secret"

    refute inspect({opened_measurements, reused_measurements, closed_measurements}) =~
             "mcp.example"
  end

  test "reports discovery outcomes without catalog contents" do
    attach(@request_stop)
    sentinel = "private-tool-definition"

    client =
      start_client(
        responses: [
          {:ok,
           %{
             "tools" => [
               %{
                 "name" => sentinel,
                 "inputSchema" => %{"type" => "object"}
               }
             ]
           }}
        ]
      )

    assert {:ok, %Catalog{}} =
             Discovery.discover(client,
               protocol: ScriptedProtocolClient,
               max_decoded_bytes: 10_000
             )

    assert_receive {@request_stop, measurements, metadata}
    assert metadata == %{operation: :discovery, outcome: :ok, client: client}

    assert_counted_duration(measurements)

    refute inspect({measurements, metadata}) =~ sentinel
  end

  test "reports rejected and successful invocation outcomes without tool data" do
    attach(@request_stop)
    sentinel = "private-tool-name"
    client = start_client(invocation_responses: [{:ok, %{"content" => []}}])
    catalog = catalog(sentinel)

    assert {:error, :invalid_arguments} =
             Invocation.call(client, catalog, sentinel, %{"value" => 42},
               protocol: ScriptedProtocolClient
             )

    assert_receive {@request_stop, rejected_measurements, rejected_metadata}

    assert rejected_metadata == %{
             operation: :invocation,
             outcome: :rejected,
             client: client
           }

    assert_counted_duration(rejected_measurements)

    assert {:ok, %{"content" => []}} =
             Invocation.call(client, catalog, sentinel, %{"value" => "private-argument"},
               protocol: ScriptedProtocolClient
             )

    assert_receive {@request_stop, succeeded_measurements, succeeded_metadata}
    assert succeeded_metadata == %{operation: :invocation, outcome: :ok, client: client}

    assert_counted_duration(succeeded_measurements)

    observations =
      {rejected_measurements, rejected_metadata, succeeded_measurements, succeeded_metadata}

    refute inspect(observations) =~ sentinel
    refute inspect(observations) =~ "private-argument"
  end

  defp attach(event) do
    handler_id = {__MODULE__, self(), make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_telemetry/4,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  @doc false
  def handle_telemetry(event, measurements, metadata, test_pid) do
    send(test_pid, {event, measurements, metadata})
  end

  defp assert_counted_duration(%{count: 1, duration: duration}) do
    assert is_integer(duration)
    assert duration >= 0
  end

  defp connection_key do
    suffix = System.unique_integer([:positive, :monotonic])

    {:ok, key} =
      ConnectionKey.new(
        scope: :application,
        integration_id: "telemetry-#{suffix}",
        credential_generation: "generation"
      )

    key
  end

  defp start_client(overrides) do
    start_supervised!(
      {Agent,
       fn ->
         overrides
         |> Map.new()
         |> Map.put_new(:calls, [])
         |> Map.put_new(:responses, [])
         |> Map.put_new(:invocations, [])
         |> Map.put_new(:invocation_responses, [])
       end}
    )
  end

  defp catalog(name) do
    tool = %{
      "name" => name,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"value" => %{"type" => "string"}},
        "required" => ["value"]
      }
    }

    {:ok, catalog} = Catalog.new([tool])
    catalog
  end
end
