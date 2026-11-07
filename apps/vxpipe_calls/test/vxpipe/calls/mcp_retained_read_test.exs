defmodule Vxpipe.Calls.MCPRetainedReadTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{MCPConnections, Test.MCPRetainedReadFixture}
  alias Vxpipe.Identity.Principal
  @tenant "AAAAAAAAAAAAAAAA"
  @id "retained-connection"

  setup do
    principal = %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(~w(tenant_services.read tenant_services.write)),
      assigned_tenants: %{@tenant => :read_write}
    }

    record = %{
      id: @id,
      tenant_key: @tenant,
      generation: 4,
      status: "revoked",
      endpoint: "https://mcp.example.test/mcp",
      directory_id: nil,
      server_name: "Calendar",
      auth_method: "bearer",
      namespace: "stable",
      catalog: [],
      secrets: %{"token" => "must-not-appear"}
    }

    context = %{owner: self(), result: {:ok, record}}

    options = [
      credential_repository: {MCPRetainedReadFixture, context},
      mcp_connection_repository: {MCPRetainedReadFixture, context},
      refresh_authority: fn -> {:ok, principal} end
    ]

    %{principal: principal, record: record, context: context, options: options}
  end

  test "an explicit retained read returns only exact public configuration with write authority",
       data do
    assert {:ok, record} = read(data)
    assert record.id == @id
    assert record.generation == 4
    assert record.status == "revoked"
    assert record.namespace == "stable"
    assert record.can_edit
    refute inspect(record) =~ "must-not-appear"
    refute Map.has_key?(record, :tools)
    assert_received {:metadata_read, @tenant, @id}
  end

  test "read-only, foreign tenant and stale session authority cannot inspect retained metadata",
       data do
    reader = %{data.principal | assigned_tenants: %{@tenant => :read}}
    assert {:error, :forbidden} = read(%{data | principal: reader})

    assert {:error, :forbidden} =
             MCPConnections.get_retained(data.principal, "BBBBBBBBBBBBBBBB", @id, 4, data.options)

    for current <- [reader, %{data.principal | session_public_id: "different"}] do
      options = Keyword.put(data.options, :refresh_authority, fn -> {:ok, current} end)
      assert {:error, :forbidden} = read(%{data | options: options})
    end

    refute_received {:metadata_read, _, _}
  end

  test "a retained read rejects stale generation, connected records and repository identity mismatch",
       data do
    for {changes, reason} <- [
          {%{generation: 5}, :stale_mcp_connection},
          {%{status: "connected"}, :mcp_reconnect_not_required},
          {%{tenant_key: "BBBBBBBBBBBBBBBB"}, :not_found},
          {%{id: "another-id"}, :not_found}
        ] do
      context = %{data.context | result: {:ok, Map.merge(data.record, changes)}}

      options =
        Keyword.put(data.options, :mcp_connection_repository, {MCPRetainedReadFixture, context})

      assert {:error, ^reason} = read(%{data | options: options})
    end
  end

  test "authority is checked again after metadata loading and storage failures stay failures",
       data do
    authority = start_supervised!({Agent, fn -> data.principal end})

    context =
      Map.put(data.context, :before_return, fn ->
        Agent.update(authority, &%{&1 | grants: MapSet.new()})
      end)

    options =
      data.options
      |> Keyword.put(:refresh_authority, fn -> {:ok, Agent.get(authority, & &1)} end)
      |> Keyword.put(:mcp_connection_repository, {MCPRetainedReadFixture, context})

    assert {:error, :forbidden} = read(%{data | options: options})
    context = %{data.context | result: {:error, :mcp_connections_unavailable}}

    options =
      Keyword.put(data.options, :mcp_connection_repository, {MCPRetainedReadFixture, context})

    assert {:error, :mcp_connections_unavailable} = read(%{data | options: options})
  end

  defp read(data), do: MCPConnections.get_retained(data.principal, @tenant, @id, 4, data.options)
end
