defmodule Vxpipe.Console.Test.MCPBrowserScenario do
  @moduledoc "Startup-selected protocol scenarios with fresh local acceptance credentials."
  alias Vxpipe.Console.Test.OutboundMCPOAuthServer
  alias Vxpipe.MCP.{Authentication, StaticConfiguration}

  def new(mode) when mode in ~w(cimd dcr own_client),
    do: {:ok, %{state: OutboundMCPOAuthServer.initial(mode), credentials: %{}}}

  def new(mode) when mode in ~w(none bearer headers basic) do
    credentials = credentials(mode)

    {:ok, configuration} =
      StaticConfiguration.new(%{
        "endpoint" => OutboundMCPOAuthServer.resource(),
        "auth_method" => mode,
        "credentials" => credentials
      })

    {:ok, headers} = Authentication.headers(configuration.authentication)
    state = Map.put(OutboundMCPOAuthServer.initial(mode), :static_headers, headers)
    {:ok, %{state: state, credentials: credentials}}
  end

  def new(_mode), do: {:error, :unsupported_browser_scenario}

  defp credentials("none"), do: %{}
  defp credentials("bearer"), do: %{"token" => secret()}
  defp credentials("basic"), do: %{"username" => "fixture-user", "password" => secret()}

  defp credentials("headers"),
    do: %{"headers" => [%{"name" => "x-api-key", "value" => secret()}]}

  defp secret, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end
