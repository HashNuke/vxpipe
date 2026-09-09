defmodule Vxpipe.MCP.ConnectionNames do
  @moduledoc false

  alias Vxpipe.MCP.ConnectionKey

  @registry Vxpipe.MCP.ConnectionRegistry

  @spec via(:client | :owner, ConnectionKey.t()) :: GenServer.name()
  def via(role, %ConnectionKey{} = key) when role in [:client, :owner] do
    {:via, Registry, {@registry, {role, key}}}
  end

  @spec lookup(:client | :owner, ConnectionKey.t()) :: {:ok, pid()} | :error
  def lookup(role, %ConnectionKey{} = key) when role in [:client, :owner] do
    case Registry.lookup(@registry, {role, key}) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end
end
