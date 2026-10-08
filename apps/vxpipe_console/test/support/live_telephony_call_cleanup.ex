defmodule Vxpipe.Console.Test.LiveTelephonyCallCleanup do
  @moduledoc "Captures this live test's carrier handles for independent ExUnit teardown."
  use GenServer

  alias Vxpipe.CallEngine.Telephony.{Adapter, Answer, Event, Submission}
  alias Vxpipe.Gateway.TestLiveCallCleanup

  @derive {Inspect, only: [:current]}
  defstruct current: nil, scopes: %{}

  def start_link(options), do: GenServer.start_link(__MODULE__, %__MODULE__{}, options)
  def open(server \\ __MODULE__, numbers \\ []), do: GenServer.call(server, {:open, numbers})
  def current(server \\ __MODULE__), do: GenServer.call(server, :current)

  def command(provider, operation, options, request, server \\ __MODULE__)
      when operation in [:dial, :answer] do
    scope = current(server)

    if operation == :answer do
      %Answer{leg: leg} = request
      :ok = record(scope, provider, options, leg.provider_call_control_id, server)
    end

    result = apply(Adapter, operation, [adapter(provider), options, request])

    case result do
      {:ok, %Submission{provider_call_control_id: handle}} when is_binary(handle) ->
        :ok = record(scope, provider, options, handle, server)

      _no_handle ->
        :ok
    end

    result
  end

  def observe(scope, provider, options, {:ok, %Event{} = event}, server \\ __MODULE__) do
    if event.kind in [:incoming, :outgoing] do
      register(
        server,
        scope,
        provider,
        options,
        event.provider_call_control_id,
        {event.from, event.to}
      )
    else
      :ok
    end
  end

  def record(scope, provider, options, handle, server \\ __MODULE__),
    do: register(server, scope, provider, options, handle, :submitted)

  def close(scope, server \\ __MODULE__) do
    failures =
      server
      |> GenServer.call({:close, scope})
      |> Enum.sort_by(fn {{provider, handle}, _options} -> {provider, handle} end)
      |> Enum.flat_map(fn {{provider, handle}, options} ->
        case TestLiveCallCleanup.hangup(provider, options, handle) do
          :ok -> []
          {:error, reason} -> [reason]
        end
      end)

    if failures == [], do: :ok, else: {:error, failures}
  end

  def adapter(:telnyx), do: Vxpipe.Providers.Telnyx.Adapter
  def adapter(:twilio), do: Vxpipe.Providers.Twilio.Adapter

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def format_status(status),
    do: Map.merge(status, %{state: :live_telephony_call_cleanup, message: :redacted})

  @impl true
  def handle_call({:open, numbers}, _from, state) do
    scope = make_ref()
    entry = %{closed?: false, numbers: numbers, handles: %{}}
    {:reply, scope, %{state | current: scope, scopes: Map.put(state.scopes, scope, entry)}}
  end

  def handle_call(:current, _from, state), do: {:reply, state.current, state}

  def handle_call({:record, scope, provider, options, handle, source}, _from, state) do
    entry = Map.fetch!(state.scopes, scope)

    cond do
      not relevant?(entry.numbers, source) ->
        {:reply, :ok, state}

      entry.closed? ->
        {:reply, :closed, state}

      true ->
        entry = %{entry | handles: Map.put(entry.handles, {provider, handle}, options)}
        {:reply, :ok, %{state | scopes: Map.put(state.scopes, scope, entry)}}
    end
  end

  def handle_call({:close, scope}, _from, state) do
    entry = Map.fetch!(state.scopes, scope)
    closed = %{entry | closed?: true, handles: %{}}
    {:reply, entry.handles, %{state | scopes: Map.put(state.scopes, scope, closed)}}
  end

  defp register(server, scope, provider, options, handle, source) do
    case GenServer.call(server, {:record, scope, provider, options, handle, source}) do
      :ok -> :ok
      :closed -> TestLiveCallCleanup.hangup(provider, options, handle)
    end
  end

  defp relevant?(_numbers, :submitted), do: true
  defp relevant?(numbers, {from, to}), do: from in numbers or to in numbers
end
