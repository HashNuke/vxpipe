defmodule Vxpipe.Console.Test.MCPCallbackNodeCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Vxpipe.Console.Test.{MCPCallbackNode, OutboundMCPOAuthServer}
  alias Vxpipe.Persistence.{CredentialKeyring, Repo}

  using do
    quote do
      import Vxpipe.Console.Test.MCPCallbackNodeCase
      @moduletag :integration
      @moduletag timeout: 120_000
    end
  end

  setup_all do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    :ok
  end

  setup tags do
    database = "vxpipe_mcp_callback_" <> String.replace(Ecto.UUID.generate(), "-", "")
    repository = Repo.config() |> Keyword.delete(:url) |> Keyword.put(:database, database)
    :ok = Ecto.Adapters.Postgres.storage_up(repository)
    on_exit(fn -> :ok = Ecto.Adapters.Postgres.storage_down(repository) end)

    {:ok, keyring} =
      CredentialKeyring.new("callback", %{"callback" => :crypto.strong_rand_bytes(32)})

    context = [repo: Repo, keyring: keyring]
    mode = Map.get(tags, :mode, "dcr")
    state = start_supervised!({Agent, fn -> OutboundMCPOAuthServer.initial(mode) end})

    server =
      start_supervised!(
        {Bandit, plug: {OutboundMCPOAuthServer, state}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    base = "http://127.0.0.1:#{port}"
    OutboundMCPOAuthServer.configure(state, %{base: base})

    configuration = %{
      repository: repository,
      context: context,
      base: base,
      endpoint: Application.fetch_env!(:vxpipe_console, Vxpipe.Console.Endpoint),
      phoenix: Application.get_all_env(:phoenix)
    }

    peers =
      for index <- 0..1 do
        peer =
          start_supervised!(%{
            id: {:mcp_callback_node, index},
            start:
              {:peer, :start_link,
               [%{connection: :standard_io, args: [~c"+S", ~c"2:2", ~c"-pa" | :code.get_path()]}]},
            restart: :temporary
          })

        identity = :peer.call(peer, MCPCallbackNode, :boot, [configuration, index == 0], 60_000)
        {peer, identity}
      end

    [{first, a}, {second, b}] = peers
    assert a.os_pid != b.os_pid
    assert a.backend != b.backend
    refute System.pid() in [a.os_pid, b.os_pid]
    tenant = rpc(first, :setup_installation)
    session = rpc(first, :login)
    %{first: first, second: second, tenant: tenant, session: session, state: state, mode: mode}
  end

  def rpc(peer, function, args \\ []),
    do: :peer.call(peer, MCPCallbackNode, function, args, 30_000)

  def start(data), do: rpc(data.first, :start, [data.session, data.tenant, data.mode])
  def count(data, key), do: OutboundMCPOAuthServer.count(data.state, key)
  def tokens(data), do: count(data, {"POST", "/token"})
  def error(response), do: JSON.decode!(response.resp_body)["error"]["code"]

  def authorize(data, handoff) do
    response = OutboundMCPOAuthServer.authorize(data.state, handoff["authorization_url"])
    assert response.status == 303
    [location] = Req.Response.get_header(response, "location")
    location
  end

  def assert_returned(data, response, handoff, status) do
    assert response.status == 303, response.resp_body

    assert Plug.Conn.get_resp_header(response, "location") == [
             "/t/#{data.tenant}/services/search?q=calendar&mcp=#{status}&mcp_attempt=#{handoff["attempt_id"]}"
           ]

    assert Plug.Conn.get_resp_header(response, "cache-control") == ["private, no-store"]
    assert Plug.Conn.get_resp_header(response, "referrer-policy") == ["no-referrer"]
  end
end
