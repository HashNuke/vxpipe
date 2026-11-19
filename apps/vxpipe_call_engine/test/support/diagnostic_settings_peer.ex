defmodule Vxpipe.CallEngine.DiagnosticSettingsPeer do
  @moduledoc false
  alias Vxpipe.CallEngine.Diagnostics.{SettingsProjection, SettingsSupervisor}
  @projection __MODULE__.Projection
  @reader __MODULE__.Reader

  def start(now) do
    clock = :atomics.new(1, signed: true)
    :atomics.put(clock, 1, now)
    :persistent_term.put({__MODULE__, :clock}, clock)
    write({:ok, %{enabled: true, revision: 1}})

    {:ok, supervisor} =
      SettingsSupervisor.start_link(
        name: __MODULE__.Supervisor,
        projection: @projection,
        reader: @reader,
        loader: fn -> :persistent_term.get({__MODULE__, :snapshot}) end,
        clock: fn -> :atomics.get(clock, 1) end,
        send_after: fn _, _, _ -> make_ref() end
      )

    # The owning peer VM is supervised by ExUnit; its exit owns this root's lifetime.
    Process.unlink(supervisor)
    settle()
    status()
  end

  def write(result), do: :persistent_term.put({__MODULE__, :snapshot}, result)
  def invalidate, do: SettingsProjection.invalidate(@projection)
  def status, do: SettingsProjection.status(@projection)
  def granted?, do: match?({:ok, _}, SettingsProjection.grant(@projection))
  def suspend, do: :sys.suspend(@projection)
  def resume, do: :sys.resume(@projection)

  def advance(now) do
    :atomics.put(:persistent_term.get({__MODULE__, :clock}), 1, now)
    :ok
  end

  def refresh do
    state = :sys.get_state(@projection)
    send(@projection, {:poll, state.poll})
    settle()
    status()
  end

  defp settle do
    _ = :sys.get_state(@projection)
    _ = :sys.get_state(@reader)
    _ = :sys.get_state(@projection)
    :ok
  end
end
