defmodule Vxpipe.MCP.Connection do
  @moduledoc """
  An opaque handle to one supervised, ready MCP client session.

  The handle intentionally contains no endpoint headers or credentials.
  """

  alias Vxpipe.MCP.ConnectionKey

  @enforce_keys [:key, :owner, :client]
  defstruct [:key, :owner, :client]

  @opaque t :: %__MODULE__{
            key: ConnectionKey.t(),
            owner: pid(),
            client: GenServer.server()
          }

  @doc false
  @spec new(ConnectionKey.t(), pid(), GenServer.server()) :: t()
  def new(%ConnectionKey{} = key, owner, client) when is_pid(owner) do
    %__MODULE__{key: key, owner: owner, client: client}
  end

  @spec key(t()) :: ConnectionKey.t()
  def key(%__MODULE__{key: key}), do: key

  @spec owner(t()) :: pid()
  def owner(%__MODULE__{owner: owner}), do: owner

  @spec client(t()) :: GenServer.server()
  def client(%__MODULE__{client: client}), do: client
end
