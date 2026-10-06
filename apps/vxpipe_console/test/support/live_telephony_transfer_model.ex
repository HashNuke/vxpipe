defmodule Vxpipe.Console.Test.LiveTelephonyTransferModel do
  @moduledoc false
  @behaviour Vxpipe.AgentRuntime.ModelProvider

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}

  @roles %{
    "test:telephony-caller" => :caller,
    "test:telephony-reception" => :reception,
    "test:telephony-destination" => :destination
  }

  def new(options) do
    with {:ok, options} <- Keyword.validate(options, [:model, :once, :destination_gate]),
         {:ok, role} <- Map.fetch(@roles, Keyword.get(options, :model)),
         once when is_pid(once) <- Keyword.get(options, :once),
         gate when is_nil(gate) or is_pid(gate) <- Keyword.get(options, :destination_gate) do
      {:ok, %{role: role, once: once, destination_gate: gate}}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def readiness(%{role: role, once: once})
      when role in [:caller, :reception, :destination] and is_pid(once),
      do: :ready

  @impl true
  def streaming?(_model), do: true

  @impl true
  def generate(model, request), do: stream(model, request, fn _text -> :ok end)

  @impl true
  def stream(%{role: :reception, once: once}, _request, emit) do
    first? = Agent.get_and_update(once, fn requested? -> {not requested?, true} end)

    if first? do
      {:ok, tool} =
        ToolCall.new(
          id: "live-private-transfer",
          name: "transfer",
          arguments: %{"destination" => "support", "reason" => "Delta."}
        )

      ModelResponse.new(text: "", tool_calls: [tool])
    else
      reply("Charlie.", emit)
    end
  end

  def stream(%{role: :caller}, _request, emit), do: reply("Alpha.", emit)

  def stream(%{role: :destination, destination_gate: gate}, _request, emit) when is_pid(gate) do
    with :ok <- await_destination(gate), do: reply("Bravo.", emit)
  end

  def stream(%{role: :destination}, _request, emit), do: reply("Bravo.", emit)

  def open_destination(gate) do
    waiting = Agent.get_and_update(gate, &{&1.waiting, %{&1 | open?: true, waiting: []}})
    Enum.each(waiting, fn {pid, reference} -> send(pid, {:live_destination_speak, reference}) end)
    :ok
  end

  defp await_destination(gate) do
    waiter = {self(), make_ref()}
    {_pid, reference} = waiter

    open? =
      Agent.get_and_update(gate, fn state ->
        if state.open? do
          {true, state}
        else
          send(state.observer, {:live_destination_waiting, reference})
          {false, %{state | waiting: [waiter | state.waiting]}}
        end
      end)

    if open? do
      :ok
    else
      receive do
        {:live_destination_speak, ^reference} -> :ok
      after
        20_000 -> {:error, :provider_unavailable}
      end
    end
  end

  defp reply(text, emit) do
    with :ok <- emit.(text), do: ModelResponse.new(text: text)
  end
end
