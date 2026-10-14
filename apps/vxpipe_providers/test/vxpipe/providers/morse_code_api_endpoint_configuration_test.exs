defmodule Vxpipe.Providers.MorseCodeApi.EndpointConfigurationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Providers.MorseCodeApi.Endpoint

  setup do
    previous = Application.fetch_env(:vxpipe_providers, :morse_code_api)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:vxpipe_providers, :morse_code_api, value)
        :error -> Application.delete_env(:vxpipe_providers, :morse_code_api)
      end
    end)
  end

  test "selected configuration never substitutes a host for absent or invalid origins" do
    Application.delete_env(:vxpipe_providers, :morse_code_api)
    assert {:error, :endpoint_not_configured} = Endpoint.configured()

    Application.put_env(:vxpipe_providers, :morse_code_api, base_url: "https://bad.example/path")
    assert {:error, :invalid_endpoint} = Endpoint.configured()

    Application.put_env(:vxpipe_providers, :morse_code_api,
      base_url: "http://morse-local:9876",
      allow_http?: true
    )

    assert {:ok, endpoint} = Endpoint.configured()
    assert endpoint.http == "http://morse-local:9876"
    assert endpoint.websocket == "ws://morse-local:9876"

    Application.put_env(:vxpipe_providers, :morse_code_api,
      base_url: "https://morse-audio.definerun.com"
    )

    assert {:ok, endpoint} = Endpoint.configured()
    assert endpoint.websocket == "wss://morse-audio.definerun.com"
  end
end
