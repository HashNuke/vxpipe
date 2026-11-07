defmodule Vxpipe.Console.MCPListedConnectionEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Console.IntegrationsDirectory.{Listing, Request}
  alias Vxpipe.Console.Test.FakeUserIdentity
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.ConnectionStore
  @endpoint Vxpipe.Console.Endpoint
  @example Path.expand(
             "../../../../../docs/development/integrations-directory.example.json",
             __DIR__
           )

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    {:ok, tenant, _} =
      Administration.bootstrap_tenant("Listed MCP", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, other, _} =
      Administration.bootstrap_tenant("Other tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    page =
      @example
      |> File.read!()
      |> JSON.decode!()
      |> Map.put("installation_version", Request.installation_version())
      |> Map.update!("items", fn items ->
        Enum.map(
          items,
          &put_in(&1, ["connection", "authentication"], %{
            "type" => "api_key",
            "header_name" => "X-API-Key"
          })
        )
      end)

    directory = start_supervised!({Agent, fn -> page end})
    supervisor = start_supervised!({Task.Supervisor, []})

    runner =
      start_supervised!(
        {Vxpipe.MCP.PreflightRunner, name: nil, task_supervisor: supervisor, interval: 0}
      )

    parent = self()

    protocol = [
      preflight_runner: runner,
      listing_options: [
        fetcher: fn :integrations, params ->
          send(parent, {:directory_request, params})

          case Agent.get(directory, & &1) do
            :offline -> {:error, :unavailable}
            page -> {:ok, %{body: page}}
          end
        end
      ],
      connection_check: fn scoped_tenant, configuration ->
        assert scoped_tenant == tenant.key
        assert configuration.endpoint == "https://calendar.example.test/mcp"

        assert {:ok, [{"x-api-key", _value}]} =
                 Vxpipe.MCP.Authentication.headers(configuration.authentication)

        send(parent, :mcp_checked)

        {:ok,
         %{
           server_name: "Protocol name",
           catalog: [%{"name" => "events", "inputSchema" => %{"type" => "object"}}]
         }}
      end
    ]

    previous_identity = Application.get_env(:vxpipe_console, :user_identity_backend)
    previous_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.merge(previous_calls,
        credential_repository: {CredentialStore, Repo},
        mcp_connection_repository: {ConnectionStore, context},
        mcp_connection_probe: {Vxpipe.Console.MCPConnectionProbe, protocol}
      )
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_console, :user_identity_backend, previous_identity)
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, previous_calls)
    end)

    session =
      build_conn()
      |> post("https://localhost/auth/api/login", %{
        email: FakeUserIdentity.email(),
        password: FakeUserIdentity.password()
      })
      |> recycle()
      |> get("https://localhost/account")

    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, session.resp_body)
    [entry] = page["items"]

    %{
      tenant: tenant.key,
      other: other.key,
      context: context,
      directory: directory,
      session: session,
      csrf: csrf,
      path: "/api/tenants/#{tenant.key}/mcp-connections",
      reference: Listing.reference(page, entry, %{"category" => "calendar", "limit" => 1})
    }
  end

  test "existing tenant routes preserve listed identity and credentials through a directory outage",
       data do
    input = %{
      "listing" => data.reference,
      "endpoint" => "https://untrusted.example.test/mcp",
      "auth_method" => "none",
      "credentials" => credentials("initial")
    }

    created =
      request(data, :post, data.path, input) |> json_response(201) |> Map.fetch!("connection")

    assert created["server_name"] == "Example Calendar"
    assert created["directory_id"] == "example-directory/example-calendar"
    assert created["auth_method"] == "headers"
    assert created["generation"] == 1
    entry = created["directory_entry"]
    id = created["id"]
    path = data.path <> "/" <> id

    assert_receive {:directory_request,
                    %{"category" => "calendar", "scope" => "tenant", "limit" => 1}}

    assert_receive :mcp_checked
    assert_saved_key(data, id, "initial")
    Agent.update(data.directory, fn _ -> :offline end)

    detail = data.session |> recycle() |> get("https://localhost" <> path) |> json_response(200)
    assert detail["connection"]["directory_entry"] == entry
    refute inspect(detail) =~ "initial"

    updated =
      request(data, :patch, path, %{
        "generation" => 1,
        "endpoint" => "https://untrusted.example.test/mcp",
        "auth_method" => "bearer",
        "credentials" => credentials("replacement")
      })
      |> json_response(200)
      |> Map.fetch!("connection")

    assert updated["directory_entry"] == entry
    assert updated["id"] == id
    assert updated["generation"] == 2
    assert_receive :mcp_checked
    assert_saved_key(data, id, "replacement")

    refreshed =
      request(data, :patch, path, %{"generation" => 2, "refresh_tools" => true})
      |> json_response(200)

    assert refreshed["connection"]["directory_entry"] == entry
    assert refreshed["connection"]["server_name"] == "Example Calendar"
    assert refreshed["connection"]["generation"] == 2
    assert_receive :mcp_checked

    revoked = request(data, :delete, path, %{"generation" => 2}) |> json_response(200)
    assert revoked["connection"]["directory_entry"] == entry
    assert revoked["connection"]["generation"] == 3

    restored =
      request(data, :post, path <> "/reconnect", %{
        "generation" => 3,
        "credentials" => credentials("fresh")
      })
      |> json_response(200)
      |> Map.fetch!("connection")

    assert restored["directory_entry"] == entry
    assert restored["id"] == id
    assert restored["namespace"] == created["namespace"]
    assert restored["generation"] == 4
    assert_receive :mcp_checked
    assert_saved_key(data, id, "fresh")

    stale =
      request(data, :patch, path, %{"generation" => 2, "credentials" => credentials("stale")})

    assert json_response(stale, 409)["error"]["code"] == "stale_mcp_connection"
    other_path = "/api/tenants/#{data.other}/mcp-connections/#{id}"

    assert data.session
           |> recycle()
           |> get("https://localhost" <> other_path)
           |> json_response(404)

    refute_received :mcp_checked
    refute_received {:directory_request, _}
  end

  defp credentials(value), do: %{"headers" => [%{"name" => "Browser-Override", "value" => value}]}

  defp assert_saved_key(data, id, value) do
    assert {:ok, resolved} = ConnectionStore.resolve(data.context, data.tenant, id)
    assert resolved.secrets == %{"headers" => [%{"name" => "X-API-Key", "value" => value}]}
  end

  defp request(data, method, path, body) do
    conn = data.session |> recycle() |> put_req_header("x-csrf-token", data.csrf)
    conn = %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}
    url = "https://localhost" <> path

    case method do
      :post -> post(conn, url, body)
      :patch -> patch(conn, url, body)
      :delete -> delete(conn, url, body)
    end
  end
end
