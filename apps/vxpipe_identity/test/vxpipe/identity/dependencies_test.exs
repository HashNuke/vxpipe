defmodule Vxpipe.Identity.DependenciesTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Identity

  setup do
    previous = Application.fetch_env(:vxpipe_identity, :dependencies)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:vxpipe_identity, :dependencies, value)
        :error -> Application.delete_env(:vxpipe_identity, :dependencies)
      end
    end)

    :ok
  end

  test "Identity exposes configured repository ports without Console composition" do
    dependencies = %{users: Vxpipe.Identity.FakeUsers, roles: Vxpipe.Identity.FakeRoles}
    Application.put_env(:vxpipe_identity, :dependencies, dependencies)

    assert Identity.dependencies() == {:ok, dependencies}
  end

  test "missing or invalid configuration fails closed" do
    Application.delete_env(:vxpipe_identity, :dependencies)
    assert Identity.dependencies() == {:error, :unavailable}

    Application.put_env(:vxpipe_identity, :dependencies, :disabled)
    assert Identity.dependencies() == {:error, :unavailable}
  end
end
