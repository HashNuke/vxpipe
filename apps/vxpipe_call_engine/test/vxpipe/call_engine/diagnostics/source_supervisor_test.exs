defmodule Vxpipe.CallEngine.Diagnostics.SourceSupervisorTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.{SourcePort, SourceSupervisor}
  alias Vxpipe.CallEngine.Speech.ActivitySupervisor

  test "node pool exposes the injected port and lazy shared inference without owning room workers" do
    parent = self()
    collector = fn _ -> {:error, :unavailable} end

    pool =
      start_supervised!(
        {SourceSupervisor,
         name: __MODULE__.Pool,
         inference: __MODULE__.Inference,
         tasks: __MODULE__.Tasks,
         runtime: __MODULE__.Runtime,
         port: __MODULE__.Port,
         maximum_sources: 2,
         collector: collector,
         load: fn ->
           send(parent, :loaded)
           {:ok, :model}
         end}
      )

    assert {:ok, port} = SourcePort.read(__MODULE__.Port)
    assert port.collector == collector
    assert port.runtime == __MODULE__.Runtime
    assert port.maximum_sources == 2

    assert Enum.sort(Enum.map(Supervisor.which_children(pool), &elem(&1, 0))) ==
             Enum.sort([ActivitySupervisor, SourcePort])

    refute_received :loaded
  end
end
