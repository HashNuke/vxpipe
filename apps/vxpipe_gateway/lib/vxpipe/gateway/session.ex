defmodule Vxpipe.Gateway.Session do
  @moduledoc false

  use GenServer

  alias Vxpipe.Gateway.Session.Snapshot

  @claim_timeout 5_000

  def start_link(options) do
    session_id = Keyword.fetch!(options, :session_id)
    GenServer.start_link(__MODULE__, options, name: via(session_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :session_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def claim(session_id) do
    case Registry.lookup(Vxpipe.Gateway.SessionRegistry, session_id) do
      [{session, _value}] -> GenServer.call(session, :claim, @claim_timeout)
      [] -> {:error, :not_found}
    end
  end

  def snapshot(session) do
    GenServer.call(session, :snapshot, @claim_timeout)
  end

  @impl true
  def init(options) do
    ttl_ms = Keyword.fetch!(options, :ttl_ms)
    now = DateTime.utc_now(:millisecond)
    expires_at = DateTime.add(now, ttl_ms, :millisecond)
    expires_after = System.monotonic_time(:millisecond) + ttl_ms
    _timer = Process.send_after(self(), :expire, ttl_ms)

    snapshot = %Snapshot{
      session_id: Keyword.fetch!(options, :session_id),
      tenant_id: Keyword.fetch!(options, :tenant_id),
      actor_id: Keyword.fetch!(options, :actor_id),
      room_id: Keyword.fetch!(options, :room_id),
      incarnation_id: Keyword.fetch!(options, :incarnation_id),
      participant_id: Keyword.fetch!(options, :participant_id),
      tool_visibility: Keyword.fetch!(options, :tool_visibility),
      expires_at: expires_at
    }

    {:ok, %{expires_after: expires_after, snapshot: snapshot, state: :pending}}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call(:claim, _from, state) do
    cond do
      state.state == :claimed ->
        {:reply, {:error, :already_claimed}, state}

      System.monotonic_time(:millisecond) >= state.expires_after ->
        {:stop, :normal, {:error, :expired}, state}

      true ->
        {:reply, {:ok, state.snapshot}, %{state | state: :claimed}}
    end
  end

  @impl true
  def handle_info(:expire, state), do: {:stop, :normal, state}

  defp via(session_id) do
    {:via, Registry, {Vxpipe.Gateway.SessionRegistry, session_id}}
  end
end
