defmodule Vxpipe.CallEngine.Speech.Silero.PoolAdmissionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Silero.Pool

  setup do
    start_supervised!({Pool, name: __MODULE__, budget: %{workers: 1}, leases_per_worker: 1})
    :ok
  end

  test "reserves at most the pool limit and rejects a stale release after reuse" do
    assert {:ok, lease} = reserve()
    assert {:error, :busy} = reserve()
    assert :ok = Pool.close(lease)
    assert {:ok, next} = reserve()
    assert {:error, :unknown_lease} = Pool.close(lease)
    assert %{admitted: 1, admission_limit: 1} = Pool.status(__MODULE__)
    assert :ok = Pool.close(next)
  end

  test "only the owner can close its allocation" do
    assert {:ok, lease} = reserve()
    assert {:error, :unknown_lease} = Task.async(fn -> Pool.close(lease) end) |> Task.await()
    assert :ok = Pool.close(lease)
  end

  test "reclaims credits after the allocation owner exits" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, lease} = reserve()
        send(parent, {:reserved, lease})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:reserved, lease}
    # The dispatcher acknowledges processing the owner's monitor signal through status.
    monitor = Process.monitor(owner)
    send(owner, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    assert_eventually_released(lease, 50)
    assert {:ok, _} = reserve()
  end

  defp assert_eventually_released(lease, left) when left > 0 do
    case Pool.status(__MODULE__) do
      %{admitted: 0} -> :ok
      _ -> assert_eventually_released(lease, left - 1)
    end
  end

  test "refuses expired preparation before reserving capacity" do
    assert {:error, :model_unavailable} =
             Pool.reserve(make_ref(), System.monotonic_time(:millisecond) - 1, __MODULE__)

    assert %{admitted: 0} = Pool.status(__MODULE__)
  end

  defp reserve,
    do: Pool.reserve(make_ref(), System.monotonic_time(:millisecond) + 5_000, __MODULE__)
end
