defmodule Vxpipe.CallEngine.Capability.DeterministicText do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Command.SendText

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :participant_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def respond(capability, %SendText{} = command) do
    GenServer.cast(capability, {:respond, command})
  end

  @impl true
  def init(options) do
    {:ok, %{room_authority: Keyword.fetch!(options, :room_authority)}}
  end

  @impl true
  def handle_cast({:respond, command}, state) do
    send(
      state.room_authority,
      {:vxpipe_capability_text, self(), command, "Echo: #{command.content}"}
    )

    {:noreply, state}
  end
end
