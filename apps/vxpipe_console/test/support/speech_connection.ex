defmodule Vxpipe.Console.Test.SpeechConnection do
  @moduledoc false
  use GenServer
  @behaviour Vxpipe.CallEngine.Media.ConnectionReadiness

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Media.Ingress
  alias Vxpipe.CallEngine.Readiness.Resource

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def attach(connection), do: GenServer.call(connection, :attach, 5_000)
  def attachment(connection), do: GenServer.call(connection, :attachment, 5_000)
  def readiness(connection), do: GenServer.call(connection, :readiness, 1_000)
  def send_text(connection, command), do: GenServer.call(connection, {:send_text, command}, 5_000)

  @impl true
  def prepare_binding(binding, _policy, demand) do
    if demand.speech_to_text? do
      with %{media_ingress: ingress} when is_pid(ingress) <- binding.attachment,
           :ok <- Ingress.prepare_track(ingress, binding.track),
           {:ok, resources} <- Ingress.readiness_resources(ingress) do
        {:ok, [binding.resource | resources], binding.track}
      else
        _unavailable -> {:error, :speech_unavailable}
      end
    else
      track = if demand.audio_input?, do: binding.track
      {:ok, [binding.resource], track}
    end
  end

  @impl true
  def init(options) do
    command = Keyword.fetch!(options, :command)

    identity =
      Map.take(command, [:tenant_id, :room_id, :incarnation_id, :participant_id, :connection_id])

    resource =
      Resource.new(
        :media_connection,
        {:participant, command.participant_id},
        __MODULE__,
        identity,
        binding: command.connection_id
      )

    {:ok,
     %{
       command: command,
       observer: Keyword.fetch!(options, :observer),
       audit_events?: Keyword.get(options, :audit_events?, false),
       binding: %{
         identity: identity,
         instance: self(),
         adapter: __MODULE__,
         resource: resource,
         generation: make_ref(),
         attachment: nil,
         output: Keyword.get(options, :output),
         track: %{
           track_id: "configured-speech",
           codec: :linear16,
           sample_rate: 16_000,
           channels: 1
         }
       }
     }}
  end

  @impl true
  def handle_call(:attach, _from, state) do
    case CallEngine.attach_connection(state.command, state.binding.output) do
      {:ok, attachment} ->
        {:reply, {:ok, attachment}, put_in(state.binding.attachment, attachment)}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:attachment, _from, state), do: {:reply, state.binding.attachment, state}

  def handle_call({:send_text, command}, _from, state),
    do: {:reply, CallEngine.send_text(command), state}

  def handle_call(:vxpipe_connection_readiness, _from, state),
    do: {:reply, {:ok, state.binding}, state}

  def handle_call(:readiness, _from, state),
    do: {:reply, {:ok, state.binding.resource, :ready}, state}

  @impl true
  def handle_info(
        {:vxpipe_startup_speech, monitor},
        %{binding: %{attachment: %{room_monitor: monitor}}} = state
      ) do
    command = %{state.command | deadline: DateTime.add(DateTime.utc_now(), 10, :second)}

    case CallEngine.activate_speech_to_text(command) do
      {:ok, ingress} -> {:noreply, put_in(state.binding.attachment.media_ingress, ingress)}
      _error -> {:stop, :speech_unavailable, state}
    end
  end

  def handle_info(
        {:vxpipe_call_ready, monitor},
        %{binding: %{attachment: %{room_monitor: monitor}}} = state
      ) do
    send(state.observer, {:configured_speech_ready, self()})
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, monitor, :process, _room, _reason},
        %{binding: %{attachment: %{room_monitor: monitor}}} = state
      ) do
    send(state.observer, {:configured_speech_closed, self()})
    {:noreply, state}
  end

  def handle_info({:vxpipe_event, event} = message, %{audit_events?: true} = state) do
    send(state.observer, {:configured_public_event, event})
    send(state.observer, message)
    {:noreply, state}
  end

  def handle_info(message, state) do
    send(state.observer, message)
    {:noreply, state}
  end
end
