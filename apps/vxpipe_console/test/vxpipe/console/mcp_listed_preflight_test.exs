defmodule Vxpipe.Console.MCPListedPreflightTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.{IntegrationsDirectory.Listing, MCPPreflight}
  alias Vxpipe.Console.IntegrationsDirectory.{Cache, Request}

  @example Path.expand(
             "../../../../../docs/assets/integrations/integrations-directory.example.json",
             __DIR__
           )

  setup context do
    supervisor = start_supervised!({Task.Supervisor, []})

    runner =
      start_supervised!(
        {Vxpipe.MCP.PreflightRunner,
         name: nil,
         task_supervisor: supervisor,
         interval: 0,
         timeout: Map.get(context, :preflight_deadline, 15_000)}
      )

    owner = self()
    page = @example |> File.read!() |> JSON.decode!()
    page = Map.put(page, "installation_version", Request.installation_version())
    [entry] = page["items"]
    reference = Listing.reference(page, entry, %{"category" => "calendar", "limit" => 1})

    options = [
      preflight_runner: runner,
      listing_options: [
        fetcher: fn :integrations, params ->
          send(owner, {:directory, params})
          {:ok, %{body: page}}
        end
      ],
      dns_resolver: fn host, _ ->
        send(owner, {:dns, host})
        {:ok, [{93, 184, 216, 34}]}
      end,
      http_client: fn _, _, _ -> {:ok, %{status: 404, body: "", headers: []}} end,
      anonymous_check: fn tenant, configuration ->
        send(owner, {:anonymous, tenant, configuration.endpoint})
        {:error, :mcp_authentication_required}
      end
    ]

    %{
      input: %{"listing" => reference, "revision" => "draft-1"},
      options: options,
      page: page,
      supervisor: supervisor
    }
  end

  test "resolves the listing before credentialless discovery without downgrading its recipe",
       data do
    assert {:ok, result} = MCPPreflight.discover(data.options, "tenant", data.input)
    assert result.revision == "draft-1"
    assert result.endpoint == "https://calendar.example.test/mcp"
    assert result.outcome == :unknown
    assert result.suggested_method == nil
    assert result.listing["authentication"] == %{"type" => "oauth2", "registration" => "discover"}
    assert result.listing["name"] == "Example Calendar"
    assert_receive {:directory, %{"category" => "calendar", "limit" => 1, "scope" => "tenant"}}
    assert_receive {:dns, "calendar.example.test"}
    assert_receive {:anonymous, "tenant", "https://calendar.example.test/mcp"}
  end

  test "a failed listing lookup cannot probe a browser-provided endpoint", data do
    options =
      Keyword.put(data.options, :listing_options,
        fetcher: fn _, _ -> {:error, :cursor_expired} end
      )

    assert {:error, :mcp_listing_unavailable} =
             MCPPreflight.discover(options, "tenant", data.input)

    invalid = Map.put(data.input, "endpoint", "https://attacker.example.test/mcp")

    assert {:error, :invalid_mcp_preflight} =
             MCPPreflight.discover(data.options, "tenant", invalid)

    refute_received {:directory, _}
    refute_received {:dns, _}
    refute_received {:anonymous, _, _}
  end

  test "canceling discovery during a shared cache fetch prevents subsequent MCP requests", data do
    {options, cache} = held_lookup(data)
    caller = Task.async(fn -> MCPPreflight.discover(options, "tenant", data.input) end)
    assert_receive {:lookup_owner, worker}
    monitor = Process.monitor(worker)
    assert_receive {:directory_waiting, loader}

    Task.shutdown(caller, :brutal_kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}
    finish_shared_fetch(data, cache, loader)
  end

  @tag preflight_deadline: 50
  test "an expired discovery cannot resume after its shared directory fetch finishes", data do
    {options, cache} = held_lookup(data)
    caller = Task.async(fn -> MCPPreflight.discover(options, "tenant", data.input) end)
    assert_receive {:lookup_owner, worker}
    monitor = Process.monitor(worker)
    assert_receive {:directory_waiting, loader}

    assert {:error, :mcp_connection_timed_out} = Task.await(caller)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}
    finish_shared_fetch(data, cache, loader)
  end

  defp held_lookup(data) do
    owner = self()

    cache =
      start_supervised!(
        {Cache,
         name: nil,
         task_supervisor: data.supervisor,
         loader: fn _, _ ->
           send(owner, {:directory_waiting, self()})

           receive do
             :release_directory -> {:ok, %{body: data.page, etag: nil}}
           end
         end}
      )

    fetcher = fn resource, params ->
      send(owner, {:lookup_owner, self()})
      Cache.fetch(resource, params, cache)
    end

    {Keyword.put(data.options, :listing_options, fetcher: fetcher), cache}
  end

  defp finish_shared_fetch(data, cache, loader) do
    send(loader, :release_directory)
    assert {:ok, %{body: page}} = Cache.fetch(:integrations, data.input["listing"]["page"], cache)
    assert page == data.page
    refute_received {:dns, _}
    refute_received {:anonymous, _, _}
  end
end
