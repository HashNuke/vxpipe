defmodule Vxpipe.CallEngine.Speech.Silero.Lease do
  @moduledoc false
  @enforce_keys [:table, :pool, :owner, :generation, :slot, :token]
  @derive {Inspect, only: []}
  defstruct @enforce_keys

  def open_table(name, capacity) do
    :ets.new(name, [:set, :public, :named_table, write_concurrency: true])
    table = :ets.whereis(name)
    :ets.insert(table, {:capacity, capacity, self()})
    table
  end

  def offer(server, generation) do
    table = :ets.whereis(server)

    with [{:capacity, capacity, pool}] <- :ets.lookup(table, :capacity) do
      first = :erlang.phash2(self(), capacity)

      lease = %__MODULE__{
        table: table,
        pool: pool,
        owner: self(),
        generation: generation,
        slot: first,
        token: make_ref()
      }

      take_slot(lease, capacity, capacity)
    else
      [] -> {:error, :model_unavailable}
    end
  rescue
    ArgumentError -> {:error, :model_unavailable}
  end

  def adopt(lease), do: move(lease, :offered, :active)
  def submit(lease), do: move(lease, :active, :submitted)
  def settle(lease), do: move(lease, :submitted, :active)

  defp move(lease, from, to) do
    before = entry(lease, from)
    after_entry = entry(lease, to)
    :ets.select_replace(lease.table, [{before, [], [{:const, after_entry}]}]) == 1
  end

  def withdraw(lease), do: :ets.delete_object(lease.table, entry(lease, :offered))

  def release(lease) do
    :ets.delete_object(lease.table, entry(lease, :active))
    :ets.delete_object(lease.table, entry(lease, :submitted))
  end

  defp take_slot(_lease, _capacity, 0), do: {:error, :busy}

  defp take_slot(lease, capacity, left) do
    if :ets.insert_new(lease.table, entry(lease, :offered)) do
      {:ok, lease}
    else
      take_slot(%{lease | slot: rem(lease.slot + 1, capacity)}, capacity, left - 1)
    end
  end

  defp entry(lease, phase), do: {lease.slot, lease.owner, lease.token, phase}
end
