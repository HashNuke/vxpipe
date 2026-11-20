defmodule Vxpipe.CallEngine.TestCallSettings do
  @moduledoc false
  alias Vxpipe.CallEngine.Diagnostics.CallSettings

  def start!(name, options \\ []) do
    table = :ets.new(name, [:named_table, :protected, :set])

    snapshot =
      CallSettings.new(%{
        enabled: Keyword.get(options, :enabled, true),
        revision: Keyword.get(options, :revision, 1)
      })

    true = :ets.insert(table, {:snapshot, snapshot})
    :ok
  end

  def get(name) do
    [{:snapshot, snapshot}] = :ets.lookup(name, :snapshot)
    snapshot
  end
end
