defmodule Vxpipe.MCP.ConnectionNames do
  @moduledoc false

  alias Vxpipe.MCP.ConnectionKey

  @registry Vxpipe.MCP.ConnectionRegistry

  def via(role, key, scope \\ nil, value \\ nil)

  def via(role, %ConnectionKey{} = key, scope, value) when role in [:client, :owner] do
    {:via, Registry, {@registry, name(role, key, scope), value}}
  end

  def lookup(role, key, scope \\ nil)

  def lookup(role, %ConnectionKey{} = key, scope) when role in [:client, :owner] do
    case Registry.lookup(@registry, name(role, key, scope)) do
      [{pid, _value}] -> if Process.alive?(pid), do: {:ok, pid}, else: :error
      [] -> :error
    end
  end

  def client(key, scope, owner) do
    case Registry.lookup(@registry, name(:client, key, scope)) do
      [{pid, %{integration_owner: ^owner}}] ->
        if Process.alive?(pid), do: {:ok, pid}, else: :error

      _mismatched_or_absent ->
        :error
    end
  end

  def policy(key, scope, owner) do
    case Registry.lookup(@registry, name(:owner, key, scope)) do
      [{^owner, %{policy: policy}}] -> {:ok, policy}
      _mismatched_or_absent -> :error
    end
  end

  def runtime(key, scope, owner) do
    case Registry.lookup(@registry, name(:owner, key, scope)) do
      [{^owner, %{runtime: runtime}}] -> {:ok, runtime}
      _mismatched_or_absent -> :error
    end
  end

  def sessions(key) do
    Registry.select(@registry, [
      {{{:owner, key}, :"$1", %{parent: :"$2"}}, [], [{{:"$2", :"$1"}}]},
      {{{:owner, :_, key}, :"$1", %{parent: :"$2"}}, [], [{{:"$2", :"$1"}}]}
    ])
  end

  def count do
    Registry.count_select(@registry, [
      {{{:owner, :_}, :_, %{parent: :_}}, [], [true]},
      {{{:owner, :_, :_}, :_, %{parent: :_}}, [], [true]}
    ])
  end

  defp name(role, key, nil), do: {role, key}
  defp name(role, key, scope) when is_pid(scope), do: {role, scope, key}
end
