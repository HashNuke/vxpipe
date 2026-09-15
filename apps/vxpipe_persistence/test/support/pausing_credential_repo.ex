defmodule Vxpipe.Persistence.TestPausingCredentialRepo do
  @moduledoc false

  alias Vxpipe.Persistence.Repo

  defdelegate transaction(operation, options), to: Repo
  defdelegate all(query, options), to: Repo
  defdelegate rollback(reason), to: Repo

  def update(changeset, options) do
    result = Repo.update(changeset, options)
    owner = Process.get(:reencryption_test_owner)
    send(owner, {:reencryption_row_written, self(), changeset.data.public_id})

    receive do
      :continue_reencryption -> result
    after
      5_000 -> Repo.rollback(:test_reencryption_timeout)
    end
  end
end
