defmodule Vxpipe.MCP.ReferenceClient do
  @moduledoc false

  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, ReferenceProbe}

  @fixture_version "everything-2026.8.31"

  @spec run(String.t()) :: {:ok, %{tool: map(), result: map()}} | {:error, term()}
  def run(server_url) when is_binary(server_url) do
    name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {__MODULE__, make_ref()}}}
    {:ok, host} = DynamicSupervisor.start_link(strategy: :one_for_one, name: name)

    try do
      run_owned(host, server_url)
    after
      Supervisor.stop(host)
    end
  end

  defp run_owned(host, server_url) do
    with {:ok, key} <- connection_key(),
         {:ok, connection} <-
           Connections.open_loopback_test(
             key,
             [
               endpoint: server_url,
               limits: [
                 max_request_bytes: 262_144,
                 max_response_bytes: 262_144,
                 max_stream_buffer_bytes: 262_144
               ]
             ], owner: host) do
      try do
        ReferenceProbe.run(Connection.client(connection))
      after
        Connections.close(connection)
      end
    end
  end

  defp connection_key do
    suffix = System.unique_integer([:positive, :monotonic])

    ConnectionKey.new(
      scope: :application,
      integration_id: "everything-reference-#{suffix}",
      credential_generation: @fixture_version
    )
  end
end
