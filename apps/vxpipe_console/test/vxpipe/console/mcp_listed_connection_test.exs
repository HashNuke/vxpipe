defmodule Vxpipe.Console.MCPListedConnectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.{IntegrationsDirectory.Listing, MCPConnectionProbe}
  alias Vxpipe.Console.IntegrationsDirectory.Request

  @example Path.expand(
             "../../../../../docs/development/integrations-directory.example.json",
             __DIR__
           )

  setup do
    supervisor = start_supervised!({Task.Supervisor, []})

    runner =
      start_supervised!(
        {Vxpipe.MCP.PreflightRunner, name: nil, task_supervisor: supervisor, interval: 0}
      )

    %{runner: runner}
  end

  test "listed static connections use the accepted recipe and ignore endpoint/auth overrides",
       data do
    cases = [
      {%{"type" => "none"}, %{}, []},
      {%{"type" => "bearer"}, %{"token" => "synthetic-token"},
       [{"authorization", "Bearer synthetic-token"}]},
      {%{"type" => "basic"}, %{"username" => "operator", "password" => "synthetic-password"},
       [{"authorization", "Basic " <> Base.encode64("operator:synthetic-password")}]},
      {%{"type" => "api_key", "header_name" => "X-API-Key"},
       %{"headers" => [%{"name" => "Attacker-Header", "value" => "synthetic-key"}]},
       [{"x-api-key", "synthetic-key"}]}
    ]

    for {recipe, credentials, expected_headers} <- cases do
      {reference, options} = configuration(data, recipe)
      owner = self()

      options =
        Keyword.put(options, :connection_check, fn tenant, configuration ->
          send(owner, {:checked, tenant, configuration.endpoint})

          assert {:ok, ^expected_headers} =
                   Vxpipe.MCP.Authentication.headers(configuration.authentication)

          {:ok, %{server_name: "Protocol name", catalog: [%{"name" => "events"}]}}
        end)

      input = %{
        "listing" => reference,
        "endpoint" => "https://attacker.example.test/mcp",
        "auth_method" => "own_client",
        "credentials" => credentials
      }

      assert {:ok, result} = MCPConnectionProbe.check(options, "tenant", input)
      assert result.connection.endpoint == "https://calendar.example.test/mcp"
      assert result.connection.endpoint_identity == result.connection.endpoint
      assert result.connection.directory_id == "example-directory/example-calendar"
      assert result.connection.directory_entry["authentication"] == recipe
      assert result.connection.server_name == "Example Calendar"
      assert result.connection.catalog == [%{"name" => "events"}]
      refute inspect(result) =~ "synthetic"
      assert_receive {:checked, "tenant", "https://calendar.example.test/mcp"}
      assert_receive {:directory, %{"category" => "calendar", "scope" => "tenant", "limit" => 1}}

      if recipe["type"] == "api_key" do
        assert result.secrets == %{
                 "headers" => [%{"name" => "X-API-Key", "value" => "synthetic-key"}]
               }
      end
    end
  end

  test "saved listing checks use the accepted snapshot without another directory dependency",
       data do
    {reference, options} = configuration(data, %{"type" => "bearer"})
    assert {:ok, snapshot} = Listing.resolve(reference, options[:listing_options])
    assert_receive {:directory, _}

    options =
      options
      |> Keyword.put(:listing_options,
        fetcher: fn _, _ -> flunk("saved listing must remain local") end
      )
      |> Keyword.put(:connection_check, fn _, configuration ->
        assert configuration.endpoint == snapshot["endpoint"]
        assert configuration.auth_method == "bearer"
        {:ok, %{server_name: "Protocol name", catalog: []}}
      end)

    input = %{
      "credentials" => %{"token" => "replacement-token"},
      "endpoint" => "https://untrusted.example.test/mcp",
      "auth_method" => "none"
    }

    assert {:ok, result} = MCPConnectionProbe.check_saved(options, "tenant", input, snapshot)
    assert result.connection.directory_entry == snapshot
    assert result.connection.server_name == snapshot["name"]
    assert result.secrets == %{"token" => "replacement-token"}
  end

  test "extra credentials and invalid directory proposals fail before MCP authentication", data do
    {reference, options} = configuration(data, %{"type" => "bearer"})

    options =
      Keyword.put(options, :connection_check, fn _, _ -> flunk("unexpected credential use") end)

    assert {:error, :invalid_mcp_configuration} =
             MCPConnectionProbe.check(options, "tenant", %{
               "listing" => reference,
               "credentials" => %{
                 "token" => "synthetic",
                 "headers" => [%{"name" => "X-Extra", "value" => "unused"}]
               }
             })

    assert {:error, :mcp_listing_unavailable} =
             MCPConnectionProbe.check(options, "tenant", %{
               "listing" => Map.put(reference, "entry_revision", 999),
               "credentials" => %{"token" => "synthetic"}
             })

    assert {:error, :invalid_mcp_configuration} =
             MCPConnectionProbe.check(options, "tenant", %{
               "listing" => reference,
               "directory_entry" => %{"endpoint" => "https://untrusted.example.test"},
               "credentials" => %{"token" => "synthetic"}
             })
  end

  defp configuration(data, recipe) do
    page =
      @example
      |> File.read!()
      |> JSON.decode!()
      |> Map.put("installation_version", Request.installation_version())
      |> Map.update!("items", fn items ->
        Enum.map(items, &put_in(&1, ["connection", "authentication"], recipe))
      end)

    [entry] = page["items"]
    reference = Listing.reference(page, entry, %{"category" => "calendar", "limit" => 1})
    owner = self()

    options = [
      preflight_runner: data.runner,
      listing_options: [
        fetcher: fn :integrations, params ->
          send(owner, {:directory, params})
          {:ok, %{body: page}}
        end
      ]
    ]

    {reference, options}
  end
end
