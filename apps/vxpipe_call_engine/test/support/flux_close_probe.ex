defmodule Vxpipe.CallEngine.TestFluxCloseProbe do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.Socket

  alias Vxpipe.CallEngine.Speech.{PrivateInit, Socket}
  alias Vxpipe.CallEngine.TestFluxCloseProbe.Evidence
  alias Vxpipe.Providers.Deepgram.Flux

  @maximum_audio_bytes 320_000
  @chunk_bytes 2_560
  @maximum_events 256

  # The gate is deliberately outside the exception/configuration/connector path.
  def run(options, hooks) do
    if Keyword.get(options, :enabled) === true do
      run_armed(options, hooks)
    else
      unavailable(:not_armed)
    end
  end

  def callback_state(owner, reference) do
    %{owner: owner, reference: reference, finish_gate: :atomics.new(1, []), events: 0}
  end

  def start_socket(options, callback, starter) do
    with {:ok, private} <- PrivateInit.open([options: options, callback: callback], 5_000) do
      try do
        starter.(%{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [private]},
          restart: :temporary,
          shutdown: 5_000
        })
      after
        PrivateInit.close(private)
      end
    end
  end

  def start_link(private) do
    with {:ok, [options: options, callback: callback]} <- PrivateInit.claim(private) do
      Socket.start_link(options, __MODULE__, callback)
    end
  end

  @impl true
  def handle_frame({:text, payload}, state) when state.events < @maximum_events do
    event =
      case Flux.decode(payload) do
        {:ok, signal} -> {:signal, signal}
        _invalid_or_unknown -> :invalid_wire
      end

    notify(state, event)
  end

  def handle_frame(_frame, state), do: notify(state, :invalid_wire)

  @impl true
  def handle_disconnect(_reason, state), do: notify(state, :connection_lost)

  @impl true
  def handle_peer_close(status, state) do
    notify(state, {:peer_close, status, :atomics.get(state.finish_gate, 1) == 1})
  end

  defp notify(%{events: @maximum_events} = state, _event) do
    send(state.owner, {:flux_close_probe, state.reference, self(), :limit})
    {:ok, %{state | events: state.events + 1}}
  end

  defp notify(%{events: events} = state, _event) when events > @maximum_events, do: {:ok, state}

  defp notify(state, event) do
    send(state.owner, {:flux_close_probe, state.reference, self(), event})
    {:ok, %{state | events: state.events + 1}}
  end

  defp run_armed(options, hooks) do
    with {:ok, pcm, tail, timeout} <- input(options),
         now = Map.get(hooks, :now, fn -> System.monotonic_time(:millisecond) end),
         evidence = Evidence.new(tail, now.() + timeout),
         {:ok, config} <-
           Flux.new(
             api_key: hooks.credential.(),
             model: "flux-general-en",
             encoding: :linear16,
             sample_rate: 16_000
           ) do
      connect(pcm, config, evidence, now, hooks)
    else
      {:error, :invalid_input} -> unavailable(:invalid_input)
      _unavailable -> unavailable(:unavailable)
    end
  rescue
    _exception -> unavailable(:unavailable)
  catch
    :exit, _reason -> unavailable(:unavailable)
  end

  defp connect(pcm, config, evidence, now, hooks) do
    remaining = evidence.deadline - now.()

    if remaining <= 0 do
      evidence |> Evidence.fail(:timeout) |> Evidence.report()
    else
      callback = callback_state(self(), make_ref())
      timeout = min(remaining, 5_000)

      options = [
        connection: Flux.connection_options(config),
        connect_mode: :deferred,
        transport_options: [connect_timeout: timeout, receive_timeout: timeout]
      ]

      case hooks.connect.(options, callback) do
        {:ok, socket} -> collect(socket, callback, pcm, evidence, now, hooks)
        _unavailable -> Evidence.report(Evidence.fail(evidence, :unavailable))
      end
    end
  end

  defp collect(socket, callback, pcm, evidence, now, hooks) do
    monitor = Process.monitor(socket)
    context = %{socket: socket, monitor: monitor, callback: callback, now: now, hooks: hooks}

    try do
      evidence = wait_connected(evidence, context)
      evidence = send_input(evidence, pcm, context)
      evidence = wait_terminal(evidence, context)
      Evidence.report(evidence)
    after
      Process.demonitor(monitor, [:flush])
      hooks.stop.(socket)
      discard(callback.reference, socket)
    end
  end

  defp wait_connected(%{terminal: terminal} = evidence, _) when terminal != nil, do: evidence
  defp wait_connected(%{connected?: true} = evidence, _), do: evidence
  defp wait_connected(evidence, context), do: wait_connected(next(evidence, context), context)

  defp wait_terminal(%{terminal: terminal} = evidence, _) when terminal != nil, do: evidence
  defp wait_terminal(evidence, context), do: wait_terminal(next(evidence, context), context)

  defp next(evidence, context) do
    remaining = evidence.deadline - context.now.()
    reference = context.callback.reference
    socket = context.socket
    monitor = context.monitor

    if remaining <= 0 do
      Evidence.fail(evidence, :timeout)
    else
      receive do
        {:flux_close_probe, ^reference, ^socket, event} ->
          Evidence.accept(evidence, event, context.now.())

        {:DOWN, ^monitor, :process, ^socket, _reason} ->
          Evidence.fail(evidence, :local_teardown)
      after
        remaining -> Evidence.fail(evidence, :timeout)
      end
    end
  end

  defp send_input(%{terminal: terminal} = evidence, _, _) when terminal != nil, do: evidence

  defp send_input(evidence, <<>>, context) do
    evidence = %{evidence | audio_sent?: true}
    :atomics.put(context.callback.finish_gate, 1, 1)
    result = send_frame(evidence, {:text, ~s({"type":"CloseStream"})}, context)
    if result.terminal == nil, do: %{result | close_stream_sent?: true}, else: result
  end

  defp send_input(evidence, pcm, context) do
    size = min(byte_size(pcm), @chunk_bytes)
    <<chunk::binary-size(size), rest::binary>> = pcm
    evidence |> send_frame({:binary, chunk}, context) |> send_input(rest, context)
  end

  defp send_frame(evidence, frame, context) do
    if context.now.() >= evidence.deadline do
      Evidence.fail(evidence, :timeout)
    else
      send = Map.get(context.hooks, :send, &Socket.send_frame/2)

      case send.(context.socket, frame) do
        :ok -> evidence
        _failure -> Evidence.fail(evidence, :send_failed)
      end
    end
  end

  defp input(options) do
    tail = Keyword.get(options, :expected_tail)
    timeout = Keyword.get(options, :timeout_ms, 30_000)
    path = Keyword.get(options, :fixture_path)

    with true <- is_binary(tail) and byte_size(tail) in 1..256 and String.valid?(tail),
         true <- is_integer(timeout) and timeout in 1..30_000,
         true <- is_binary(path),
         {:ok, %{type: :regular, size: size}} <- File.stat(path),
         true <- size in 2..@maximum_audio_bytes and rem(size, 2) == 0,
         {:ok, pcm} <-
           File.open(path, [:read, :binary], &IO.binread(&1, @maximum_audio_bytes + 1)),
         true <-
           is_binary(pcm) and byte_size(pcm) in 2..@maximum_audio_bytes and
             rem(byte_size(pcm), 2) == 0 do
      {:ok, pcm, tail, timeout}
    else
      _invalid -> {:error, :invalid_input}
    end
  end

  defp unavailable(terminal), do: Evidence.report(Evidence.fail(Evidence.new(nil, 0), terminal))

  defp discard(reference, socket) do
    receive do
      {:flux_close_probe, ^reference, ^socket, _event} -> discard(reference, socket)
      {:vxpipe_socket_connected, ^socket} -> discard(reference, socket)
    after
      0 -> :ok
    end
  end
end
