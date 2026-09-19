defmodule Vxpipe.CallEngine.Speech.SessionTree do
  @moduledoc false
  use Supervisor

  alias Vxpipe.CallEngine.Speech.Channel

  def start_link(options) do
    name = {:via, Registry, {Vxpipe.CallEngine.Speech.Registry, {:tree, make_ref()}}}
    private_init = :ets.new(__MODULE__, [:set, :protected])
    :ets.insert(private_init, {:private, Keyword.get(options, :private, [])})
    deadline = System.monotonic_time(:millisecond) + Keyword.fetch!(options, :start_timeout)

    public_options =
      options
      |> Keyword.take([:owner, :provider, :descriptor, :call_timeout, :start_timeout])
      |> Keyword.put(:private_init, private_init)
      |> Keyword.put(:start_deadline, deadline)

    try do
      with {:ok, session} <- Supervisor.start_link(__MODULE__, public_options, name: name),
           :ok <- Channel.activate(session) do
        {:ok, session}
      else
        _failure -> {:error, :initialization_failed}
      end
    after
      :ets.delete(private_init)
    end
  catch
    :exit, _reason -> {:error, :initialization_failed}
  end

  def commands(session),
    do: {:via, Registry, {Vxpipe.CallEngine.Speech.Registry, {:commands, session}}}

  # The supervisor retains only the opaque ETS reference in its initial args and
  # child spec. The starting owner deletes the short-lived snapshot on every exit.
  def start_provider(provider, options) do
    [{:private, private}] = :ets.lookup(Keyword.fetch!(options, :private_init), :private)
    private_init = options |> Keyword.delete(:private_init) |> Keyword.put(:private, private)

    case provider.start_link(private_init) do
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      _failure -> {:error, :initialization_failed}
    end
  rescue
    _error -> {:error, :initialization_failed}
  catch
    _kind, _reason -> {:error, :initialization_failed}
  end

  @impl true
  def init(options) do
    options = Keyword.put(options, :session, self())
    provider = Keyword.fetch!(options, :provider)

    provider_options = [
      descriptor: Keyword.fetch!(options, :descriptor),
      channel: Channel.address(self()),
      private_init: Keyword.fetch!(options, :private_init),
      start_deadline: Keyword.fetch!(options, :start_deadline)
    ]

    children = [
      Supervisor.child_spec({Channel, Keyword.delete(options, :private_init)},
        restart: :temporary,
        significant: true
      ),
      Supervisor.child_spec({Task.Supervisor, name: commands(self())},
        restart: :temporary,
        significant: true
      ),
      %{
        id: provider,
        start: {__MODULE__, :start_provider, [provider, provider_options]},
        restart: :temporary,
        significant: true,
        shutdown: 5_000
      }
    ]

    Supervisor.init(children, strategy: :one_for_all, auto_shutdown: :any_significant)
  end
end
