defmodule Vxpipe.CallEngine.Diagnostics.AttachmentRunner do
  @moduledoc "One room-owned attachment IO slot; the service retains it until work resolves."
  use GenServer
  alias Vxpipe.CallEngine.Diagnostics.SourceAttachment

  def child_spec(options),
    do: %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      restart: :permanent,
      shutdown: :brutal_kill,
      type: :worker
    }

  def start_link(options),
    do: GenServer.start_link(__MODULE__, :idle, name: Keyword.fetch!(options, :name))

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_info({:attach, owner, reference, candidate, packet, options}, state) do
    result = SourceAttachment.start_input(candidate, packet, options)
    send(owner, {:attachment_result, reference, result})
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def format_status(status),
    do: %{status | state: :redacted, message: :redacted, reason: :redacted, log: []}
end
