defmodule Vxpipe.CallEngine.Media.Ingress.Readiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.Ingress.AudioOrigin
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.Resource

  def media_format(ingress) do
    with {:ok, binding} <- call(ingress, :readiness_binding),
         {:ok, provider} <- input_binding(binding, :current),
         :ok <- validate_provider(binding, provider) do
      {:ok, provider.media_format}
    end
  end

  def readiness(ingress) do
    with {:ok, resource, status, _dependencies} <- observe(ingress),
         do: {:ok, resource, status}
  end

  def resources(ingress, provider \\ :current) do
    with {:ok, resource, _status, dependencies} <- observe(ingress, provider),
         do: {:ok, [resource | dependencies]}
  end

  def readiness_binding(%Resource{
        instance: ingress,
        binding: {_connection, :prepared_speech, provider}
      }) do
    with {:ok, resource, status, _dependencies} <- observe(ingress, provider),
         do: {:ok, resource, status}
  end

  def readiness_binding(%Resource{instance: ingress}), do: readiness(ingress)

  def prepare_track(ingress, track, selection \\ :current) do
    with :ok <- validate_track(track),
         {:ok, binding} <- call(ingress, :readiness_binding),
         :ok <- validate_track_binding(binding, track) do
      if binding.prepared_track == track and selection == :current do
        :ok
      else
        with {:ok, provider} <- input_binding(binding, selection),
             :ok <- validate_provider(binding, provider),
             :ok <- validate_interval(binding, provider, selection),
             :ok <- validate_format(track, provider.media_format) do
          call(ingress, {:prepare_track, binding.resource, track})
        end
      end
    end
  end

  def binding(state) do
    interval =
      if state.policy,
        do: Snapshot.interval(state.policy, :speech_to_text, state.identity.participant_id)

    resource = %{
      state.readiness_resource
      | policy_interval: interval,
        configuration:
          Resource.signature({state.readiness_resource.configuration, state.prepared_track})
    }

    capacity? =
      state.total_bytes < state.maximum_bytes and
        :queue.len(state.queue) + if(state.in_flight == nil, do: 0, else: 1) <
          state.maximum_frames

    origin_ready? =
      AudioOrigin.current?(
        state.audio_origin,
        state.policy,
        state.identity.participant_id,
        state.activity_agent_id
      )

    %{
      resource: resource,
      identity: state.identity,
      capability: state.capability,
      activity_agent_id: state.activity_agent_id,
      audio_origin: state.audio_origin,
      native_generation: state.native_generation,
      source_epoch: state.source_epoch,
      source_cutover_pending?: state.source_cutover_pending?,
      prepared_track: state.prepared_track,
      track_id: state.track_id,
      capacity?: capacity?,
      available?:
        interval != nil and state.policy_demand? and state.prepared_track != nil and capacity? and
          origin_ready? and not state.source_cutover_pending?
    }
  end

  def validate_track_binding(binding, track) do
    cond do
      binding.track_id != nil and binding.track_id != track.track_id -> {:error, :wrong_track}
      binding.prepared_track not in [nil, track] -> {:error, :track_already_prepared}
      true -> :ok
    end
  end

  defp observe(ingress, selection \\ :current) do
    with {:ok, binding} <- call(ingress, :readiness_binding),
         {:ok, provider} <- input_binding(binding, selection),
         :ok <- validate_interval(binding, provider, selection),
         {:ok, ^binding} <- call(ingress, :readiness_binding) do
      case validate_provider(binding, provider) do
        :ok -> report(prepare_binding(binding, provider), provider)
        {:error, _reason} -> {:ok, binding.resource, :failed, []}
      end
    else
      _unavailable_or_changed -> {:error, :unavailable}
    end
  end

  defp input_binding(binding, :current), do: SpeechToText.input_binding(binding.capability)

  defp input_binding(binding, %Resource{} = provider),
    do: SpeechToText.input_binding(binding.capability, provider)

  defp input_binding(_binding, _selection), do: {:error, :unavailable}

  defp validate_interval(_binding, _provider, :current), do: :ok

  defp validate_interval(binding, provider, _selection) do
    if binding.resource.policy_interval in provider.policy_intervals,
      do: :ok,
      else: {:error, :policy_not_prepared}
  end

  defp prepare_binding(
         binding,
         %{resource: %{binding: {_id, :prepared_policy, _token}}} = provider
       ) do
    resource = %{
      binding.resource
      | binding: {binding.identity.connection_id, :prepared_speech, provider.resource},
        policy_interval: provider.resource.policy_interval
    }

    %{
      binding
      | resource: resource,
        available?:
          resource.policy_interval != nil and binding.prepared_track != nil and binding.capacity?
    }
  end

  defp prepare_binding(binding, _provider), do: binding

  defp report(binding, provider) do
    resource = %{
      binding.resource
      | configuration:
          Resource.signature(
            {binding.resource.configuration, %{provider.resource | policy_interval: nil}}
          )
    }

    status =
      cond do
        provider.status == :failed ->
          :failed

        binding.prepared_track != nil and
            validate_format(binding.prepared_track, provider.media_format) != :ok ->
          :failed

        not binding.available? ->
          :preparing

        not native_origin_current?(binding, provider) ->
          :preparing

        resource.policy_interval != provider.resource.policy_interval ->
          :preparing

        true ->
          provider.status
      end

    {:ok, resource, status, [provider.resource]}
  end

  defp native_origin_current?(%{activity_agent_id: nil}, _provider), do: true

  defp native_origin_current?(%{resource: %{binding: {_id, :prepared_speech, _provider}}}, _),
    do: true

  defp native_origin_current?(%{audio_origin: origin}, %{audio_origin: origin})
       when is_map(origin),
       do: true

  defp native_origin_current?(_binding, _provider), do: false

  defp validate_provider(binding, %{identity: identity, resource: %Resource{} = resource}) do
    if identity == binding.identity and resource.kind == :speech_to_text and
         resource.instance == binding.capability and
         resource.scope == {:participant, identity.participant_id} and
         valid_provider_binding?(resource.binding, identity.connection_id) and
         Resource.bound?(resource),
       do: :ok,
       else: {:error, :wrong_connection}
  end

  defp validate_provider(_binding, _provider), do: {:error, :unavailable}

  defp valid_provider_binding?(connection, connection), do: true

  defp valid_provider_binding?({connection, :prepared_policy, token}, connection),
    do: is_reference(token)

  defp valid_provider_binding?(_binding, _connection), do: false

  defp validate_format(track, %{codec: codec, sample_rate: sample_rate}) do
    if track.codec == codec and track.sample_rate == sample_rate,
      do: :ok,
      else: {:error, :unsupported_audio}
  end

  defp validate_format(_track, _format), do: {:error, :unsupported_audio}

  defp validate_track(
         %{track_id: id, codec: codec, sample_rate: rate, channels: channels} = track
       )
       when is_binary(id) and byte_size(id) > 0 and is_atom(codec) and not is_nil(codec) and
              is_integer(rate) and rate > 0 and channels in [1, 2] and map_size(track) == 4,
       do: :ok

  defp validate_track(_track), do: {:error, :invalid_track}

  defp call(ingress, message) do
    GenServer.call(ingress, message, 1_000)
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
