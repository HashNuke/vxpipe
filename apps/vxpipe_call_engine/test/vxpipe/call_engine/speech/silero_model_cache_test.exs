defmodule Vxpipe.CallEngine.Speech.Silero.ModelCacheTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Silero.{Model, ModelCache}

  test "owners leaving a blocked model load release their waiters" do
    parent = self()

    server =
      start_supervised!(
        {ModelCache,
         name: __MODULE__,
         load: fn ->
           send(parent, {:loading, self()})

           receive do
             :finish -> {:error, :model_unavailable}
           end
         end}
      )

    owner = spawn(fn -> ModelCache.fetch(server, 15_000) end)
    assert_receive {:loading, loader}
    ref = Process.monitor(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^ref, :process, ^owner, :killed}
    assert map_size(:sys.get_state(server).waiting) == 0
    send(loader, :finish)
  end

  test "expired waiters cannot retry an unsuccessful load" do
    parent = self()

    server =
      start_supervised!(
        {ModelCache,
         name: __MODULE__,
         load: fn ->
           send(parent, {:loading, self()})

           receive do
             :finish -> {:error, :model_unavailable}
           end
         end}
      )

    first = Task.async(fn -> ModelCache.fetch(server, 1000) end)
    assert_receive {:loading, loader_pid}
    assert {:error, :model_unavailable} = ModelCache.fetch(server, 10)
    send(loader_pid, :finish)
    assert {:error, :model_unavailable} = Task.await(first)
    refute_receive {:loading, _}, 30
  end

  test "a missed preparation deadline permits a later caller to reuse the completed load" do
    test_pid = self()
    model = %Model{resource: :test, sample_rate: 16_000}

    loader = fn ->
      send(test_pid, {:loading, self()})

      receive do
        :finish -> {:ok, model}
      end
    end

    server = start_supervised!({ModelCache, name: __MODULE__, load: loader})
    task = Task.async(fn -> ModelCache.fetch(server, 50) end)
    assert_receive {:loading, loader_pid}
    assert Task.await(task) == {:error, :model_unavailable}
    send(loader_pid, :finish)
    assert {:ok, ^model} = ModelCache.fetch(server, 5_000)
    refute_received {:loading, _}
  end
end
