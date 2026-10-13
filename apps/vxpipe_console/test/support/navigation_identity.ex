defmodule Vxpipe.Console.Test.NavigationIdentity do
  @moduledoc false
  alias Vxpipe.Console.Test.FakeUserIdentity

  defdelegate login(email, password, address), to: FakeUserIdentity
  defdelegate logout(token), to: FakeUserIdentity
  def status, do: Application.get_env(:vxpipe_console, :navigation_test_status, {:ok, :complete})
  defdelegate session_details(principal), to: FakeUserIdentity

  def authenticate(token) do
    with {:ok, principal} <- FakeUserIdentity.authenticate(token) do
      Application.get_env(:vxpipe_console, :navigation_test_principal, {:ok, principal})
    end
  end
end
