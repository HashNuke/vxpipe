defmodule Vxpipe.CallEngine.Readiness.ProviderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Readiness.Provider

  test "a failed provider remains failed when a late connection arrives" do
    assert Provider.connected(:failed) == :failed
  end
end
