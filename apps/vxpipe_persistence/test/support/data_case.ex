defmodule Vxpipe.Persistence.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Vxpipe.Persistence.Repo
    end
  end

  setup tags do
    owner =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Vxpipe.Persistence.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    :ok
  end
end
