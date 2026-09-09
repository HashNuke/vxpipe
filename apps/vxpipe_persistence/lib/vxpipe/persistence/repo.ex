defmodule Vxpipe.Persistence.Repo do
  use Ecto.Repo,
    otp_app: :vxpipe_persistence,
    adapter: Ecto.Adapters.Postgres
end
