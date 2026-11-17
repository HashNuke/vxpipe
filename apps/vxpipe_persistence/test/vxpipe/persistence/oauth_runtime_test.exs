defmodule Vxpipe.Persistence.OAuthRuntimeTest do
  use ExUnit.Case, async: false

  @runtime Path.expand("../../../../../config/runtime.exs", __DIR__)
  @variable "VXPIPE_MCP_ACCESS_TOKEN_TTL_SECONDS"

  setup do
    previous = System.get_env(@variable)
    System.delete_env(@variable)

    on_exit(fn ->
      if previous, do: System.put_env(@variable, previous), else: System.delete_env(@variable)
    end)
  end

  test "access token lifetime defaults to an hour" do
    assert configured_lifetime() == 3600
  end

  test "access token lifetime can be configured in seconds" do
    System.put_env(@variable, "60")
    assert configured_lifetime() == 60
  end

  test "invalid lifetimes fail startup without disclosing the value" do
    for value <- ["0", "-1", "86401", "1.5", "60s", "private-invalid-content"] do
      System.put_env(@variable, value)

      assert_raise RuntimeError,
                   "invalid VXPIPE_MCP_ACCESS_TOKEN_TTL_SECONDS: expected an integer from 1 to 86400",
                   fn -> configured_lifetime() end
    end
  end

  defp configured_lifetime do
    @runtime
    |> Config.Reader.read!(env: :test)
    |> Keyword.fetch!(:vxpipe_persistence)
    |> Keyword.fetch!(:oauth_access_token_ttl_seconds)
  end
end
