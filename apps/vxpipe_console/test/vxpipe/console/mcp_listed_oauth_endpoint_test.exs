defmodule Vxpipe.Console.MCPListedOAuthEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Console.IntegrationsDirectory.{Listing, Request}
  alias Vxpipe.Console.Test.FakeUserIdentity
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.{ConnectionStore, OAuthAttemptStore}
  @endpoint Vxpipe.Console.Endpoint
  @resource "https://calendar.example.test/mcp"
  @issuer "https://auth.example.test"
  @example Path.expand(
             "../../../../../docs/assets/integrations/integrations-directory.example.json",
             __DIR__
           )

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    {:ok, tenant, _} =
      Administration.bootstrap_tenant("Listed OAuth", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, other, _} =
      Administration.bootstrap_tenant("Other", [:admin],
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
            "type" => "oauth2",
            "registration" => "dcr"
          })
        )
      end)

    directory = start_supervised!({Agent, fn -> page end})

    metadata_state =
      start_supervised!(Supervisor.child_spec({Agent, fn -> metadata() end}, id: :metadata))

    tasks = start_supervised!({Task.Supervisor, []})

    runner =
      start_supervised!(
        {Vxpipe.MCP.PreflightRunner, name: nil, task_supervisor: tasks, interval: 0}
      )

    parent = self()

    protocol = [
      preflight_runner: runner,
      completion_runner: runner,
      listing_options: [
        fetcher: fn :integrations, _ ->
          send(parent, :directory_request)

          case Agent.get(directory, & &1) do
            :offline -> {:error, :unavailable}
            page -> {:ok, %{body: page}}
          end
        end
      ],
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn uri, _, _ ->
        {status, body} =
          case {uri.host, uri.path} do
            {"calendar.example.test", "/mcp"} ->
              {401, %{}}

            {"calendar.example.test", _} ->
              {200,
               %{
                 "resource" => @resource,
                 "authorization_servers" => [@issuer],
                 "scopes_supported" => ["tools.read"]
               }}

            {"auth.example.test", _} ->
              {200, Agent.get(metadata_state, & &1)}
          end

        {:ok, %{status: status, headers: [], body: JSON.encode!(body)}}
      end,
      request_fun: fn :post, {uri, _, _, _}, _, _ ->
        case URI.parse(to_string(uri)).path do
          "/register" ->
            send(parent, :registered)

            protocol_response(201, %{
              "client_id" => "registered",
              "token_endpoint_auth_method" => "none",
              "redirect_uris" => ["https://console.example.test/oauth/mcp/callback"]
            })

          "/token" ->
            send(parent, :exchanged)

            protocol_response(200, %{
              "access_token" => "synthetic-access",
              "refresh_token" => "synthetic-refresh",
              "token_type" => "Bearer",
              "expires_in" => 300
            })
        end
      end,
      connection_check: fn scoped, configuration ->
        assert scoped == tenant.key
        assert configuration.endpoint == @resource
        assert configuration.secrets["token"] == "synthetic-access"
        send(parent, :mcp_checked)
        {:ok, %{server_name: "Remote protocol name", catalog: []}}
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
        mcp_oauth_attempt_repository: {OAuthAttemptStore, context},
        mcp_connection_probe: {Vxpipe.Console.MCPConnectionProbe, protocol},
        mcp_preflight: {Vxpipe.Console.MCPPreflight, protocol},
        mcp_oauth_preparation: {Vxpipe.Console.MCPOAuthPreparation, protocol},
        mcp_oauth_completion: {Vxpipe.Console.MCPOAuthCompletion, protocol}
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
      metadata_state: metadata_state,
      session: session,
      csrf: csrf,
      path: "/api/tenants/#{tenant.key}",
      reference: Listing.reference(page, entry, %{"category" => "calendar", "limit" => 1})
    }
  end

  test "listed OAuth keeps accepted configuration through callback, replacement and reconnect during outage",
       data do
    handoff =
      request(data, :post, "/mcp-oauth", %{
        "listing" => data.reference,
        "revision" => "draft",
        "credentials" => %{}
      })
      |> json_response(201)

    id = handoff["connection_id"]
    assert_receive :directory_request
    assert_receive :registered
    Agent.update(data.directory, fn _ -> :offline end)
    complete(data, handoff)
    assert_receive :exchanged
    assert_receive :mcp_checked
    assert {:ok, initial} = ConnectionStore.resolve(data.context, data.tenant, id)
    entry = initial.connection.directory_entry
    assert initial.connection.server_name == "Example Calendar"
    assert initial.connection.directory_id == "example-directory/example-calendar"
    refute Map.has_key?(initial.secrets, "directory_entry")
    path = "/mcp-connections/" <> id
    detail = request(data, :get, path, %{}) |> json_response(200)
    assert detail["connection"]["directory_entry"] == entry
    refute inspect(detail) =~ "synthetic-access"

    replacing =
      request(data, :post, path <> "/oauth", %{
        "generation" => 1,
        "revision" => "replace",
        "credentials" => %{}
      })
      |> json_response(201)

    complete(data, replacing)
    assert_receive :exchanged
    assert_receive :mcp_checked
    refute_received :registered
    assert {:ok, replaced} = ConnectionStore.resolve(data.context, data.tenant, id)
    assert replaced.connection.generation == 2
    assert replaced.connection.directory_entry == entry
    assert replaced.connection.namespace == initial.connection.namespace

    refreshed =
      request(data, :patch, path, %{"generation" => 2, "refresh_tools" => true})
      |> json_response(200)

    assert refreshed["connection"]["directory_entry"] == entry
    assert_receive :mcp_checked
    assert request(data, :delete, path, %{"generation" => 2}) |> json_response(200)

    reconnecting =
      request(data, :post, path <> "/oauth", %{
        "generation" => 3,
        "revision" => "reconnect",
        "credentials" => %{}
      })
      |> json_response(201)

    assert_receive :registered
    complete(data, reconnecting)
    assert {:ok, restored} = ConnectionStore.resolve(data.context, data.tenant, id)
    assert restored.connection.generation == 4
    assert restored.connection.directory_entry == entry
    assert restored.connection.namespace == initial.connection.namespace
    assert_receive :exchanged
    assert_receive :mcp_checked

    assert request(data, :post, path <> "/oauth", %{"generation" => 2, "revision" => "stale"})
           |> json_response(409)

    assert request(%{data | path: "/api/tenants/#{data.other}"}, :post, path <> "/oauth", %{
             "generation" => 4,
             "revision" => "other"
           })
           |> json_response(404)

    refute_received :directory_request
    refute_received :registered
    refute_received :exchanged
  end

  test "OAuth duplicate proposals precede changed recipe preparation and need no decryption key",
       data do
    handoff =
      request(data, :post, "/mcp-oauth", %{"listing" => data.reference, "revision" => "draft"})
      |> json_response(201)

    id = handoff["connection_id"]
    complete(data, handoff)
    assert_receive :directory_request
    assert_receive :registered
    assert_receive :exchanged
    assert_receive :mcp_checked

    Agent.update(data.directory, fn page ->
      Map.update!(page, "items", fn [item] ->
        [
          item
          |> Map.put("revision", 2)
          |> put_in(["connection", "endpoint"], "https://changed.example.test/mcp")
          |> put_in(["connection", "authentication"], %{
            "type" => "oauth2",
            "registration" => "preregistered"
          })
        ]
      end)
    end)

    calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    {module, protocol} = Keyword.fetch!(calls, :mcp_oauth_preparation)
    parent = self()

    protocol =
      Keyword.put(protocol, :http_client, fn _, _, _ ->
        send(parent, :unexpected_oauth_read)
        {:error, :unavailable}
      end)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      calls
      |> Keyword.put(:mcp_connection_repository, {ConnectionStore, [repo: Repo]})
      |> Keyword.put(:mcp_oauth_preparation, {module, protocol})
    )

    input = %{"listing" => Map.put(data.reference, "entry_revision", 2), "revision" => "changed"}

    assert request(data, :post, "/mcp-oauth", input) |> json_response(409) ==
             %{"error" => %{"code" => "mcp_connection_exists", "connection_id" => id}}

    assert_receive :directory_request

    assert request(data, :delete, "/mcp-connections/" <> id, %{"generation" => 1})
           |> json_response(200)

    assert request(data, :post, "/mcp-oauth", input) |> json_response(409) ==
             %{
               "error" => %{
                 "code" => "mcp_reconnect_required",
                 "connection_id" => id,
                 "generation" => 2
               }
             }

    assert_receive :directory_request
    refute_received :unexpected_oauth_read
    refute_received :registered
    refute_received :exchanged
    refute_received :mcp_checked
  end

  test "atomic create rejects an OAuth duplicate that appears after both early lookups", data do
    input = %{"listing" => data.reference, "revision" => "draft"}
    first = request(data, :post, "/mcp-oauth", input) |> json_response(201)
    second = request(data, :post, "/mcp-oauth", input) |> json_response(201)
    refute first["connection_id"] == second["connection_id"]
    complete(data, first)

    assert {:ok, original} =
             ConnectionStore.resolve(data.context, data.tenant, first["connection_id"])

    state =
      second["authorization_url"]
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("state")

    query = URI.encode_query(%{"state" => state, "code" => "second-code", "iss" => @issuer})
    callback = data.session |> recycle() |> get("https://localhost/oauth/mcp/callback?" <> query)
    assert redirected_to(callback, 303) =~ "mcp=failed"
    assert {:ok, [record]} = ConnectionStore.list(data.context, data.tenant)
    assert record.id == first["connection_id"]
    assert record.generation == 1
    assert {:ok, after_race} = ConnectionStore.resolve(data.context, data.tenant, record.id)
    assert after_race == original

    assert data.session
           |> recycle()
           |> get("https://localhost/oauth/mcp/callback?" <> query)
           |> json_response(400)
  end

  test "changed or malformed listing produces a bounded recoverable route error before registration",
       data do
    assert request(data, :post, "/mcp-oauth", %{"listing" => %{}, "revision" => "draft"})
           |> json_response(422) == %{"error" => %{"code" => "invalid_mcp_listing"}}

    changed = Map.put(data.reference, "entry_revision", 999)

    assert request(data, :post, "/mcp-oauth", %{"listing" => changed, "revision" => "draft"})
           |> json_response(503) == %{"error" => %{"code" => "mcp_listing_unavailable"}}

    refute_received :registered
    refute_received :exchanged
  end

  test "saved discovery returns bound reusable advice during directory outage without mutating OAuth",
       data do
    handoff =
      request(data, :post, "/mcp-oauth", %{"listing" => data.reference, "revision" => "draft"})
      |> json_response(201)

    id = handoff["connection_id"]
    complete(data, handoff)
    assert_receive :directory_request
    assert_receive :registered
    assert_receive :exchanged
    assert_receive :mcp_checked
    Agent.update(data.directory, fn _ -> :offline end)

    Agent.update(
      data.metadata_state,
      &Map.drop(&1, ~w(registration_endpoint client_id_metadata_document_supported))
    )

    input = %{"connection_id" => id, "generation" => 1, "revision" => "advice"}

    discovery =
      request(data, :post, "/mcp-discovery", input)
      |> json_response(200)
      |> Map.fetch!("discovery")

    assert discovery["connection_id"] == id
    assert discovery["generation"] == 1
    assert discovery["revision"] == "advice"
    assert discovery["oauth_registration"] == %{"method" => "dcr", "reusable" => true}

    assert discovery["oauth_client"]["callback_url"] ==
             "https://console.example.test/oauth/mcp/callback"

    refute inspect(discovery) =~ "synthetic-access"

    assert request(data, :post, "/mcp-discovery", %{input | "generation" => 2})
           |> json_response(409)

    assert request(%{data | path: "/api/tenants/#{data.other}"}, :post, "/mcp-discovery", input)
           |> json_response(404)

    assert request(data, :post, "/mcp-discovery", Map.put(input, "credentials", %{}))
           |> json_response(422)

    assert {:ok, saved} = ConnectionStore.resolve(data.context, data.tenant, id)
    assert saved.connection.generation == 1

    assert request(data, :delete, "/mcp-connections/" <> id, %{"generation" => 1})
           |> json_response(200)

    revoked =
      request(data, :post, "/mcp-discovery", %{input | "generation" => 2}) |> json_response(200)

    assert revoked["discovery"]["oauth_registration"] == %{
             "method" => "own_client",
             "reusable" => false
           }

    refute_received :directory_request
    refute_received :registered
    refute_received :exchanged
    refute_received :mcp_checked
  end

  test "malformed listed issuer is a validation error before directory or protocol work", data do
    for issuer <- [123, "https://user@auth.example.test", "https://auth.example.test?scope=other"] do
      result =
        request(data, :post, "/mcp-oauth", %{
          "listing" => data.reference,
          "revision" => "draft",
          "issuer" => issuer
        })

      assert json_response(result, 422)["error"]["code"] == "invalid_oauth_issuer"
    end

    refute_received :directory_request
    refute_received :registered
    refute_received :exchanged
  end

  defp metadata do
    %{
      "issuer" => @issuer,
      "authorization_endpoint" => @issuer <> "/authorize",
      "token_endpoint" => @issuer <> "/token",
      "registration_endpoint" => @issuer <> "/register",
      "client_id_metadata_document_supported" => true,
      "token_endpoint_auth_methods_supported" => ["none"],
      "response_types_supported" => ["code"],
      "code_challenge_methods_supported" => ["S256"],
      "authorization_response_iss_parameter_supported" => true
    }
  end

  defp protocol_response(status, body),
    do: {:ok, {{~c"HTTP/1.1", status, ~c"OK"}, [], JSON.encode!(body)}}

  defp complete(data, handoff) do
    state =
      handoff["authorization_url"]
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("state")

    query = URI.encode_query(%{"state" => state, "code" => "synthetic-code", "iss" => @issuer})
    response = data.session |> recycle() |> get("https://localhost/oauth/mcp/callback?" <> query)
    assert redirected_to(response, 303) =~ "mcp=connected"

    assert data.session
           |> recycle()
           |> get("https://localhost/oauth/mcp/callback?" <> query)
           |> json_response(400)
  end

  defp request(data, method, suffix, body) do
    conn = data.session |> recycle() |> put_req_header("x-csrf-token", data.csrf)
    conn = %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}
    dispatch(conn, @endpoint, method, "https://localhost" <> data.path <> suffix, body)
  end
end
