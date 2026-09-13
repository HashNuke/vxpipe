defmodule Vxpipe.CallEngine.Capability.SpeechToText.TransportConnector do
  @moduledoc false

  @supervisor Vxpipe.CallEngine.SpeechToTextConnectionTaskSupervisor

  @spec start(module(), map(), keyword()) :: {:ok, map()} | {:error, :unavailable}
  def start(module, connection, options) do
    owner = self()

    case Task.Supervisor.start_child(@supervisor, fn ->
           connect(owner, module, connection, options)
         end) do
      {:ok, pid} -> {:ok, %{pid: pid, monitor: Process.monitor(pid)}}
      {:error, _reason} -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec stop(map()) :: :ok
  def stop(%{pid: pid, monitor: monitor}) do
    Process.demonitor(monitor, [:flush])
    Process.exit(pid, :shutdown)
    :ok
  end

  defp connect(owner, module, connection, options) do
    Process.link(owner)
    owner_monitor = Process.monitor(owner)

    case module.start_link(owner: self(), connection: connection, transport_options: options) do
      {:ok, transport} ->
        transport_monitor = Process.monitor(transport)
        send(owner, {:vxpipe_stt_connected, self(), transport})
        forward(owner, owner_monitor, transport, transport_monitor)

      {:error, _reason} ->
        :ok
    end
  end

  # Forward from the same sender as readiness so even an immediate provider callback
  # is processed only after the capability has bound this session to its revision.
  defp forward(owner, owner_monitor, transport, transport_monitor) do
    receive do
      {:vxpipe_stt_transport, ^transport, event} ->
        send(owner, {:vxpipe_stt_transport, transport, event})
        forward(owner, owner_monitor, transport, transport_monitor)

      {:DOWN, ^transport_monitor, :process, ^transport, _reason} ->
        :ok

      {:DOWN, ^owner_monitor, :process, ^owner, _reason} ->
        Process.exit(transport, :shutdown)
    end
  end
end
