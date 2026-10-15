defmodule Vxpipe.Gateway.MCP.CallSpecToolsTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    CallSpecSummary,
    InstallationOperator,
    Tenant,
    TestMemoryRepository
  }

  alias Vxpipe.Gateway.MCP.{Admission, Endpoint}

  @version "2025-11-25"
  @spec_tools ~w(list_call_specs get_call_spec create_call_spec update_call_spec publish_call_spec_revision list_providers list_provider_models)

  setup do
    repository = start_supervised!(TestMemoryRepository)

    calls_options = [
      credential_repository: {TestMemoryRepository, repository},
      call_spec_repository: {TestMemoryRepository, repository},
      admin_repository: {__MODULE__, self()},
      provider_credential_repository: {__MODULE__, self()},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("MCP spec", [:admin], calls_options)
    {:ok, actor} = Calls.authenticate_api_key(key.secret, calls_options)
    admission = start_supervised!({Admission, name: nil})

    endpoint = [
      enabled: true,
      allowed_hosts: ["localhost"],
      admission: admission,
      authentication: {__MODULE__, actor},
      call_options: calls_options
    ]

    %{endpoint: endpoint, tenant: tenant, actor: actor, calls_options: calls_options}
  end

  test "only full tenant and Settings platform actors discover and invoke spec tools", ctx do
    for actor <- [
          ctx.actor,
          %InstallationOperator{
            grant: :installation_operator,
            credential_kind: :platform_api_key,
            api_key_id: "fixture"
          }
        ] do
      endpoint = Keyword.put(ctx.endpoint, :authentication, {__MODULE__, actor})
      session = initialize(endpoint)
      catalog = request(endpoint, session, 2, "tools/list", %{})
      names = Enum.map(JSON.decode!(catalog.resp_body)["result"]["tools"], & &1["name"])
      assert Enum.all?(@spec_tools, &(&1 in names))
    end

    for actor <- [%{ctx.actor | scopes: MapSet.new([:calls])}] do
      endpoint = Keyword.put(ctx.endpoint, :authentication, {__MODULE__, actor})
      session = initialize(endpoint)
      catalog = request(endpoint, session, 2, "tools/list", %{})
      names = Enum.map(JSON.decode!(catalog.resp_body)["result"]["tools"], & &1["name"])
      refute Enum.any?(@spec_tools, &(&1 in names))

      assert invoke(endpoint, session, 3, "list_call_specs", %{tenant_key: ctx.tenant.key}).status ==
               403
    end

    legacy =
      Keyword.put(
        ctx.endpoint,
        :authentication,
        {__MODULE__, %InstallationOperator{grant: :installation_operator}}
      )

    assert request(legacy, nil, 1, "initialize", %{protocolVersion: @version}).status == 401

    refute_received {:list_specs, _, _, _}
  end

  test "create, update, historical read and explicit publication use shared immutable revisions",
       ctx do
    session = initialize(ctx.endpoint)

    create =
      invoke(ctx.endpoint, session, 2, "create_call_spec", %{
        tenant_key: ctx.tenant.key,
        call_spec_definition: source()
      })
      |> result()

    assert create["isError"] == false

    assert %{"call_spec_id" => id, "revision" => 1, "validation_errors" => []} =
             create["structuredContent"]

    assert {:ok, %{published_revision: nil}} =
             Calls.fetch_operator_call_spec(ctx.actor, ctx.tenant.key, id, ctx.calls_options)

    updated_source = Map.put(source(), "name", "Updated")

    updated =
      invoke(ctx.endpoint, session, 3, "update_call_spec", %{
        tenant_key: ctx.tenant.key,
        call_spec_id: id,
        call_spec_definition: updated_source
      })
      |> result()

    assert updated["structuredContent"]["revision"] == 2

    read =
      invoke(ctx.endpoint, session, 4, "get_call_spec", %{
        tenant_key: ctx.tenant.key,
        call_spec_id: id,
        revision: 1
      })
      |> result()

    assert read["structuredContent"] == %{
             "call_spec_id" => id,
             "revision" => 1,
             "latest_revision" => 2,
             "published_revision" => nil,
             "call_spec_definition" => source()
           }

    assert [%{"type" => "text", "text" => text}] = read["content"]
    assert JSON.decode!(text) == read["structuredContent"]

    published =
      invoke(ctx.endpoint, session, 5, "publish_call_spec_revision", %{
        tenant_key: ctx.tenant.key,
        call_spec_id: id,
        revision: 1
      })
      |> result()

    assert published["structuredContent"] == %{"call_spec_id" => id, "published_revision" => 1}

    latest =
      invoke(ctx.endpoint, session, 6, "get_call_spec", %{
        tenant_key: ctx.tenant.key,
        call_spec_id: id
      })
      |> result()

    assert latest["structuredContent"]["call_spec_definition"] == updated_source
    assert latest["structuredContent"]["published_revision"] == 1

    missing =
      invoke(ctx.endpoint, session, 7, "update_call_spec", %{
        tenant_key: ctx.tenant.key,
        call_spec_id: "missing",
        call_spec_definition: source()
      })
      |> result()

    assert missing["isError"] == true
    assert missing["structuredContent"]["error"]["code"] == "call_spec_not_found"

    assert {:error, :not_found} =
             Calls.fetch_call_spec(ctx.tenant.key, "missing", 1, ctx.calls_options)
  end

  test "spec and catalog lists paginate without exposing compiled data or credentials", ctx do
    session = initialize(ctx.endpoint)

    listed =
      invoke(ctx.endpoint, session, 2, "list_call_specs", %{
        tenant_key: ctx.tenant.key,
        page: 2,
        page_size: 2
      })
      |> result()

    assert listed["structuredContent"] == %{
             "items" => [
               %{"call_spec_id" => "3", "latest_revision" => 2, "published_revision" => 1}
             ],
             "pagination" => %{"page" => 2, "page_size" => 2, "total" => 3, "total_pages" => 2}
           }

    assert_received {:list_specs, _, 2, 2}

    providers =
      invoke(ctx.endpoint, session, 3, "list_providers", %{
        tenant_key: ctx.tenant.key,
        capability: "text_to_speech",
        page_size: 1
      })
      |> result()

    assert [%{"id" => _}] = providers["structuredContent"]["items"]
    assert providers["structuredContent"]["pagination"]["page_size"] == 1

    models =
      invoke(ctx.endpoint, session, 4, "list_provider_models", %{
        tenant_key: ctx.tenant.key,
        provider: "morse",
        capability: "text_to_speech"
      })
      |> result()

    assert [_ | _] = models["structuredContent"]["items"]
    assert models["isError"] == false

    out_of_range =
      invoke(ctx.endpoint, session, 5, "list_provider_models", %{
        tenant_key: ctx.tenant.key,
        provider: "morse",
        capability: "text_to_speech",
        page: 99
      })
      |> result()

    assert out_of_range["structuredContent"]["error"]["code"] == "page_out_of_range"
  end

  test "typed inputs and foreign tenants fail before side effects", ctx do
    session = initialize(ctx.endpoint)

    for {name, arguments, id} <- [
          {"list_call_specs", %{tenant_key: ctx.tenant.key, page_size: 51}, 2},
          {"get_call_spec", %{tenant_key: ctx.tenant.key, call_spec_id: "1", revision: nil}, 3},
          {"create_call_spec", %{tenant_key: ctx.tenant.key, call_spec_definition: nil}, 4},
          {"create_call_spec",
           %{tenant_key: ctx.tenant.key, call_spec_definition: source(), api_key: "secret"}, 5},
          {"publish_call_spec_revision",
           %{tenant_key: ctx.tenant.key, call_spec_id: "1", revision: "1"}, 6},
          {"list_providers", %{tenant_key: ctx.tenant.key, capability: "unsupported"}, 7}
        ] do
      response = invoke(ctx.endpoint, session, id, name, arguments)
      assert %{"error" => %{"code" => -32602}} = JSON.decode!(response.resp_body)
    end

    foreign =
      invoke(ctx.endpoint, session, 8, "create_call_spec", %{
        tenant_key: "ZZZZZZZZZZZZZZZZ",
        call_spec_definition: source()
      })
      |> result()

    assert foreign["isError"] == true
    assert foreign["structuredContent"]["error"]["code"] == "authoring_forbidden"
    refute_received {:list_specs, _, _, _}
    refute_received {:bindings, _}
  end

  def authenticate(actor, _secret), do: {:ok, actor}

  def list_call_specs(owner, tenant, limit, offset) do
    send(owner, {:list_specs, tenant, limit, offset})

    summary = %CallSpecSummary{
      id: "3",
      name: "not in MCP projection",
      latest_revision: 2,
      published_revision: 1,
      call_count: 99,
      updated_at: ~U[2026-10-15 00:00:00Z]
    }

    {:ok,
     {%Tenant{key: tenant, name: "Fixture", inserted_at: ~U[2026-10-15 00:00:00Z]}, [summary], 3}}
  end

  def list_bindings(owner, tenant) do
    send(owner, {:bindings, tenant})
    {:ok, %{tenant: %{key: tenant, name: "Fixture"}, bindings: []}}
  end

  defp source,
    do: %{
      "schema_version" => "20261004.01",
      "defaults" => %{
        "capabilities" => %{"model_inference" => %{"provider" => "fixture", "model" => "test"}}
      },
      "incoming_call" => %{"caller" => "caller", "handled_by" => "assistant"},
      "participants" => %{
        "caller" => %{
          "type" => "human",
          "connection" => %{"service" => "web", "mode" => "receive", "admission" => "start_call"}
        },
        "assistant" => %{"type" => "agent", "prompt" => "Help."}
      }
    }

  defp result(response), do: JSON.decode!(response.resp_body)["result"]

  defp initialize(endpoint) do
    response =
      request(endpoint, nil, 1, "initialize", %{
        protocolVersion: @version,
        capabilities: %{},
        clientInfo: %{name: "fixture", version: "1"}
      })

    assert response.status == 200
    [session] = get_resp_header(response, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)
    session
  end

  defp invoke(endpoint, session, id, name, arguments),
    do: request(endpoint, session, id, "tools/call", %{name: name, arguments: arguments})

  defp request(endpoint, session, id, method, params) do
    conn =
      conn(
        :post,
        "https://localhost/mcp",
        JSON.encode!(%{jsonrpc: "2.0", id: id, method: method, params: params})
      )
      |> put_req_header("authorization", "Bearer synthetic")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mcp-protocol-version", @version)

    conn = if session, do: put_req_header(conn, "mcp-session-id", session), else: conn
    Endpoint.call(conn, Endpoint.init(endpoint))
  end
end
