defmodule Vxpipe.Gateway.WebRTC.ConnectionIncarnationSupervisor do
  @moduledoc false

  use Supervisor

  alias Vxpipe.Gateway.{CallCleanup, CallCleanupSupervisor}
  alias Vxpipe.Gateway.Session.Snapshot
  alias Vxpipe.Gateway.WebRTC.{Connection, ConnectionPeerSupervisor}

  def start_link(options), do: Supervisor.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  @impl true
  def init(options) do
    case register_cleanup(Keyword.fetch!(options, :session)) do
      :ok ->
        connection = options |> Connection.child_spec() |> Map.put(:significant, true)

        Supervisor.init([{ConnectionPeerSupervisor, options}, connection],
          strategy: :one_for_one,
          auto_shutdown: :any_significant
        )

      {:error, _reason} ->
        :ignore
    end
  end

  defp register_cleanup(session) do
    case Snapshot.cleanup_binding(session) do
      {:ok, nil} ->
        :ok

      {:ok, binding} ->
        with {:ok, tracker} <- CallCleanupSupervisor.lookup(binding),
             :ok <- CallCleanup.register(tracker, :web_rtc, self()) do
          # This local tree has no independent carrier or durable usage obligation.
          # Completion still requires orderly DOWN of this entire supervision root.
          CallCleanup.acknowledge(tracker, self(), :complete)
        end

      {:error, _reason} = error ->
        error
    end
  catch
    :exit, _reason -> {:error, :cleanup_unavailable}
  end
end
