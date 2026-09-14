defmodule Vxpipe.Gateway.Media.ConnectionReadiness do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Media.ConnectionReadiness

  alias Vxpipe.CallEngine.Media.{Ingress, PreparedConnection}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot, SpeechToTextDemand}
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.Gateway.Media.{OutputArbiter, RoomAudioEgress, RoomAudioIngress}

  @intervals %{
    room_audio_ingress: :audio_input,
    speech_to_text_ingress: :speech_to_text,
    speech_to_text: :speech_to_text,
    room_audio_egress: :audio_output,
    audio_subscription: :audio_output
  }

  def binding(state, transport, transport_binding, output) do
    command = state.attach_command

    %{
      adapter: __MODULE__,
      instance: self(),
      generation: transport_binding.resource.generation,
      identity: %{
        tenant_id: command.tenant_id,
        room_id: command.room_id,
        incarnation_id: command.incarnation_id,
        participant_id: command.participant_id,
        connection_id: command.connection_id
      },
      transport: transport,
      transport_binding: transport_binding,
      attachment: state.attachment,
      output: output,
      room_input: state.room_audio_ingress,
      room_output: state.room_audio_egress
    }
  end

  @impl true
  def prepare_binding(binding, policy, demand) do
    with :ok <- validate_demand(binding, policy, demand),
         {:ok, track} <- input_track(binding, demand),
         {:ok, current} <- collect(binding, demand),
         :ok <- validate_intervals(current, policy, binding.identity.participant_id),
         :ok <- prepare_input(binding, track, demand),
         {:ok, resources} <- collect(binding, demand),
         :ok <- validate_intervals(resources, policy, binding.identity.participant_id) do
      {:ok, resources, track}
    end
  end

  @impl true
  def prepare_candidate(binding, candidate, demand, options) do
    with :ok <- validate_candidate_admission(binding, candidate, demand, options),
         :ok <- OutputArbiter.confirm_hold(binding.output, Keyword.fetch!(options, :generation)),
         {:ok, track} <- input_track(binding, demand),
         {:ok, base} <- base_resources(binding, demand),
         {:ok, resources, preparations} <-
           candidate_parts(binding, candidate, demand, track, options) do
      case validate_intervals(resources, candidate.snapshot, binding.identity.participant_id) do
        :ok ->
          {:ok, base ++ resources, track, preparations}

        {:error, _reason} = error ->
          _ = PreparedConnection.discard_preparations(preparations)
          error
      end
    end
  end

  defp candidate_parts(binding, candidate, demand, track, options) do
    [:room_input, :speech_input, :room_output]
    |> Enum.reduce_while({:ok, [], []}, fn part, {:ok, resources, preparations} ->
      case prepare_part(part, binding, candidate, demand, track, options) do
        {:ok, selected, prepared} ->
          {:cont, {:ok, resources ++ selected, preparations ++ prepared}}

        {:error, _reason} = error ->
          _ = PreparedConnection.discard_preparations(preparations)
          {:halt, error}
      end
    end)
  end

  defp prepare_part(:room_input, binding, candidate, %{audio_input?: false}, _track, options) do
    if is_pid(binding.room_input) and
         not RoomAudioIngress.PolicyPreparation.required?(
           candidate.snapshot,
           binding.identity.participant_id
         ),
       do: prepare_room_input(binding.room_input, candidate, nil, options),
       else: {:ok, [], []}
  end

  defp prepare_part(:room_input, %{room_input: input}, candidate, _demand, track, options)
       when is_pid(input), do: prepare_room_input(input, candidate, track, options)

  defp prepare_part(
         :speech_input,
         _binding,
         _candidate,
         %{speech_to_text?: false},
         _track,
         _options
       ),
       do: {:ok, [], []}

  defp prepare_part(:speech_input, binding, _candidate, _demand, track, options) do
    input = binding.attachment.media_ingress

    with %Resource{kind: :speech_to_text} = provider <- Keyword.get(options, :speech_to_text),
         :ok <- Ingress.prepare_track(input, track, provider),
         {:ok, resources} <- Ingress.readiness_resources(input, provider) do
      {:ok, resources, []}
    else
      {:error, _reason} = error -> error
      _missing -> {:error, :missing_prepared_speech}
    end
  end

  defp prepare_part(:room_output, _binding, _candidate, %{room_output?: false}, _track, _options),
    do: {:ok, [], []}

  defp prepare_part(:room_output, %{room_output: output}, candidate, _demand, _track, options)
       when is_pid(output) do
    case Keyword.get(options, :subscription) do
      %Vxpipe.CallEngine.RoomMixer.Subscription{} = subscription ->
        with {:ok, prepared} <-
               RoomAudioEgress.prepare_policy(output, candidate, subscription, options),
             do: prepared_part(RoomAudioEgress, output, prepared)

      _missing ->
        {:error, :missing_prepared_subscription}
    end
  end

  defp prepare_part(_part, _binding, _candidate, _demand, _track, _options),
    do: {:error, :missing_required_media}

  defp prepared_part(adapter, instance, prepared),
    do:
      {:ok, prepared.resources, [%{adapter: adapter, instance: instance, token: prepared.token}]}

  defp prepare_room_input(input, candidate, track, options) do
    with {:ok, prepared} <- RoomAudioIngress.prepare_policy(input, candidate, track, options),
         do: prepared_part(RoomAudioIngress, input, prepared)
  end

  defp validate_candidate_admission(binding, candidate, demand, options) do
    if binding.attachment.admission == :transfer_preparation do
      if binding.attachment.transfer_attempt_id == Keyword.fetch!(options, :attempt_id) and
           not MapSet.member?(
             candidate.base_snapshot.present_participant_ids,
             binding.identity.participant_id
           ),
         do: validate_policy_demand(binding, candidate.snapshot, demand),
         else: {:error, :preparation_not_admitted}
    else
      validate_demand(binding, candidate.snapshot, demand)
    end
  end

  defp input_track(binding, demand) do
    if demand.audio_input? or demand.speech_to_text?,
      do: binding.transport.input_track(binding.instance),
      else: {:ok, nil}
  end

  defp prepare_input(binding, track, demand) do
    with :ok <- prepare_track(RoomAudioIngress, binding.room_input, track, demand.audio_input?),
         :ok <-
           prepare_track(Ingress, binding.attachment.media_ingress, track, demand.speech_to_text?) do
      :ok
    end
  end

  defp prepare_track(_adapter, _input, _track, false), do: :ok
  defp prepare_track(adapter, input, track, true), do: adapter.prepare_track(input, track)

  defp collect(binding, demand) do
    with {:ok, base} <- base_resources(binding, demand),
         {:ok, room_input} <- resources(RoomAudioIngress, binding.room_input, demand.audio_input?),
         {:ok, room_output} <-
           resources(RoomAudioEgress, binding.room_output, demand.room_output?),
         {:ok, speech_input} <-
           resources(Ingress, binding.attachment.media_ingress, demand.speech_to_text?) do
      {:ok, base ++ room_input ++ room_output ++ speech_input}
    end
  end

  defp base_resources(binding, demand) do
    with {:ok, transport} <-
           binding.transport.readiness_resources(binding.instance,
             input?: demand.audio_input? or demand.speech_to_text?
           ),
         {:ok, output} <- resources(OutputArbiter, binding.output, true),
         do: {:ok, transport ++ output}
  end

  defp resources(_adapter, _instance, false), do: {:ok, []}

  defp resources(adapter, instance, true) when is_pid(instance),
    do: adapter.readiness_resources(instance)

  defp resources(_adapter, _instance, true), do: {:error, :missing_required_media}

  defp validate_intervals(resources, policy, participant) do
    if Enum.all?(resources, &current_interval?(&1, policy, participant)),
      do: :ok,
      else: {:error, :policy_not_prepared}
  end

  defp current_interval?(%Resource{} = resource, policy, participant) do
    case Map.fetch(@intervals, resource.kind) do
      {:ok, scope} -> resource.policy_interval == Snapshot.interval(policy, scope, participant)
      :error -> true
    end
  end

  defp current_interval?(_resource, _policy, _participant), do: false

  defp validate_demand(binding, policy, demand) do
    attachment = binding.attachment

    cond do
      (demand.audio_input? or demand.speech_to_text?) and
          attachment.room_audio_input_mode != :enabled ->
        {:error, :input_not_admitted}

      demand.room_output? and attachment.room_audio_output_mode == :disabled ->
        {:error, :output_not_admitted}

      true ->
        validate_policy_demand(binding, policy, demand)
    end
  end

  defp validate_policy_demand(binding, policy, demand) do
    participant = binding.identity.participant_id

    cond do
      demand.audio_input? and not audio_input_permitted?(policy, participant) ->
        {:error, :input_not_permitted}

      demand.room_output? and not room_output_permitted?(policy, participant) ->
        {:error, :output_not_permitted}

      demand.speech_to_text? and not SpeechToTextDemand.required?(policy, participant) ->
        {:error, :speech_not_permitted}

      true ->
        :ok
    end
  end

  defp audio_input_permitted?(policy, participant) do
    policy.effective.record_audio or
      Enum.any?(policy.present_participant_ids, fn recipient ->
        recipient != participant and
          Effective.audio_route_permitted?(policy.effective, participant, recipient)
      end)
  end

  defp room_output_permitted?(policy, participant) do
    Enum.any?(policy.present_participant_ids, fn source ->
      source != participant and
        Effective.audio_route_permitted?(policy.effective, source, participant)
    end)
  end
end
