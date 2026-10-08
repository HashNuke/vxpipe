defmodule Vxpipe.CallEngine.RemoteMCP.ConfiguredNamesTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.RemoteMCP.ConfiguredNames

  setup do
    old = Application.get_env(:vxpipe_call_engine, :remote_mcp_integrations)

    on_exit(fn ->
      if old,
        do: Application.put_env(:vxpipe_call_engine, :remote_mcp_integrations, old),
        else: Application.delete_env(:vxpipe_call_engine, :remote_mcp_integrations)
    end)
  end

  test "lists only application and matching tenant names without tools, URLs or credentials" do
    configured =
      for {scope, name} <- [
            {:application, "common"},
            {{:tenant, "one"}, "calendar"},
            {{:tenant, "one"}, "common"},
            {{:tenant, "two"}, "foreign"}
          ] do
        [
          scope: scope,
          integration_id: name,
          configuration_generation: "one",
          credential_generation: "one",
          catalog_generation: "one",
          allowed_tools: ["private-tool"],
          client_config: [
            endpoint: "https://private.example.test/mcp",
            authentication: [
              type: :custom_headers,
              headers: [{"authorization", "private-config-sentinel"}]
            ]
          ]
        ]
      end

    Application.put_env(:vxpipe_call_engine, :remote_mcp_integrations, configured)
    assert {:ok, ["calendar", "common"]} = ConfiguredNames.list("one")
    assert {:ok, ["common", "foreign"]} = ConfiguredNames.list("two")
  end

  test "empty configuration succeeds and invalid configuration fails closed" do
    Application.put_env(:vxpipe_call_engine, :remote_mcp_integrations, [])
    assert {:ok, []} = ConfiguredNames.list("one")

    Application.put_env(:vxpipe_call_engine, :remote_mcp_integrations, [
      [integration_id: "invalid"]
    ])

    assert {:error, :invalid_remote_mcp_configuration} = ConfiguredNames.list("one")
  end
end
