defmodule Vxpipe.CallEngine.SpeechExperiment.Allocation do
  @moduledoc false
  use Supervisor

  alias Vxpipe.CallEngine.SpeechExperiment.{Control, Worker}

  def start_link(options) do
    if System.monotonic_time(:millisecond) < Keyword.fetch!(options, :deadline) do
      token = Keyword.fetch!(options, :token)
      Supervisor.start_link(__MODULE__, options, name: address(token))
    else
      {:error, :expired}
    end
  end

  def child_spec(options) do
    %{
      id: make_ref(),
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor,
      restart: :temporary,
      shutdown: 1_000
    }
  end

  def address(token),
    do: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, token}}}

  def init(options) do
    children =
      Enum.map([Control, Worker], fn module ->
        Supervisor.child_spec({module, options},
          restart: :temporary,
          significant: true,
          shutdown: :brutal_kill
        )
      end)

    Supervisor.init(children, strategy: :one_for_all, auto_shutdown: :any_significant)
  end
end
