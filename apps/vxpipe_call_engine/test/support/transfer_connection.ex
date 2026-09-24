defmodule Vxpipe.CallEngine.TestTransferConnection do
  @moduledoc "A supervised embedded connection for engine handoff tests; native media is covered by Gateway."
  use GenServer

  @behaviour Vxpipe.CallEngine.Media.ConnectionReadiness

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Media.{Ingress, OutputSink, STSIngress}
  alias Vxpipe.CallEngine.Readiness.Resource

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: name(Keyword.fetch!(options, :command)))
  end

  def attach(command, output, options \\ []) do
    connection =
      ExUnit.Callbacks.start_supervised!(
        {__MODULE__,
         [command: command, output: output, observer: self()] ++
           Keyword.take(options, [:input_track, :source_control?])},
        id: {__MODULE__, command.connection_id}
      )

    GenServer.call(connection, :attach)
  end

  def run(command, callback), do: GenServer.call(name(command), {:run, callback})

  def complete_source_hold(connection, result),
    do: GenServer.call(connection, {:complete_source_hold, result})

  def complete_source_arm(connection, result),
    do: GenServer.call(connection, {:complete_source_arm, result})

  def attachment(command), do: GenServer.call(name(command), :attachment)

  def control(command),
    do: run(command, fn -> CallEngine.participant_transfer_control(command) end)

  def readiness(connection), do: GenServer.call(connection, :readiness)

  def send_text(command) do
    if GenServer.whereis(name(command)),
      do: run(command, fn -> CallEngine.send_text(command) end),
      else: CallEngine.send_text(command)
  end

  def hold(binding, scope), do: OutputSink.hold(binding.output, scope.generation)
  def recover(binding, scope), do: hold(binding, scope)
  def release(binding, scope, _demand), do: OutputSink.release(binding.output, scope.generation)
  def adopt(binding, _scope), do: GenServer.call(binding.instance, :adopt)

  @impl true
  def prepare_binding(binding, _policy, demand) do
    await_output_preparation(binding, demand)

    track =
      if demand.audio_input? or demand.speech_to_text? or
           Map.get(demand, :speech_to_speech?, false),
         do: Map.get(binding, :input_track, input_track())

    with {:ok, speech} <- prepare_speech(binding, track, demand.speech_to_text?),
         {:ok, sts} <- prepare_sts(binding, track, Map.get(demand, :speech_to_speech?, false)) do
      {:ok, [binding.resource | speech ++ sts], track}
    end
  end

  defp prepare_sts(_binding, _track, false), do: {:ok, []}

  defp prepare_sts(binding, track, true) do
    with {:ok, %{ingress: ingress}} <-
           CallEngine.speech_to_speech_input_configuration(binding.attachment),
         :ok <- STSIngress.prepare_track(ingress, track),
         {:ok, resource, :ready} <- STSIngress.readiness(ingress),
         do: {:ok, [resource]}
  end

  defp prepare_speech(_binding, _track, false), do: {:ok, []}

  defp prepare_speech(%{attachment: %{media_ingress: ingress}}, track, true)
       when is_pid(ingress) do
    with :ok <- Ingress.prepare_track(ingress, track),
         do: Ingress.readiness_resources(ingress)
  end

  defp prepare_speech(_binding, _track, true), do: {:ok, []}

  defp await_output_preparation(
         %{output_preparation_observer: observer},
         %{audio_input?: false, room_output?: false, speech_to_text?: false}
       )
       when is_pid(observer) do
    send(observer, {:test_transfer_output_preparing, self()})

    receive do
      :complete_output_preparation -> :ok
    after
      5_000 -> exit(:output_preparation_timeout)
    end
  end

  defp await_output_preparation(_binding, _demand), do: :ok

  @impl true
  def prepare_candidate(binding, _candidate, demand, options) do
    {:ok, _resource, :ready} = readiness(binding.instance)
    await_output_preparation(binding, demand)

    track =
      if demand.audio_input? or demand.speech_to_text?,
        do: Map.get(binding, :input_track, input_track())

    if demand.speech_to_text? do
      provider = Keyword.fetch!(options, :speech_to_text)
      ingress = binding.attachment.media_ingress

      with :ok <- Ingress.prepare_track(ingress, track, provider),
           {:ok, resources} <- Ingress.readiness_resources(ingress, provider),
           do: {:ok, [binding.resource | resources], track, []}
    else
      {:ok, [binding.resource], track, []}
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
       source_control?: Keyword.get(options, :source_control?, false),
       source_hold_from: nil,
       source_arm_from: nil,
       defer_readiness?: false,
       pending_readiness: nil,
       defer_adoption?: false,
       pending_adoption: nil,
       private_policy: nil,
       binding: %{
         identity: identity,
         instance: self(),
         adapter: __MODULE__,
         resource: resource,
         generation: make_ref(),
         attachment: nil,
         output: Keyword.fetch!(options, :output),
         input_track: Keyword.get(options, :input_track, input_track()),
         output_preparation_observer: Keyword.get(options, :output_preparation_observer),
         policy_subscription: [
           id: command.connection_id <> ":room-output",
           tenant_id: command.tenant_id,
           room_id: command.room_id,
           incarnation_id: command.incarnation_id,
           recipient_participant_id: command.participant_id,
           subscriber: self(),
           mode: :mix_minus
         ]
       }
     }}
  end

  @impl true
  def handle_call(:attach, _from, state) do
    case CallEngine.attach_connection(
           state.command,
           state.binding.output,
           state.source_control?
         ) do
      {:ok, attachment} ->
        {:reply, {:ok, attachment}, put_in(state.binding.attachment, attachment)}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:vxpipe_sts_source_hold, scope}, from, state) do
    send(state.observer, {:test_sts_source_hold, self(), scope})
    {:noreply, %{state | source_hold_from: from}}
  end

  def handle_call({:vxpipe_sts_source_arm, scope}, from, state) do
    send(state.observer, {:test_sts_source_arm, self(), scope})
    {:noreply, %{state | source_arm_from: from}}
  end

  def handle_call({:complete_source_hold, result}, _from, state) do
    if state.source_hold_from, do: GenServer.reply(state.source_hold_from, result)
    {:reply, :ok, %{state | source_hold_from: nil}}
  end

  def handle_call({:complete_source_arm, result}, _from, state) do
    if state.source_arm_from, do: GenServer.reply(state.source_arm_from, result)
    {:reply, :ok, %{state | source_arm_from: nil}}
  end

  def handle_call({:run, callback}, _from, state), do: {:reply, callback.(), state}

  def handle_call(:attachment, _from, state), do: {:reply, state.binding.attachment, state}

  def handle_call(:vxpipe_connection_readiness, _from, state),
    do: {:reply, {:ok, state.binding}, state}

  def handle_call(:readiness, from, %{defer_readiness?: true} = state) do
    send(state.observer, {:test_transfer_readiness_waiting, self()})
    {:noreply, %{state | pending_readiness: from}}
  end

  def handle_call(:readiness, _from, state),
    do: {:reply, {:ok, state.binding.resource, :ready}, state}

  def handle_call(:renew_readiness, _from, state) do
    resource = %{state.binding.resource | generation: make_ref()}
    {:reply, :ok, put_in(state.binding.resource, resource)}
  end

  def handle_call(:defer_readiness, _from, state),
    do: {:reply, :ok, %{state | defer_readiness?: true}}

  def handle_call(:complete_readiness, _from, state) do
    GenServer.reply(state.pending_readiness, {:ok, state.binding.resource, :ready})
    {:reply, :ok, %{state | defer_readiness?: false, pending_readiness: nil}}
  end

  def handle_call({:vxpipe_prepare_transfer_media, attempt}, _from, state) do
    with {:ok, media} <- CallEngine.prepare_transfer_media(state.command, attempt) do
      speech = media.speech_to_text
      enforcers = if speech, do: [speech.capability, speech.ingress], else: []
      ingress = if speech, do: speech.ingress
      attachment = %{state.binding.attachment | media_ingress: ingress}

      {:reply, {:ok, Map.put(media, :enforcers, enforcers)},
       put_in(%{state | private_policy: media.policy}.binding.attachment, attachment)}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call(:defer_adoption, _from, state),
    do: {:reply, :ok, %{state | defer_adoption?: true}}

  def handle_call(:complete_adoption, _from, state) do
    GenServer.reply(state.pending_adoption, :ok)
    {:reply, :ok, %{state | defer_adoption?: false, pending_adoption: nil}}
  end

  def handle_call(:adopt, from, state) do
    attachment = %{
      state.binding.attachment
      | admission: :main,
        transfer_attempt_id: nil,
        room_audio_input_mode: :enabled,
        room_audio_output_mode: :mix_minus
    }

    state = put_in(state.binding.attachment, attachment)

    if state.defer_adoption? do
      send(state.observer, {:test_transfer_adoption_waiting, self()})
      {:noreply, %{state | pending_adoption: from}}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info(
        {:vxpipe_call_ready, monitor},
        %{binding: %{attachment: %{room_monitor: monitor}}} = state
      ) do
    send(state.observer, {:test_call_ready, state.command.room_id})
    {:noreply, state}
  end

  def handle_info({:vxpipe_transfer_active, attempt}, state) do
    send(state.observer, {:vxpipe_transfer_active, attempt})
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_startup_speech, monitor},
        %{binding: %{attachment: %{room_monitor: monitor}}} = state
      ) do
    command = %{state.command | deadline: DateTime.add(DateTime.utc_now(), 5, :second)}

    case CallEngine.activate_speech_to_text(command) do
      {:ok, ingress} ->
        {:noreply, put_in(state.binding.attachment.media_ingress, ingress)}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  def handle_info(message, state) do
    send(state.observer, message)
    {:noreply, state}
  end

  defp name(command),
    do:
      {:via, Registry,
       {Vxpipe.CallEngine.RoomRegistry,
        {__MODULE__, command.incarnation_id, command.connection_id}}}

  defp input_track, do: %{track_id: "embedded", codec: :opus, sample_rate: 48_000, channels: 1}
end
