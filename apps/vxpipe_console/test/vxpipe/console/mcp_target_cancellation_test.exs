defmodule Vxpipe.Console.MCPTargetCancellationTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{MCPConnections, MCPOAuthAttempts}
  alias Vxpipe.Console.IntegrationsDirectory.{Cache, Listing, Request}
  alias Vxpipe.Console.Test.MCPStaticManagementFixture
  alias Vxpipe.Identity.Principal
  @tenant "AAAAAAAAAAAAAAAA"
  @example Path.expand(
             "../../../../../docs/development/integrations-directory.example.json",
             __DIR__
           )

  for flow <- [:static, :oauth] do
    test "cancelled #{flow} target lookup permits a shared directory fetch but never continues the connection" do
      parent = self()

      page =
        @example
        |> File.read!()
        |> JSON.decode!()
        |> Map.put("installation_version", Request.installation_version())

      [entry] = page["items"]
      reference = Listing.reference(page, entry, %{"category" => "calendar", "limit" => 1})
      tasks = start_supervised!({Task.Supervisor, []})

      cache =
        start_supervised!(
          {Cache,
           name: nil,
           task_supervisor: tasks,
           loader: fn _, _ ->
             send(parent, {:directory_loading, self()})

             receive do
               :release -> {:ok, %{body: page, etag: "accepted-page"}}
             end
           end}
        )

      principal = %Principal{
        user_public_id: "user",
        session_public_id: "session",
        account_kind: :member,
        grants: MapSet.new(~w(tenant_services.read tenant_services.write)),
        assigned_tenants: %{@tenant => :read_write}
      }

      protocol = [
        listing_options: [
          fetcher: fn resource, params -> Cache.fetch(resource, params, cache) end
        ],
        connection_check: fn _, _ ->
          send(parent, :unexpected_protocol)
          {:error, :unavailable}
        end,
        http_client: fn _, _, _ ->
          send(parent, :unexpected_protocol)
          {:error, :unavailable}
        end
      ]

      options = [
        credential_repository: {MCPStaticManagementFixture, parent},
        mcp_connection_repository: {MCPStaticManagementFixture, parent},
        mcp_connection_probe: {Vxpipe.Console.MCPConnectionProbe, protocol},
        mcp_oauth_preparation: {Vxpipe.Console.MCPOAuthPreparation, protocol},
        installation_identity: fn -> {:ok, %{origin: "https://console.test", revision: 1}} end,
        refresh_authority: fn -> {:ok, principal} end
      ]

      caller =
        start_supervised!(
          {Task,
           fn ->
             result = run(unquote(flow), principal, reference, options)
             send(parent, {:connection_result, result})
           end}
        )

      caller_monitor = Process.monitor(caller)
      assert_receive {:directory_loading, worker}, 1000
      worker_monitor = Process.monitor(worker)
      stop_supervised!(Task)
      assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :shutdown}, 1000

      :erlang.trace(cache, true, [:receive])

      shared =
        Task.Supervisor.async_nolink(tasks, fn ->
          Cache.fetch(:integrations, reference["page"], cache)
        end)

      shared_pid = shared.pid
      assert_receive {:trace, ^cache, :receive, {:"$gen_call", {^shared_pid, _}, _}}, 1000
      :erlang.trace(cache, false, [:receive])
      _ = :sys.get_state(cache)
      send(worker, :release)
      assert {:ok, %{body: ^page}} = Task.await(shared)
      assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :normal}, 1000
      _ = :sys.get_state(cache)
      refute_received {:directory_loading, _}
      refute_received {:mcp_identity_lookup, _, _}
      refute_received :unexpected_protocol
      refute_received {:connection_result, _}
    end
  end

  defp run(:static, principal, reference, options),
    do:
      MCPConnections.connect(
        principal,
        @tenant,
        %{"listing" => reference, "credentials" => %{}},
        options
      )

  defp run(:oauth, principal, reference, options),
    do:
      MCPOAuthAttempts.start(
        principal,
        @tenant,
        %{"listing" => reference, "revision" => "draft"},
        options
      )
end
