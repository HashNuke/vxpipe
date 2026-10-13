defmodule Vxpipe.Identity.FakeHasher do
  @behaviour Vxpipe.Identity.PasswordHasher
  @impl true
  def hash(password), do: {:ok, "hash:" <> password}
  @impl true
  def verify(password, "hash:" <> password), do: true
  def verify(_, _), do: false
end
