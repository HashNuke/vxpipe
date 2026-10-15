defmodule Vxpipe.Gateway.MCP.SensitiveFailuresTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test
  import ExUnit.CaptureLog

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, InstallationOperator, TestMemoryRepository}
  alias Vxpipe.Gateway.MCP.{Admission, Endpoint, Protocol}
  alias Vxpipe.Gateway.Test.AccountStore

  @password "private-mcp-password-sentinel!"
  @token "vxj_private-mcp-issued-token-sentinel"

  setup do
    Process.register(self(), __MODULE__)
    admission = start_supervised!({Admission, name: nil})
    tasks = start_supervised!({Task.Supervisor, name: nil})

    options = [
      enabled: true,
      allowed_hosts: ["localhost"],
      admission: admission,
      authentication: {__MODULE__, :platform},
      handler_call_timeout: 200
    ]

    %{options: options, tasks: tasks}
  end

  test "password-bearing create faults and timeouts keep response and diagnostic logs private",
       c do
    deps = Map.put(AccountStore.dependencies(), :hasher, __MODULE__)
    options = Endpoint.init(Keyword.put(c.options, :call_options, identity_dependencies: deps))
    session = initialize(options)

    for failure <- [:raise, :timeout] do
      log =
        capture_log([level: :debug], fn ->
          task =
            Task.Supervisor.async_nolink(c.tasks, fn ->
              invoke(options, session, "create_user", %{
                email: "local@example.test",
                password: @password,
                password_confirmation: @password,
                role_id: AccountStore.role_id()
              })
            end)

          assert_receive {:hashing, handler, @password}, 1_000
          monitor = Process.monitor(handler)
          if failure == :raise, do: send(handler, :fail_hash)
          response = Task.await(task, 2_000)
          result = JSON.decode!(response.resp_body)

          case failure do
            :raise -> assert result["result"]["isError"]
            :timeout -> assert result["error"]["data"]["type"] == "handler_timeout"
          end

          assert_receive {:DOWN, ^monitor, :process, ^handler, _reason}, 1_000
          refute response.resp_body =~ @password
        end)

      refute log =~ @password
    end
  end

  test "issued join tokens are returned only on success and stay private in issuance faults", c do
    repository = start_supervised!(TestMemoryRepository)

    calls_options = [
      credential_repository: {TestMemoryRepository, repository},
      call_spec_repository: {TestMemoryRepository, repository},
      call_repository: {TestMemoryRepository, repository},
      join_token_generator: fn -> @token end,
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, key} =
      Administration.bootstrap_tenant("Sensitive boundary", [:calls], calls_options)

    {:ok, actor} = Calls.authenticate_api_key(key.secret, calls_options)
    {:ok, revision} = Calls.save_call_spec(tenant.key, source(), calls_options)
    {:ok, _} = Calls.publish_call_spec(tenant.key, revision.call_spec_id, 1, calls_options)

    {:ok, call} =
      Calls.claim_call(actor, tenant.key, revision.call_spec_id, %{}, nil, nil, calls_options)

    args = %{tenant_key: tenant.key, call_id: call.id}
    options = Endpoint.init(Keyword.put(c.options, :call_options, calls_options))
    session = initialize(options)

    log =
      capture_log([level: :debug], fn ->
        response = invoke(options, session, "create_join_token", args)
        assert JSON.decode!(response.resp_body)["result"]["structuredContent"]["token"] == @token
      end)

    refute log =~ @token

    for failure <- [:raise, :exit, :throw] do
      fault_options =
        Keyword.put(calls_options, :call_repository, {__MODULE__, {repository, failure}})

      endpoint = Endpoint.init(Keyword.put(c.options, :call_options, fault_options))

      log =
        capture_log([level: :debug], fn ->
          response = invoke(endpoint, session, "create_join_token", args)
          assert_received {:issuance_fault, ^failure}
          assert JSON.decode!(response.resp_body)["error"]["code"] == -32603
          refute response.resp_body =~ @token
        end)

      refute log =~ @token
    end
  end

  def authenticate(:platform, "synthetic-key"),
    do:
      {:ok,
       %{
         InstallationOperator.authority()
         | credential_kind: :platform_api_key,
           api_key_id: AccountStore.key_id()
       }}

  def hash(password) do
    send(__MODULE__, {:hashing, self(), password})

    receive do
      :fail_hash -> raise password
    after
      5_000 -> {:error, :unavailable}
    end
  end

  def fetch_call({repository, _failure}, tenant, call),
    do: TestMemoryRepository.fetch_call(repository, tenant, call)

  def issue_join_token({_repository, failure}, _tenant, _call, _participant, token) do
    # Prove the domain generated the same secret before injecting a storage fault.
    if token.digest != :crypto.hash(:sha256, @token), do: raise("unexpected test token")
    send(__MODULE__, {:issuance_fault, failure})

    case failure do
      :raise -> raise @token
      :exit -> exit({:storage_fault, @token})
      :throw -> throw({:storage_fault, @token})
    end
  end

  defp initialize(options) do
    response =
      request(options, nil, "initialize", %{
        protocolVersion: Protocol.version(),
        capabilities: %{},
        clientInfo: %{name: "sensitive-boundary", version: "1"}
      })

    assert response.status == 200
    [session] = get_resp_header(response, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)
    session
  end

  defp invoke(options, session, name, args),
    do: request(options, session, "tools/call", %{name: name, arguments: args})

  defp request(options, session, method, params) do
    conn =
      conn(
        :post,
        "https://localhost/mcp",
        JSON.encode!(%{
          jsonrpc: "2.0",
          id: System.unique_integer([:positive]),
          method: method,
          params: params
        })
      )
      |> put_req_header("authorization", "Bearer synthetic-key")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mcp-protocol-version", Protocol.version())

    conn = if session, do: put_req_header(conn, "mcp-session-id", session), else: conn
    Endpoint.call(conn, options)
  end

  defp source do
    %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        caller: %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        assistant: %{type: "agent", prompt: "Local fixture only."}
      }
    }
  end
end
