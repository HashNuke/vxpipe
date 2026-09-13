defmodule Vxpipe.CallEngine.Readiness.ProviderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Readiness.Provider

  test "a provider without a readiness contract fails closed" do
    assert Provider.initial_status(__MODULE__) == :failed
    assert Provider.connected(:failed) == :failed
  end
end
