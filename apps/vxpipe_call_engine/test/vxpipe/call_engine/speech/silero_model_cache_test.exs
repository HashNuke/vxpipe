defmodule Vxpipe.CallEngine.Speech.Silero.ModelCacheTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Silero.{Model, ModelCache}

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
    assert_receive {:loading, ^server}
    assert Task.await(task) == {:error, :model_unavailable}
    send(server, :finish)
    assert {:ok, ^model} = ModelCache.fetch(server, 5_000)
    refute_received {:loading, _}
  end
end
