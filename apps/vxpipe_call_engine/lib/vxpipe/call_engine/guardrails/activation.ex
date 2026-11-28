defmodule Vxpipe.CallEngine.Guardrails.Activation do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.RoomCapabilitySupervisor

  def start_link(options) do
    GenServer.start_link(__MODULE__, Keyword.delete(options, :name),
      name: Keyword.fetch!(options, :name)
    )
  end

  @impl true
  def init(options), do: {:ok, nil, {:continue, {:start_checks, options}}}

  @impl true
  def handle_continue({:start_checks, options}, nil) do
    # Native activation trees themselves start under the room's capability
    # supervisor. Wait until init returns before asking it to start a sibling.
    case RoomCapabilitySupervisor.start_guardrail_checks(options, self()) do
      {:ok, checks} -> {:noreply, {checks, Process.monitor(checks)}}
      {:error, reason} -> {:stop, reason, nil}
    end
  end

  @impl true
  def handle_call(request, from, {checks, _monitor} = state) do
    GenServer.cast(checks, {:from_activation, from, request})
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, checks, :shutdown}, {checks, monitor} = state),
    do: {:stop, :shutdown, state}

  def handle_info({:DOWN, monitor, :process, checks, reason}, {checks, monitor} = state),
    do: {:stop, {:guardrails_unavailable, reason}, state}

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {key, _value} when key in [:state, :message, :reason, :log] -> {key, :redacted}
      entry -> entry
    end)
  end
end
