defmodule Vxpipe.CallEngine.RemoteMCP.SourceBudgetTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.{CatalogStore, IntegrationOwner}
  alias Vxpipe.CallEngine.RemoteMCPFixture

  test "waiting for the catalog shares the original initialization budget and cannot open later" do
    sessions = RemoteMCPFixture.session_supervisor!()
    bindings = RemoteMCPFixture.session_supervisor!()
    client = start_supervised!({Agent, fn -> %{responses: [], invocations: []} end})
    {catalog, binding} = RemoteMCPFixture.binding!(client, self(), "private")
    source = RemoteMCPFixture.source!(catalog)
    observer = self()
    deadline = System.monotonic_time(:millisecond) + 500
    :ok = :sys.suspend(source)
    :erlang.trace(bindings, true, [:send, :set_on_spawn, {:tracer, observer}])

    start_supervised!(
      {Task,
       fn ->
         result =
           DynamicSupervisor.start_child(
             bindings,
             {IntegrationOwner,
              activation_id: "source-budget",
              session_supervisor: sessions,
              lifecycle_owner: observer,
              initialization: {observer, deadline},
              tools: %{"customer_lookup" => binding},
              integrations: source,
              connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
              protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
           )

         send(observer, {:started, result})
       end}
    )

    try do
      assert_receive {:"$gen_call", from,
                      {:mcp_initialization_budget, "source-budget", ^observer, ^deadline}},
                     1_000

      GenServer.reply(from, {:ok, deadline, observer})
      assert_receive {:trace, worker, :send, {:"$gen_call", _, :snapshot}, ^source}, 1_000
      monitor = Process.monitor(worker)
      assert_receive {:started, {:error, _}}, 1_000
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 500
      :ok = :sys.resume(source)
      {:ok, ^catalog} = CatalogStore.snapshot(source)
      refute_receive {:test_remote_mcp_opened, _, _}, 100
    after
      :erlang.trace(bindings, false, [:send, :set_on_spawn])
      :sys.resume(source)
    end
  end
end
