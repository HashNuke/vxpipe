defmodule Vxpipe.CallEngine.RemoteMCP.ApplicationConfigurationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.RemoteMCP.ApplicationConfiguration

  @configuration_key :test_remote_mcp_integrations

  setup do
    previous = Application.get_env(:vxpipe_call_engine, @configuration_key, :not_configured)

    on_exit(fn -> restore_configuration(previous) end)
  end

  test "loads application and tenant integrations from raw OTP application settings" do
    private_value = "private-application-configuration-value"

    Application.put_env(:vxpipe_call_engine, @configuration_key, [
      [
        scope: :application,
        integration_id: "utilities",
        configuration_generation: "configuration-1",
        credential_generation: "credential-1",
        catalog_generation: "catalog-1",
        allowed_tools: ["clock"],
        client_config: [
          endpoint: "https://utilities.example.test/mcp",
          headers: [{"authorization", private_value}]
        ]
      ],
      [
        scope: {:tenant, "tenant-demo"},
        integration_id: "records",
        configuration_generation: "configuration-2",
        credential_generation: "credential-2",
        catalog_generation: "catalog-2",
        allowed_tools: ["lookup_customer"],
        client_config: [endpoint: "https://records.example.test/mcp"]
      ]
    ])

    assert {:ok, [application, tenant]} =
             ApplicationConfiguration.fetch(
               application: :vxpipe_call_engine,
               key: @configuration_key
             )

    assert application.connection_key.scope == :application
    assert application.connection_key.integration_id == "utilities"
    assert tenant.connection_key.scope == {:tenant, "tenant-demo"}
    assert tenant.connection_key.integration_id == "records"
    refute inspect([application, tenant]) =~ private_value
    refute inspect([application, tenant]) =~ "authorization"
  end

  test "returns no integrations when the application setting is absent" do
    Application.delete_env(:vxpipe_call_engine, @configuration_key)

    assert {:ok, []} =
             ApplicationConfiguration.fetch(
               application: :vxpipe_call_engine,
               key: @configuration_key
             )
  end

  test "rejects the complete source when any configured record is invalid" do
    Application.put_env(:vxpipe_call_engine, @configuration_key, [
      [
        scope: :application,
        integration_id: "utilities",
        configuration_generation: "configuration-1",
        credential_generation: "credential-1",
        catalog_generation: "catalog-1",
        allowed_tools: ["clock"],
        client_config: [endpoint: "https://utilities.example.test/mcp"]
      ],
      [scope: {:tenant, "tenant-demo"}, integration_id: "invalid"]
    ])

    assert {:error, :invalid_remote_mcp_configuration} =
             ApplicationConfiguration.fetch(
               application: :vxpipe_call_engine,
               key: @configuration_key
             )
  end

  defp restore_configuration(:not_configured) do
    Application.delete_env(:vxpipe_call_engine, @configuration_key)
  end

  defp restore_configuration(previous) do
    Application.put_env(:vxpipe_call_engine, @configuration_key, previous)
  end
end
