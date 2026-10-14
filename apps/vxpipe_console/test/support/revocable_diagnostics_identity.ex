defmodule Vxpipe.Console.Test.RevocableDiagnosticsIdentity do
  @moduledoc false

  use Agent

  alias Vxpipe.Console.Test.FakeUserIdentity

  @name __MODULE__

  def start_link(_options), do: Agent.start_link(fn -> :active end, name: @name)

  def as_kind(kind), do: Agent.update(@name, fn _ -> {:kind, kind} end)

  def revoke, do: Agent.update(@name, fn _ -> :revoked end)
  def unavailable, do: Agent.update(@name, fn _ -> :unavailable end)

  def authenticate(token) do
    case Agent.get(@name, & &1) do
      {:kind, kind} ->
        {:ok, principal} = FakeUserIdentity.authenticate(token)
        {:ok, %{principal | account_kind: kind}}

      :active ->
        FakeUserIdentity.authenticate(token)

      :revoked ->
        {:error, :invalid_session}

      :unavailable ->
        {:error, :unavailable}
    end
  end
end
