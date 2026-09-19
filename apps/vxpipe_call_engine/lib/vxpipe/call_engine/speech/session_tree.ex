defmodule Vxpipe.CallEngine.Speech.SessionTree do
  @moduledoc false
  use Supervisor
  alias Vxpipe.CallEngine.Speech.{Allocation, CapabilityTree, Channel, Input, ScopeControl}

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      type: :supervisor,
      shutdown: :infinity
    }
  end

  def start_link({allocation, _public} = options) do
    if Allocation.valid?(allocation),
      do: Supervisor.start_link(__MODULE__, options, name: address(allocation)),
      else: {:error, :closed}
  end

  def address(allocation), do: CapabilityTree.address({allocation.generation, :allocation})
  def commands(allocation), do: CapabilityTree.address({allocation.generation, :commands})
  def providers(allocation), do: CapabilityTree.address({allocation.generation, :providers})

  def initialize(allocation, public) do
    provider = Keyword.fetch!(public, :provider)

    with true <- Allocation.valid?(allocation),
         {:ok, descriptor} <- provider.configure(Keyword.get(public, :options, [])),
         :ok <-
           Channel.configure(
             allocation,
             provider,
             descriptor,
             Keyword.get(public, :call_timeout, 5_000)
           ),
         {:ok, pid} <-
           DynamicSupervisor.start_child(providers(allocation), %{
             id: provider,
             start: {__MODULE__, :start_provider, [allocation, provider, descriptor]},
             restart: :temporary,
             shutdown: :brutal_kill
           }),
         :ok <- Channel.started(allocation, pid) do
      :ok
    else
      _failure -> ScopeControl.failed(allocation, :initialization_failed)
    end
  rescue
    _error -> ScopeControl.failed(allocation, :initialization_failed)
  catch
    _kind, _reason -> ScopeControl.failed(allocation, :initialization_failed)
  end

  def start_provider(allocation, provider, descriptor) do
    with {:ok, private} <- ScopeControl.claim(allocation),
         true <- Allocation.valid?(allocation),
         {:ok, pid} when is_pid(pid) <-
           provider.start_link(
             allocation: allocation,
             descriptor: descriptor,
             channel: Channel.address(allocation),
             private: private,
             start_deadline: allocation.deadline
           ) do
      {:ok, pid}
    else
      _failure -> {:error, :initialization_failed}
    end
  rescue
    _error -> {:error, :initialization_failed}
  catch
    _kind, _reason -> {:error, :initialization_failed}
  end

  @impl true
  def init({allocation, _public}) do
    children = [
      {Channel, allocation},
      Supervisor.child_spec({Input, allocation}, shutdown: :brutal_kill),
      {Task.Supervisor, name: commands(allocation)},
      {DynamicSupervisor, name: providers(allocation), strategy: :one_for_one}
    ]

    children =
      Enum.map(children, &Supervisor.child_spec(&1, restart: :temporary, significant: true))

    Supervisor.init(children, strategy: :one_for_all, auto_shutdown: :any_significant)
  end
end
