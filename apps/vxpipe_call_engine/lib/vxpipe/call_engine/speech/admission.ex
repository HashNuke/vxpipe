defmodule Vxpipe.CallEngine.Speech.Admission do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.{Allocation, ScopeControl, SessionTree}

  def start_link(options), do: GenServer.start_link(__MODULE__, nil, options)

  def submit(allocation, public),
    do: GenServer.cast(allocation.scope.admissions, {:admit, allocation, public})

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_cast({:admit, allocation, public}, state) do
    result = admit(allocation, public)
    send(allocation.scope.control, {:admitted, allocation, result})
    {:noreply, state}
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :speech_admission)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp admit(allocation, public) do
    with true <- Allocation.valid?(allocation),
         {:ok, tree} <-
           DynamicSupervisor.start_child(
             allocation.scope.sessions,
             {SessionTree, {allocation, public}}
           ),
         :ok <- ScopeControl.bind(allocation, tree),
         {:ok, _worker} <-
           Task.Supervisor.start_child(SessionTree.commands(allocation), fn ->
             SessionTree.initialize(allocation, public)
           end) do
      :ok
    else
      _failure -> :error
    end
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end
end
