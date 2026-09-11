defmodule Vxpipe.Gateway.Telephony.MediaAdmission do
  @moduledoc "Issues expiring, single-use media tokens bound to exact live telephony legs."

  use GenServer

  alias Vxpipe.Gateway.Telephony.MediaBinding

  @consume_timeout 30_000
  @token_bytes 32

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    {name, options} = Keyword.pop(options, :name, __MODULE__)

    if is_nil(name) do
      GenServer.start_link(__MODULE__, options)
    else
      GenServer.start_link(__MODULE__, options, name: name)
    end
  end

  @spec issue(MediaBinding.t(), pos_integer()) :: {:ok, String.t()} | {:error, atom()}
  def issue(%MediaBinding{} = binding, ttl_ms), do: issue(__MODULE__, binding, ttl_ms)

  @spec issue(GenServer.server(), MediaBinding.t(), pos_integer()) ::
          {:ok, String.t()} | {:error, atom()}
  def issue(server, %MediaBinding{} = binding, ttl_ms)
      when is_integer(ttl_ms) and ttl_ms > 0 do
    GenServer.call(server, {:issue, binding, ttl_ms})
  end

  def issue(_server, _binding, _ttl_ms), do: {:error, :invalid_media_binding}

  @spec reserve(GenServer.server(), String.t(), pid(), pos_integer()) ::
          {:ok, String.t()} | {:error, atom()}
  def reserve(server, ingress_key, leg, ttl_ms)
      when is_binary(ingress_key) and byte_size(ingress_key) > 0 and is_pid(leg) and
             is_integer(ttl_ms) and ttl_ms > 0 do
    GenServer.call(server, {:reserve, ingress_key, leg, ttl_ms})
  end

  def reserve(_server, _ingress_key, _leg, _ttl_ms),
    do: {:error, :invalid_media_reservation}

  @spec bind(GenServer.server(), MediaBinding.t()) :: :ok | {:error, atom()}
  def bind(server, %MediaBinding{} = binding), do: GenServer.call(server, {:bind, binding})

  @spec consume(String.t(), String.t()) ::
          {:ok, MediaBinding.t()} | {:error, :invalid_media_token}
  def consume(ingress_key, token), do: consume(__MODULE__, ingress_key, token)

  @spec consume(GenServer.server(), String.t(), String.t()) ::
          {:ok, MediaBinding.t()} | {:error, :invalid_media_token}
  def consume(server, ingress_key, token) when is_binary(ingress_key) and is_binary(token) do
    GenServer.call(server, {:consume, ingress_key, token}, @consume_timeout)
  end

  def consume(_server, _ingress_key, _token), do: {:error, :invalid_media_token}

  @spec revoke(pid()) :: :ok
  def revoke(leg) when is_pid(leg), do: revoke(__MODULE__, leg)

  @spec revoke(GenServer.server(), pid()) :: :ok
  def revoke(server, leg) when is_pid(leg), do: GenServer.call(server, {:revoke, leg})

  @impl true
  def init(options) do
    options = Keyword.validate!(options, clock: fn -> System.monotonic_time(:millisecond) end)

    {:ok,
     %{
       clock: Keyword.fetch!(options, :clock),
       entries: %{},
       monitors: %{},
       tokens_by_leg: %{}
     }}
  end

  @impl true
  def handle_call({:issue, binding, ttl_ms}, _from, state) do
    if MediaBinding.valid?(binding) do
      issue_binding(binding, ttl_ms, state)
    else
      {:reply, {:error, :invalid_media_binding}, state}
    end
  end

  def handle_call({:reserve, ingress_key, leg, ttl_ms}, _from, state) do
    reserve_leg(ingress_key, leg, ttl_ms, state)
  end

  def handle_call({:bind, binding}, _from, state) do
    bind_entry(binding, state)
  end

  def handle_call({:consume, ingress_key, token}, from, state) do
    case Map.fetch(state.entries, token) do
      {:ok, entry} -> consume_entry(ingress_key, token, entry, from, state)
      :error -> {:reply, {:error, :invalid_media_token}, state}
    end
  end

  def handle_call({:revoke, leg}, _from, state) do
    state =
      case Map.fetch(state.tokens_by_leg, leg) do
        {:ok, token} -> drop_entry(state, token)
        :error -> state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:expire, token}, state) do
    {:noreply, drop_entry(state, token)}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Map.fetch(state.monitors, monitor) do
      {:ok, token} -> {:noreply, drop_entry(state, token, demonitor?: false)}
      :error -> {:noreply, state}
    end
  end

  defp issue_binding(binding, ttl_ms, state) do
    now = state.clock.()

    case existing_entry(binding, now, state) do
      {:ok, token} ->
        {:reply, {:ok, token}, state}

      {:error, :leg_already_bound} ->
        {:reply, {:error, :leg_already_bound}, state}

      :new ->
        state = drop_expired_leg_entry(state, binding.leg, now)

        {token, state} =
          put_entry(state, binding.ingress_key, binding.leg, binding, ttl_ms, now)

        {:reply, {:ok, token}, state}
    end
  end

  defp existing_entry(binding, now, state) do
    with {:ok, token} <- Map.fetch(state.tokens_by_leg, binding.leg),
         {:ok, entry} <- Map.fetch(state.entries, token),
         true <- entry.expires_at > now do
      if entry.binding == binding, do: {:ok, token}, else: {:error, :leg_already_bound}
    else
      _missing_or_expired -> :new
    end
  end

  defp reserve_leg(ingress_key, leg, ttl_ms, state) do
    now = state.clock.()

    case existing_reservation(ingress_key, leg, now, state) do
      {:ok, token} ->
        {:reply, {:ok, token}, state}

      {:error, :leg_already_bound} ->
        {:reply, {:error, :leg_already_bound}, state}

      :new ->
        state = drop_expired_leg_entry(state, leg, now)
        {token, state} = put_entry(state, ingress_key, leg, nil, ttl_ms, now)
        {:reply, {:ok, token}, state}
    end
  end

  defp existing_reservation(ingress_key, leg, now, state) do
    with {:ok, token} <- Map.fetch(state.tokens_by_leg, leg),
         {:ok, entry} <- Map.fetch(state.entries, token),
         true <- entry.expires_at > now do
      if entry.ingress_key == ingress_key and is_nil(entry.binding),
        do: {:ok, token},
        else: {:error, :leg_already_bound}
    else
      _missing_or_expired -> :new
    end
  end

  defp put_entry(state, ingress_key, leg, binding, ttl_ms, now) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(@token_bytes), padding: false)
    monitor = Process.monitor(leg)
    timer = Process.send_after(self(), {:expire, token}, ttl_ms)

    entry = %{
      binding: binding,
      ingress_key: ingress_key,
      leg: leg,
      expires_at: now + ttl_ms,
      monitor: monitor,
      timer: timer,
      waiter: nil
    }

    state = %{
      state
      | entries: Map.put(state.entries, token, entry),
        monitors: Map.put(state.monitors, monitor, token),
        tokens_by_leg: Map.put(state.tokens_by_leg, leg, token)
    }

    {token, state}
  end

  defp bind_entry(binding, state) do
    cond do
      not MediaBinding.valid?(binding) ->
        {:reply, {:error, :invalid_media_binding}, state}

      true ->
        bind_valid_entry(binding, state)
    end
  end

  defp bind_valid_entry(binding, state) do
    with {:ok, token} <- Map.fetch(state.tokens_by_leg, binding.leg),
         {:ok, entry} <- Map.fetch(state.entries, token) do
      cond do
        entry.expires_at <= state.clock.() ->
          {:reply, {:error, :media_admission_not_found}, drop_entry(state, token)}

        entry.ingress_key != binding.ingress_key or entry.leg != binding.leg ->
          {:reply, {:error, :media_binding_mismatch}, state}

        true ->
          settle_binding(token, entry, binding, state)
      end
    else
      :error -> {:reply, {:error, :media_admission_not_found}, state}
    end
  end

  defp settle_binding(_token, %{binding: binding}, binding, state),
    do: {:reply, :ok, state}

  defp settle_binding(_token, %{binding: existing}, _binding, state)
       when not is_nil(existing),
       do: {:reply, {:error, :media_binding_mismatch}, state}

  defp settle_binding(token, %{waiter: nil} = entry, binding, state) do
    entry = %{entry | binding: binding}
    {:reply, :ok, %{state | entries: Map.put(state.entries, token, entry)}}
  end

  defp settle_binding(token, %{waiter: waiter}, binding, state) do
    GenServer.reply(waiter, {:ok, binding})
    {:reply, :ok, drop_entry(state, token, reply_waiter?: false)}
  end

  defp drop_expired_leg_entry(state, leg, now) do
    with {:ok, token} <- Map.fetch(state.tokens_by_leg, leg),
         {:ok, entry} <- Map.fetch(state.entries, token),
         true <- entry.expires_at <= now do
      drop_entry(state, token)
    else
      _not_expired -> state
    end
  end

  defp consume_entry(ingress_key, token, entry, from, state) do
    cond do
      entry.expires_at <= state.clock.() ->
        {:reply, {:error, :invalid_media_token}, drop_entry(state, token)}

      entry.ingress_key != ingress_key ->
        {:reply, {:error, :invalid_media_token}, state}

      is_nil(entry.binding) and is_nil(entry.waiter) ->
        entry = %{entry | waiter: from}
        {:noreply, %{state | entries: Map.put(state.entries, token, entry)}}

      is_nil(entry.binding) ->
        {:reply, {:error, :invalid_media_token}, state}

      true ->
        {:reply, {:ok, entry.binding}, drop_entry(state, token)}
    end
  end

  defp drop_entry(state, token, options \\ []) do
    case Map.pop(state.entries, token) do
      {nil, _entries} ->
        state

      {entry, entries} ->
        _ = Process.cancel_timer(entry.timer)

        if entry.waiter != nil and Keyword.get(options, :reply_waiter?, true) do
          GenServer.reply(entry.waiter, {:error, :invalid_media_token})
        end

        if Keyword.get(options, :demonitor?, true) do
          Process.demonitor(entry.monitor, [:flush])
        end

        %{
          state
          | entries: entries,
            monitors: Map.delete(state.monitors, entry.monitor),
            tokens_by_leg: Map.delete(state.tokens_by_leg, entry.leg)
        }
    end
  end
end
