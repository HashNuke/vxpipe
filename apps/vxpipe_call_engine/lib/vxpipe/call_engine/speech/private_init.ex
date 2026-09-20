defmodule Vxpipe.CallEngine.Speech.PrivateInit do
  @moduledoc false

  use GenServer

  @enforce_keys [:pid, :token]
  @derive {Inspect, only: [:pid]}
  defstruct @enforce_keys

  def open(private, expires_in)
      when is_list(private) and is_integer(expires_in) and expires_in > 0 do
    token = make_ref()
    owner = self()

    case GenServer.start(__MODULE__, {owner, token, private, expires_in}) do
      {:ok, pid} -> {:ok, %__MODULE__{pid: pid, token: token}}
      {:error, _reason} = error -> error
    end
  end

  def claim(%__MODULE__{pid: pid, token: token}) do
    GenServer.call(pid, {:claim, token}, 5_000)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def close(%__MODULE__{pid: pid, token: token}) do
    GenServer.cast(pid, {:close, token})
    :ok
  catch
    :exit, _reason -> :ok
  end

  @impl true
  def init({owner, token, private, expires_in}) do
    timer = Process.send_after(self(), :expire, expires_in)
    {:ok, %{owner: Process.monitor(owner), token: token, private: private, timer: timer}}
  end

  @impl true
  def handle_call({:claim, token}, _from, %{token: token, private: private} = state) do
    Process.cancel_timer(state.timer)
    {:stop, :normal, {:ok, private}, %{state | private: nil}}
  end

  def handle_call({:claim, _token}, _from, state),
    do: {:reply, {:error, :unavailable}, state}

  @impl true
  def handle_cast({:close, token}, %{token: token} = state),
    do: {:stop, :normal, %{state | private: nil}}

  def handle_cast({:close, _token}, state), do: {:noreply, state}

  @impl true
  def handle_info(:expire, state), do: {:stop, :normal, %{state | private: nil}}

  def handle_info({:DOWN, monitor, :process, _owner, _reason}, %{owner: monitor} = state),
    do: {:stop, :normal, %{state | private: nil}}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :private_init)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end
end
