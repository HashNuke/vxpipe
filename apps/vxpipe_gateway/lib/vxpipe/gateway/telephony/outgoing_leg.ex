defmodule Vxpipe.Gateway.Telephony.OutgoingLeg do
  @moduledoc false

  use GenServer

  alias Vxpipe.Gateway.Telephony.OutgoingLegDialer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    leg_id = Keyword.fetch!(options, :leg_id)
    GenServer.start_link(__MODULE__, options, name: via(leg_id))
  end

  def child_spec(options) do
    leg_id = Keyword.fetch!(options, :leg_id)

    %{
      id: {__MODULE__, leg_id},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec await(pid(), timeout()) :: :ok | {:error, term()}
  def await(leg, timeout) when is_pid(leg) do
    GenServer.call(leg, :await, timeout)
  catch
    :exit, _reason -> {:error, :telephony_leg_unavailable}
  end

  @impl true
  def init(options) do
    {:ok,
     %{
       leg_id: Keyword.fetch!(options, :leg_id),
       request: Keyword.fetch!(options, :request),
       service: Keyword.fetch!(options, :service),
       media_admission: Keyword.fetch!(options, :media_admission),
       result: nil,
       status: :starting,
       waiters: []
     }, {:continue, :dial}}
  end

  @impl true
  def handle_continue(:dial, state) do
    case OutgoingLegDialer.dial(
           state.leg_id,
           state.request,
           state.service,
           state.media_admission,
           self()
         ) do
      {:ok, status} ->
        reply_waiters(state.waiters, :ok)
        {:noreply, %{state | result: :ok, status: status, waiters: []}}

      {:error, reason} ->
        result = {:error, reason}
        reply_waiters(state.waiters, result)
        Process.send_after(self(), :retire, 1_000)
        {:noreply, %{state | result: result, status: :failed, waiters: []}}
    end
  end

  @impl true
  def handle_call(:await, _from, %{result: result} = state) when not is_nil(result) do
    {:reply, result, state}
  end

  def handle_call(:await, from, state) do
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  @impl true
  def handle_info(:retire, %{status: :failed} = state), do: {:stop, :normal, state}
  def handle_info(:retire, state), do: {:noreply, state}

  defp reply_waiters(waiters, result), do: Enum.each(waiters, &GenServer.reply(&1, result))

  defp via(leg_id) do
    {:via, Registry, {Vxpipe.Gateway.Telephony.LegRegistry, {:outgoing, leg_id}}}
  end
end
