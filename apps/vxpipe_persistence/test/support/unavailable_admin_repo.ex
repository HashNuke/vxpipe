defmodule Vxpipe.Persistence.TestUnavailableAdminRepo do
  def all(_query), do: raise("could not lookup Ecto repo because it was not started")
  def one(_query), do: raise("could not lookup Ecto repo because it was not started")
end
