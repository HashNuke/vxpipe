defmodule Vxpipe.CallEngine.SpeechTopologyInput do
  @moduledoc false
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: options[:name])

  def submit(input, command), do: GenServer.cast(input, {:command, command})

  @impl true
  def init(options) do
    {:ok,
     %{
       consumer: Keyword.fetch!(options, :consumer),
       channel: Keyword.fetch!(options, :channel),
       provider: Keyword.fetch!(options, :provider)
     }}
  end

  @impl true
  def handle_cast({:command, %{kind: :speak} = command}, state) do
    result =
      provider_call(state.provider, {:speak, command.request, command.text}, command.deadline)

    if command.hold_result? do
      hold = make_ref()
      send(state.consumer, {:topology_input_held, self(), hold})

      receive do
        {:release_topology_input, ^hold} -> :ok
      after
        remaining(command.deadline) -> exit(:input_hold_timeout)
      end
    end

    result = if remaining(command.deadline) > 0, do: result, else: {:error, :command_timeout}
    GenServer.cast(state.channel, {:input_result, self(), command, result})
    {:noreply, state}
  end

  def handle_cast({:command, %{kind: :cancel} = command}, state) do
    result =
      provider_call(
        state.provider,
        {:cancel, command.request, command.played_ms},
        command.deadline
      )

    GenServer.cast(state.channel, {:input_result, self(), command, result})
    {:noreply, state}
  end

  defp provider_call(provider, message, deadline) do
    GenServer.call(provider, message, remaining(deadline))
  catch
    :exit, {:timeout, _call} -> {:error, :command_timeout}
    :exit, _reason -> {:error, :session_failed}
  end

  defp remaining(deadline),
    do: max(deadline - System.monotonic_time(:millisecond), 0)
end
