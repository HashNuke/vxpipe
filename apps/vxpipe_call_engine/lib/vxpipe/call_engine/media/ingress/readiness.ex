defmodule Vxpipe.CallEngine.Media.Ingress.Readiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.Resource

  def readiness(ingress) do
    with {:ok, resource, status, _dependencies} <- observe(ingress),
         do: {:ok, resource, status}
  end

  def resources(ingress) do
    with {:ok, resource, _status, dependencies} <- observe(ingress),
         do: {:ok, [resource | dependencies]}
  end

  def prepare_track(ingress, track) do
    with :ok <- validate_track(track),
         {:ok, binding} <- call(ingress, :readiness_binding),
         :ok <- validate_track_binding(binding, track) do
      if binding.prepared_track == track do
        :ok
      else
        with {:ok, provider} <- SpeechToText.input_binding(binding.capability),
             :ok <- validate_provider(binding, provider),
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

    %{
      resource: resource,
      identity: state.identity,
      capability: state.capability,
      prepared_track: state.prepared_track,
      track_id: state.track_id,
      available?:
        interval != nil and state.policy_demand? and state.prepared_track != nil and
          state.total_bytes < state.maximum_bytes and
          :queue.len(state.queue) + if(state.in_flight == nil, do: 0, else: 1) <
            state.maximum_frames
    }
  end

  def validate_track_binding(binding, track) do
    cond do
      binding.track_id != nil and binding.track_id != track.track_id -> {:error, :wrong_track}
      binding.prepared_track not in [nil, track] -> {:error, :track_already_prepared}
      true -> :ok
    end
  end

  defp observe(ingress) do
    with {:ok, binding} <- call(ingress, :readiness_binding),
         {:ok, provider} <- SpeechToText.input_binding(binding.capability),
         {:ok, ^binding} <- call(ingress, :readiness_binding) do
      case validate_provider(binding, provider) do
        :ok -> report(binding, provider)
        {:error, _reason} -> {:ok, binding.resource, :failed, []}
      end
    else
      _unavailable_or_changed -> {:error, :unavailable}
    end
  end

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

        resource.policy_interval != provider.resource.policy_interval ->
          :preparing

        true ->
          provider.status
      end

    {:ok, resource, status, [provider.resource]}
  end

  defp validate_provider(binding, %{identity: identity, resource: %Resource{} = resource}) do
    if identity == binding.identity and resource.kind == :speech_to_text and
         resource.instance == binding.capability and
         resource.scope == {:participant, identity.participant_id} and
         resource.binding == identity.connection_id and Resource.bound?(resource),
       do: :ok,
       else: {:error, :wrong_connection}
  end

  defp validate_provider(_binding, _provider), do: {:error, :unavailable}

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
