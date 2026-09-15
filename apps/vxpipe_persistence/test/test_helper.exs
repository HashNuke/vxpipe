ExUnit.start(exclude: [:integration])

{:ok, _supervisor} =
  Supervisor.start_link([Vxpipe.Persistence.Repo],
    strategy: :one_for_one,
    name: Vxpipe.Persistence.TestSupervisor
  )

Ecto.Adapters.SQL.Sandbox.mode(Vxpipe.Persistence.Repo, :manual)
