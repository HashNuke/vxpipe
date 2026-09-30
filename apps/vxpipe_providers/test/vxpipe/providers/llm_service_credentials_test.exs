defmodule Vxpipe.Providers.LLMServiceCredentialsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Registry

  test "direct LLM services accept only their private API key material" do
    for provider <- ["deepseek", "openrouter", "fireworks"] do
      assert {:ok, schema} = Registry.resolve_capability(provider, :credential)
      assert schema.auth_kind() == "api_key"
      assert :ok = schema.validate("api_key", %{"api_key" => "synthetic-key"})
      assert {:error, :invalid_provider_auth} = schema.validate("api_key", %{"api_key" => ""})

      assert {:error, :invalid_provider_auth} =
               schema.validate("api_key", %{"api_key" => "invalid key"})

      assert {:error, :invalid_provider_auth} =
               schema.validate("api_key", %{"api_key" => "synthetic", "url" => "https://todo"})

      assert schema.preview_fields() == [
               %{field: "api_key", label: "API key", display: :last_four}
             ]

      assert {:error, :unsupported_provider_capability} =
               Registry.fetch_capability(provider, :stt)
    end
  end

  test "read-only probes authenticate against fixed provider endpoints" do
    for {provider, url} <- [
          {"deepseek", "https://api.deepseek.com/models"},
          {"openrouter", "https://openrouter.ai/api/v1/key"}
        ] do
      assert {:ok, probe} = Registry.resolve_capability(provider, :credential_validation)
      assert {:ok, request} = probe.request("api_key", %{"api_key" => "synthetic"})
      assert Keyword.fetch!(request, :url) == url
      assert {"authorization", "Bearer synthetic"} in Keyword.fetch!(request, :headers)
    end

    assert {:error, :unsupported_provider_capability} =
             Registry.fetch_capability("fireworks", :credential_validation)
  end
end
