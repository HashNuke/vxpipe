defmodule Vxpipe.MCP.Connection do
  @moduledoc """
  An opaque handle to one supervised, ready MCP client session.

  The handle intentionally contains no endpoint headers or credentials.
  """

  alias Vxpipe.MCP.ConnectionKey

  @enforce_keys [:key, :owner, :client, :session_owner]
  defstruct @enforce_keys

  @opaque t :: %__MODULE__{
            key: ConnectionKey.t(),
            owner: pid(),
            client: GenServer.server(),
            session_owner: pid()
          }

  @doc false
  @spec new(ConnectionKey.t(), pid(), GenServer.server()) :: t()
  def new(%ConnectionKey{} = key, owner, client) when is_pid(owner) do
    new(key, owner, client, Process.whereis(Vxpipe.MCP.ConnectionSupervisor))
  end

  @doc false
  @spec new(ConnectionKey.t(), pid(), GenServer.server(), pid()) :: t()
  def new(%ConnectionKey{} = key, owner, client, session_owner)
      when is_pid(owner) and is_pid(session_owner) do
    %__MODULE__{key: key, owner: owner, client: client, session_owner: session_owner}
  end

  @spec key(t()) :: ConnectionKey.t()
  def key(%__MODULE__{key: key}), do: key

  @spec owner(t()) :: pid()
  def owner(%__MODULE__{owner: owner}), do: owner

  @doc "Returns the exact host supervisor that owns this session."
  @spec session_owner(t()) :: pid()
  def session_owner(%__MODULE__{session_owner: owner}), do: owner

  @spec client(t()) :: GenServer.server()
  def client(%__MODULE__{client: client}), do: client
end
