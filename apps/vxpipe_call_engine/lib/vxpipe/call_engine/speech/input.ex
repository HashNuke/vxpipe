defmodule Vxpipe.CallEngine.Speech.Input do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.{Allocation, CapabilityTree, Channel}

  def start_link(allocation),
    do: GenServer.start_link(__MODULE__, allocation, name: address(allocation))

  def address(allocation), do: CapabilityTree.address({allocation.generation, :input})

  def submit(allocation, command, audio),
    do: GenServer.cast(address(allocation), {:input, command, audio})

  @impl true
  def init(allocation), do: {:ok, allocation}

  @impl true
  def handle_cast({:input, command, audio}, allocation) do
    result = execute(allocation, command, audio)
    GenServer.cast(Channel.address(allocation), {:input_result, command.ref, self(), result})
    {:noreply, allocation}
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :speech_input)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp execute(allocation, command, audio) do
    remaining = command.deadline - System.monotonic_time(:millisecond)

    with true <- remaining > 0 and Allocation.valid?(allocation),
         {:ok, module, provider} <-
           GenServer.call(Channel.address(allocation), {:claim_input, command.ref}, remaining) do
      if command.deadline > System.monotonic_time(:millisecond) and Allocation.valid?(allocation),
        do: accepted(module.push_audio(provider, audio)),
        else: {:error, :session_failed}
    else
      _failure -> {:error, :session_failed}
    end
  rescue
    _error -> {:error, :session_failed}
  catch
    _kind, _reason -> {:error, :session_failed}
  end

  defp accepted(:ok), do: :ok
  defp accepted({:error, :busy}), do: {:error, :busy}
  defp accepted(_failure), do: {:error, :session_failed}
end
