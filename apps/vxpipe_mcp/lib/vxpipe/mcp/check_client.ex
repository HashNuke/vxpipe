defmodule Vxpipe.MCP.CheckClient do
  @moduledoc false
  use GenServer, restart: :temporary
  alias Vxpipe.MCP.{CheckLifetime, ConnectionNames}

  def start_link(key),
    do: GenServer.start_link(__MODULE__, key, name: ConnectionNames.via(:client, key))

  @impl true
  def init(key), do: {:ok, %{key: key, module: nil, client: nil}, {:continue, :connect}}

  @impl true
  def handle_continue(:connect, state) do
    with {:ok, request} <- CheckLifetime.claim(state.key, :client),
         %{start: {module, :start_link, [options]}} <-
           Supervisor.child_spec(request.runtime.child_spec(request.client_options), []) do
      case module.init(options) do
        {:ok, client} ->
          :ok = CheckLifetime.ready(state.key)
          {:noreply, %{state | module: module, client: client}}

        _failed ->
          {:stop, :mcp_connection_failed, state}
      end
    else
      _failed -> {:stop, :mcp_connection_failed, state}
    end
  rescue
    _error -> {:stop, :mcp_connection_failed, state}
  catch
    _kind, _reason -> {:stop, :mcp_connection_failed, state}
  end

  @impl true
  def handle_call(message, from, state), do: delegate(:handle_call, [message, from], state)
  @impl true
  def handle_cast(message, state), do: delegate(:handle_cast, [message], state)
  @impl true
  def handle_info(message, state), do: delegate(:handle_info, [message], state)
  @impl true
  def format_status(status), do: Map.new(status, fn {key, _value} -> {key, :redacted} end)

  defp delegate(callback, arguments, state) do
    case apply(state.module, callback, arguments ++ [state.client]) do
      {:reply, reply, client} -> {:reply, reply, %{state | client: client}}
      {:reply, reply, client, timeout} -> {:reply, reply, %{state | client: client}, timeout}
      {:noreply, client} -> {:noreply, %{state | client: client}}
      {:noreply, client, timeout} -> {:noreply, %{state | client: client}, timeout}
      _stopped -> {:stop, :mcp_connection_failed, state}
    end
  rescue
    _error -> {:stop, :mcp_connection_failed, state}
  catch
    _kind, _reason -> {:stop, :mcp_connection_failed, state}
  end
end
