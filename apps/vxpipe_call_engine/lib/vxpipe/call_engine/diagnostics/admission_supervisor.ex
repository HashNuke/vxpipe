defmodule Vxpipe.CallEngine.Diagnostics.AdmissionSupervisor do
  @moduledoc "Optional admission subtree; its supplied gate survives tracker and subtree restarts."
  use Supervisor
  alias Vxpipe.CallEngine.Diagnostics.SourceAdmission

  def child_spec(options),
    do: %{
      id: {__MODULE__, Keyword.fetch!(options, :name)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      significant: false,
      shutdown: :infinity,
      type: :supervisor
    }

  def start_link(options),
    do: Supervisor.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))

  @impl true
  def init(options) do
    options = Keyword.validate!(options, [:name, :admission, :gate])

    children = [
      {SourceAdmission,
       name: Keyword.fetch!(options, :admission), gate: Keyword.fetch!(options, :gate)}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 2, max_seconds: 5)
  end
end
