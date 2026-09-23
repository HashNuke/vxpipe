defmodule Vxpipe.Gateway.WebRTC.SourceReceiver do
  @moduledoc false

  use GenServer

  alias ExRTP.Packet
  alias ExWebRTC.PeerConnection

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :epoch)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def bind_peer(receiver, peer, timeout)
      when is_pid(receiver) and is_pid(peer) and is_integer(timeout) and timeout > 0 do
    deadline = System.monotonic_time(:millisecond) + timeout
    GenServer.call(receiver, {:bind_peer, peer, deadline}, timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def bind_peer(_receiver, _peer, _timeout), do: {:error, :invalid_peer}

  def cutover(receiver, old_epoch, fresh_epoch, timeout)
      when is_pid(receiver) and is_reference(old_epoch) and is_reference(fresh_epoch) and
             old_epoch != fresh_epoch and is_integer(timeout) and timeout > 0 do
    deadline = System.monotonic_time(:millisecond) + timeout
    GenServer.call(receiver, {:cutover, old_epoch, fresh_epoch, deadline}, timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def cutover(_receiver, _old_epoch, _fresh_epoch, _timeout), do: {:error, :invalid_epoch}

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    epoch = Keyword.fetch!(options, :epoch)
    clock = Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end)

    if is_pid(owner) and is_reference(epoch) and is_function(clock, 0) do
      {:ok,
       %{
         owner: owner,
         monitor: Process.monitor(owner),
         epoch: epoch,
         clock: clock,
         peer: nil,
         pending: nil
       }}
    else
      {:stop, :invalid_source_receiver}
    end
  end

  @impl true
  def handle_call({:bind_peer, peer, deadline}, _from, %{peer: nil} = state) do
    if before_deadline?(deadline),
      do: {:reply, :ok, %{state | peer: peer}},
      else: {:reply, {:error, :deadline_elapsed}, state}
  end

  def handle_call({:bind_peer, peer, _deadline}, _from, %{peer: peer} = state),
    do: {:reply, :ok, state}

  def handle_call({:bind_peer, _peer, _deadline}, _from, state),
    do: {:reply, {:error, :peer_mismatch}, state}

  def handle_call({:cutover, _old, _new, _deadline}, _from, %{peer: nil} = state),
    do: {:reply, {:error, :unbound_peer}, state}

  def handle_call({:cutover, _old, _new, _deadline}, _from, %{pending: pending} = state)
      when not is_nil(pending),
      do: {:reply, {:error, :busy}, state}

  def handle_call({:cutover, old_epoch, fresh_epoch, deadline}, from, %{epoch: old_epoch} = state) do
    if before_deadline?(deadline) do
      case peer_barrier(state.peer) do
        :ok ->
          token = make_ref()
          send(self(), {:commit_source_epoch, token})

          pending = %{
            token: token,
            from: from,
            old_epoch: old_epoch,
            fresh_epoch: fresh_epoch,
            deadline: deadline
          }

          {:noreply, %{state | pending: pending}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :deadline_elapsed}, state}
    end
  end

  def handle_call({:cutover, _old, _new, _deadline}, _from, state),
    do: {:reply, {:error, :stale_epoch}, state}

  defp peer_barrier(peer) do
    PeerConnection.controlling_process(peer, self())
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp before_deadline?(deadline),
    do: System.monotonic_time(:millisecond) < deadline

  @impl true
  def handle_info({:commit_source_epoch, token}, %{pending: %{token: token} = pending} = state) do
    if before_deadline?(pending.deadline) and state.epoch == pending.old_epoch do
      GenServer.reply(pending.from, :ok)
      {:noreply, %{state | epoch: pending.fresh_epoch, pending: nil}}
    else
      GenServer.reply(pending.from, {:error, :deadline_elapsed})
      {:noreply, %{state | pending: nil}}
    end
  end

  def handle_info({:commit_source_epoch, _token}, state), do: {:noreply, state}

  def handle_info({:ex_webrtc, _peer, {:rtp, _track, _rid, %Packet{}}} = message, state) do
    send(state.owner, {:vxpipe_webrtc_source, self(), state.epoch, state.clock.(), message})
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, _peer, _event} = message, state) do
    send(state.owner, message)
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, monitor, :process, owner, _reason},
        %{monitor: monitor, owner: owner} = state
      ),
      do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}
end
