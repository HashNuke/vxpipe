defmodule Vxpipe.Console.UserIdentityTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.UserIdentity

  test "missing identity storage fails closed for setup, login and session lookup" do
    original = Application.get_env(:vxpipe_identity, :dependencies)
    Application.delete_env(:vxpipe_identity, :dependencies)

    on_exit(fn ->
      if original do
        Application.put_env(:vxpipe_identity, :dependencies, original)
      else
        Application.delete_env(:vxpipe_identity, :dependencies)
      end
    end)

    assert UserIdentity.status() == {:error, :unavailable}

    assert UserIdentity.login("person@example.test", "password", "127.0.0.1") ==
             {:error, :unavailable}

    assert UserIdentity.authenticate(String.duplicate("a", 32)) == {:error, :unavailable}
  end
end
