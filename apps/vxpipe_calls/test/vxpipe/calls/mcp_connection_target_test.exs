defmodule Vxpipe.Calls.MCPConnectionTargetTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{MCPConnections, MCPOAuthAttempts}
  alias Vxpipe.Calls.Test.MCPConnectionTargetFixture
  alias Vxpipe.Identity.Principal

  @tenant "AAAAAAAAAAAAAAAA"
  @endpoint "https://mcp.example.test/mcp"

  setup do
    principal = %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(~w(tenant_services.read tenant_services.write)),
      assigned_tenants: %{@tenant => :read_write}
    }

    %{principal: principal}
  end

  for flow <- [:static, :oauth], status <- ["connected", "revoked"] do
    test "#{flow} finds #{status} duplicates before authentication and exposes no credentials",
         data do
      flow = unquote(flow)
      status = unquote(status)
      input = input(flow)
      target = target(flow)
      existing = existing(status)
      options = options(data.principal, target, existing)

      assert run(flow, data.principal, input, options) == conflict(existing)
      assert_receive {:target_resolved, @tenant, public_input}
      assert public_input == Map.take(input, ~w(endpoint revision))
      assert_receive {:identity_checked, @tenant, identity}
      assert identity == %{endpoint_identity: @endpoint, directory_id: nil}
      refute_received {:credentials_checked, _, _}
      refute_received {:oauth_prepared, _, _}
    end
  end

  for flow <- [:static, :oauth] do
    test "#{flow} rejects missing port capabilities before resolving a target", data do
      flow = unquote(flow)
      port_key = port_key(flow)
      legacy = {Vxpipe.Calls.Test.MCPLegacyTargetFixture, self()}

      for key <- [port_key, :mcp_connection_repository] do
        options =
          options(data.principal, target(flow), nil)
          |> Keyword.put(key, legacy)

        assert {:error, :mcp_connections_unavailable} =
                 run(flow, data.principal, input(flow), options)

        refute_received {:target_resolved, _, _}
        refute_received {:identity_checked, _, _}
        refute_received {:credentials_checked, _, _}
        refute_received {:oauth_prepared, _, _}
        refute_received :legacy_protocol_called
      end
    end

    test "#{flow} rejects a resolved target for another endpoint before lookup", data do
      flow = unquote(flow)

      for changed <- [
            %{target(flow) | endpoint: "https://other.example.test/mcp"},
            %{target(flow) | endpoint_identity: "https://other.example.test/mcp"},
            %{target(flow) | directory_id: "foreign/listing"},
            %{target(flow) | directory_entry: %{"endpoint" => @endpoint}},
            %{target(flow) | revision: "other-draft"}
          ] do
        options = options(data.principal, changed, nil)

        assert {:error, :mcp_connections_unavailable} =
                 run(flow, data.principal, input(flow), options)

        refute_received {:identity_checked, _, _}
        refute_received {:credentials_checked, _, _}
        refute_received {:oauth_prepared, _, _}
      end
    end

    test "#{flow} rechecks authority after target resolution before lookup", data do
      flow = unquote(flow)
      authority = start_supervised!({Agent, fn -> data.principal end})
      revoked = %{data.principal | grants: MapSet.new()}
      action = fn -> Agent.update(authority, fn _ -> revoked end) end
      port_key = port_key(flow)

      options =
        options(data.principal, target(flow), existing("revoked"))
        |> Keyword.update!(port_key, fn {module, context} ->
          {module, Map.put(context, :resolve_action, action)}
        end)
        |> Keyword.put(:refresh_authority, fn -> {:ok, Agent.get(authority, & &1)} end)

      assert {:error, :forbidden} = run(flow, data.principal, input(flow), options)
      assert_receive {:target_resolved, @tenant, _}
      refute_received {:identity_checked, _, _}
      refute_received {:credentials_checked, _, _}
      refute_received {:oauth_prepared, _, _}
    end

    test "#{flow} rechecks authority after an existing-identity lookup", data do
      flow = unquote(flow)
      authority = start_supervised!({Agent, fn -> data.principal end})
      revoked = %{data.principal | grants: MapSet.new()}
      action = fn -> Agent.update(authority, fn _ -> revoked end) end

      options =
        options(data.principal, target(flow), existing("revoked"), action)
        |> Keyword.put(:refresh_authority, fn -> {:ok, Agent.get(authority, & &1)} end)

      assert {:error, :forbidden} = run(flow, data.principal, input(flow), options)
      assert_receive {:identity_checked, @tenant, _}
      refute_received {:credentials_checked, _, _}
      refute_received {:oauth_prepared, _, _}
    end

    test "#{flow} rejects foreign metadata before exposing a duplicate", data do
      flow = unquote(flow)
      foreign = %{existing("revoked") | tenant_key: "BBBBBBBBBBBBBBBB"}
      options = options(data.principal, target(flow), foreign)

      assert {:error, :mcp_connections_unavailable} =
               run(flow, data.principal, input(flow), options)

      refute_received {:credentials_checked, _, _}
      refute_received {:oauth_prepared, _, _}
    end

    test "#{flow} continues protocol work for an absent identity", data do
      flow = unquote(flow)
      options = options(data.principal, target(flow), nil)

      assert run(flow, data.principal, input(flow), options) == protocol_error(flow)
      assert_receive {:target_resolved, @tenant, _}
      assert_receive {:identity_checked, @tenant, _}

      assert_protocol(flow)
    end
  end

  defp port_key(:static), do: :mcp_connection_probe
  defp port_key(:oauth), do: :mcp_oauth_preparation
  defp protocol_error(:static), do: {:error, :mcp_authentication_required}
  defp protocol_error(:oauth), do: {:error, :oauth_registration_unavailable}

  defp assert_protocol(:static) do
    assert_receive {:target_checked, _}
    assert_receive {:credentials_checked, @tenant, _}
  end

  defp assert_protocol(:oauth) do
    assert_receive {:target_prepared, _}
    assert_receive {:oauth_prepared, @tenant, _}
  end

  defp input(:static),
    do: %{
      "endpoint" => @endpoint,
      "auth_method" => "bearer",
      "credentials" => %{"token" => "private-static"}
    }

  defp input(:oauth),
    do: %{
      "endpoint" => @endpoint,
      "auth_method" => "dcr",
      "revision" => "draft",
      "initial_access_token" => "private-registration"
    }

  defp target(flow),
    do: %{
      endpoint: @endpoint,
      endpoint_identity: @endpoint,
      directory_id: nil,
      directory_entry: nil,
      revision: if(flow == :oauth, do: "draft", else: nil)
    }

  defp existing(status),
    do: %{
      id: "saved-connection",
      tenant_key: @tenant,
      endpoint: @endpoint,
      endpoint_identity: @endpoint,
      directory_id: nil,
      generation: 4,
      status: status
    }

  defp conflict(%{status: "revoked", id: id, generation: generation}),
    do: {:error, {:mcp_reconnect_required, %{id: id, generation: generation}}}

  defp conflict(%{id: id}), do: {:error, {:mcp_connection_exists, id}}

  defp options(principal, target, existing, action \\ nil) do
    context = %{owner: self(), target: target, existing: existing, lookup_action: action}
    port = {MCPConnectionTargetFixture, context}

    [
      credential_repository: port,
      mcp_connection_repository: port,
      mcp_connection_probe: port,
      mcp_oauth_preparation: port,
      refresh_authority: fn -> {:ok, principal} end,
      installation_identity: fn -> {:ok, %{origin: "https://console.test", revision: 1}} end
    ]
  end

  defp run(:static, principal, input, options),
    do: MCPConnections.connect(principal, @tenant, input, options)

  defp run(:oauth, principal, input, options),
    do: MCPOAuthAttempts.start(principal, @tenant, input, options)
end
