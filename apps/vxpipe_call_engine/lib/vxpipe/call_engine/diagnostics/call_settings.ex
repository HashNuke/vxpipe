defmodule Vxpipe.CallEngine.Diagnostics.CallSettings do
  @moduledoc "Immutable diagnostics opt-in captured once before a new room starts."
  @enforce_keys [:enabled, :revision, :token]
  defstruct @enforce_keys

  def new(%{enabled: enabled, revision: revision})
      when is_boolean(enabled) and is_integer(revision) and revision >= 0,
      do: %__MODULE__{enabled: enabled, revision: revision, token: make_ref()}

  def new(_unavailable), do: %__MODULE__{enabled: false, revision: nil, token: make_ref()}

  def grant(%__MODULE__{enabled: true, revision: revision, token: token}),
    do: {:ok, {revision, token}}

  def grant(_disabled), do: {:error, :unavailable}

  def capture do
    settings = Application.get_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, [])

    case Keyword.get(settings, :diagnostics_settings_loader) do
      loader when is_function(loader, 0) -> read(loader)
      _ -> new(nil)
    end
  end

  defp read(loader) do
    {pid, monitor} =
      spawn_monitor(fn ->
        snapshot =
          try do
            loader.()
          rescue
            _ -> {:error, :unavailable}
          catch
            _, _ -> {:error, :unavailable}
          end

        exit({:snapshot, snapshot})
      end)

    # The timer also bounds the worker if the room creator exits during the read.
    {:ok, timer} = :timer.kill_after(250, pid)

    try do
      receive do
        {:DOWN, ^monitor, :process, ^pid, {:snapshot, {:ok, snapshot}}} -> new(snapshot)
        {:DOWN, ^monitor, :process, ^pid, _reason} -> new(nil)
      after
        250 ->
          Process.exit(pid, :kill)

          receive do
            {:DOWN, ^monitor, :process, ^pid, _reason} -> new(nil)
          end
      end
    after
      :timer.cancel(timer)
    end
  end
end
