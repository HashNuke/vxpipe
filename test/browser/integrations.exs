unless Mix.env() == :dev and System.get_env("VXPIPE_BROWSER_ACCEPTANCE") == "1" do
  raise "Run only in an isolated, setup-prepared development checkout with VXPIPE_BROWSER_ACCEPTANCE=1"
end

root = Path.expand("../..", __DIR__)
output = Path.join(root, ".vxpipe/browser")
File.mkdir_p!(output)
File.chmod!(output, 0o700)

for file <- ~w(outbound_mcp_oauth_server.ex mcp_browser_consent.ex mcp_browser_scenario.ex) do
  Code.require_file(Path.join(root, "apps/vxpipe_console/test/support/" <> file))
end

alias Vxpipe.Console.Test.{MCPBrowserConsent, MCPBrowserScenario, OutboundMCPOAuthServer}

mode = System.get_env("MCP_BROWSER_MODE", "cimd")
client_auth_method = System.get_env("MCP_BROWSER_CLIENT_AUTH_METHOD", "client_secret_basic")
{:ok, scenario} = MCPBrowserScenario.new(mode, client_auth_method: client_auth_method)
certificate = System.fetch_env!("VXPIPE_DEV_TLS_CERTFILE")
key = System.fetch_env!("VXPIPE_DEV_TLS_KEYFILE")
ca_certificate = System.fetch_env!("VXPIPE_BROWSER_CA_CERTFILE")
console_port = System.fetch_env!("PORT") |> String.to_integer()
peer_port = System.get_env("MCP_BROWSER_PORT", "0") |> String.to_integer()
origin = "https://localhost:#{console_port}"

{:ok, _} =
  Supervisor.start_child(
    Vxpipe.Console.Supervisor,
    {DynamicSupervisor, name: Vxpipe.Console.Test.BrowserPeers, strategy: :one_for_one}
  )

{:ok, state} =
  DynamicSupervisor.start_child(
    Vxpipe.Console.Test.BrowserPeers,
    {Agent, fn -> scenario.state end}
  )

metadata_fetch = fn url ->
  true = url == origin <> "/oauth/client-metadata.json"

  result =
    Req.get(url,
      redirect: false,
      retry: false,
      receive_timeout: 5_000,
      connect_options: [transport_opts: [cacertfile: String.to_charlist(ca_certificate)]]
    )

  case result do
    {:ok, %{status: 200, body: body}} when is_map(body) ->
      Agent.update(state, fn current ->
        %{current | count: Map.update(current.count, "client_metadata_fetch", 1, &(&1 + 1))}
      end)

      {:ok, body}

    _ ->
      {:error, :metadata_unavailable}
  end
end

options = %{state: state, metadata_fetch: metadata_fetch}

{:ok, http} =
  DynamicSupervisor.start_child(
    Vxpipe.Console.Test.BrowserPeers,
    {Bandit, plug: {MCPBrowserConsent, options}, ip: {127, 0, 0, 1}, port: 0}
  )

{:ok, tls} =
  DynamicSupervisor.start_child(
    Vxpipe.Console.Test.BrowserPeers,
    {Bandit,
     plug: {MCPBrowserConsent, options},
     scheme: :https,
     ip: {127, 0, 0, 1},
     port: peer_port,
     certfile: certificate,
     keyfile: key}
  )

{:ok, {_, http_port}} = ThousandIsland.listener_info(http)
{:ok, {_, tls_port}} = ThousandIsland.listener_info(tls)
resource = "https://mcp.example.test:#{tls_port}/mcp"
issuer = "https://auth.example.test:#{tls_port}"

OutboundMCPOAuthServer.configure(state, %{
  base: "http://127.0.0.1:#{http_port}",
  origin: origin,
  resource: resource,
  issuer: issuer
})

protocol = OutboundMCPOAuthServer.options(state)

ports = [
  mcp_preflight: {Vxpipe.Console.MCPPreflight, protocol},
  mcp_connection_probe: {Vxpipe.Console.MCPConnectionProbe, protocol},
  mcp_oauth_preparation: {Vxpipe.Console.MCPOAuthPreparation, protocol},
  mcp_oauth_completion: {Vxpipe.Console.MCPOAuthCompletion, protocol},
  mcp_oauth_refresh: {Vxpipe.Console.MCPOAuthRefresh, protocol}
]

calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
Application.put_env(:vxpipe_calls, Vxpipe.Calls, Keyword.merge(calls, ports))

credentials_path = Path.join(output, "credentials.json")
File.write!(credentials_path, JSON.encode!(scenario.credentials))
File.chmod!(credentials_path, 0o600)

File.write!(
  Path.join(output, "peer.json"),
  JSON.encode!(%{resource: resource, issuer: issuer, origin: origin, mode: mode})
)

IO.puts("Browser acceptance peer ready: #{resource} (#{mode})")
