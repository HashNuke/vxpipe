defmodule Vxpipe.CallEngine.RoomDialSupervisor do
  @moduledoc false

  def start_link(options) do
    Task.Supervisor.start_link(
      name: via(Keyword.fetch!(options, :incarnation_id)),
      max_children: 1
    )
  end

  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, type: :supervisor}
  end

  def submit(incarnation_id, callback) do
    Task.Supervisor.async_nolink(via(incarnation_id), callback)
  end

  defp via(incarnation_id),
    do: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:dial_supervisor, incarnation_id}}}
end
