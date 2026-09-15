defmodule Vxpipe.Persistence.TestPausingTelephonyRepo do
  @moduledoc false

  alias Ecto.Multi
  alias Vxpipe.Persistence.Repo

  defdelegate one(query), to: Repo

  def transaction(%Multi{} = multi) do
    case Process.get(:telephony_transaction_probe) do
      {:before, owner} ->
        pause(owner, :before_transaction)
        Repo.transaction(multi)

      {:after, owner} ->
        multi
        |> Multi.run(:test_after_inserts, fn _repo, _changes ->
          pause(owner, :after_inserts)
          {:ok, :observed}
        end)
        |> Repo.transaction()
    end
  end

  defp pause(owner, phase) do
    send(owner, {phase, self()})

    receive do
      :continue_transaction -> :ok
    after
      5_000 -> raise "test transaction barrier timed out"
    end
  end
end
