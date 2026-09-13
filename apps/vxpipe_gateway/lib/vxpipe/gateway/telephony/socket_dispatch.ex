defmodule Vxpipe.Gateway.Telephony.SocketDispatch do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.Leg

  @maximum_pending 128
  @timeout 5_000
  @derive {Inspect, only: []}
  defstruct [:requests]

  def new, do: %__MODULE__{requests: :gen_server.reqids_new()}

  def submit(state, leg, %Event{} = event) do
    if :gen_server.reqids_size(state.requests) < @maximum_pending do
      ref = make_ref()
      timer = Process.send_after(self(), {:media_dispatch_timeout, ref}, @timeout)
      request = Leg.dispatch_async(leg, event)
      {:ok, %{state | requests: :gen_server.reqids_add(request, {ref, timer}, state.requests)}}
    else
      if event.kind == :media, do: {:ok, state}, else: {:error, :event_dispatch_saturated}
    end
  end

  def response(state, {:media_dispatch_timeout, ref}) do
    pending? =
      Enum.any?(:gen_server.reqids_to_list(state.requests), fn {_, {token, _}} -> token == ref end)

    if pending?, do: {:error, :event_dispatch_timeout}, else: {:ok, state}
  end

  def response(state, message) do
    case :gen_server.check_response(message, state.requests, true) do
      {{:reply, :ok}, {_, timer}, requests} ->
        Process.cancel_timer(timer)
        {:ok, %{state | requests: requests}}

      {_, {_, timer}, _requests} ->
        Process.cancel_timer(timer)
        {:error, :event_dispatch_failed}

      _ ->
        {:ok, state}
    end
  end
end
