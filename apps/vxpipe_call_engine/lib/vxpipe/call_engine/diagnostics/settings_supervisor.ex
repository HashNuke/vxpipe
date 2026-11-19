defmodule Vxpipe.CallEngine.Diagnostics.SettingsSupervisor do
  @moduledoc "Isolated settings reader/projection pair; exhausted restarts degrade diagnostics only."
  use Supervisor
  alias Vxpipe.CallEngine.Diagnostics.{SettingsProjection, SettingsReader}

  def child_spec(options),
    do: %{
      id: {__MODULE__, Keyword.fetch!(options, :name)},
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor,
      restart: :temporary
    }

  def start_link(options),
    do: Supervisor.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))

  @impl true
  def init(options) do
    options =
      Keyword.validate!(options, [
        :name,
        :projection,
        :reader,
        :loader,
        clock: fn -> System.monotonic_time(:millisecond) end,
        send_after: &Process.send_after/3
      ])

    names = Enum.map([:name, :projection, :reader], &Keyword.fetch!(options, &1))

    unless Enum.all?(names, &(is_atom(&1) and &1 != nil)) and length(Enum.uniq(names)) == 3 and
             is_function(Keyword.fetch!(options, :loader), 0) and
             is_function(Keyword.fetch!(options, :clock), 0) and
             is_function(Keyword.fetch!(options, :send_after), 3),
           do: raise(ArgumentError, "invalid diagnostic settings pool")

    Supervisor.init([{SettingsReader, options}, {SettingsProjection, options}],
      strategy: :one_for_all
    )
  end
end
