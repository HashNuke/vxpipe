defmodule Vxpipe.CallEngine.Recording.EgressReadiness do
  @moduledoc "Readiness of an exact native recording tap, with policy owned by the mixer."

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Candidate, Snapshot}
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.RoomMixer

  def prepare(%Resource{} = native, identity, mixer, policy) do
    with {:ok, ^native, binding, resource, status} <-
           observe(native.adapter, native.instance, :installed),
         true <- matches?(native, binding, identity, mixer),
         true <- binding.policy_interval == Snapshot.interval(policy, :recording),
         true <- status in [:ready, :preparing] do
      {:ok, Map.merge(binding, %{resource: resource, status: status})}
    else
      _unavailable -> {:error, :unavailable}
    end
  end

  def prepare_candidate(
        %Resource{} = native,
        identity,
        mixer,
        %Candidate{} = candidate,
        %Resource{kind: :room_mixer, scope: :room, instance: mixer, adapter: RoomMixer} =
          policy_resource
      ) do
    with true <- candidate.snapshot.effective.record_audio,
         true <- Authority.whereis(identity.incarnation_id) == candidate.authority,
         :ok <- Authority.validate_candidate(candidate.authority, candidate),
         true <-
           policy_resource.policy_interval ==
             Map.take(candidate.snapshot.intervals, [:audio_input, :audio_output, :recording]),
         {:ok, ^policy_resource, policy_status} <- RoomMixer.readiness_binding(policy_resource),
         {:ok, ^native, binding, resource, tap_status} <-
           observe(native.adapter, native.instance, :physical),
         true <- matches?(native, binding, identity, mixer),
         {:ok, ^policy_resource, current_status} <- RoomMixer.readiness_binding(policy_resource),
         status = status([policy_status, tap_status, current_status]),
         true <- status in [:ready, :preparing] do
      {:ok,
       Map.merge(binding, %{
         resource: resource,
         resources: [resource, policy_resource],
         status: status
       })}
    else
      _unavailable -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def prepare_candidate(_native, _identity, _mixer, _candidate, _policy_resource),
    do: {:error, :unavailable}

  @impl true
  def readiness(%Resource{} = resource), do: readiness_binding(resource)
  def readiness(_unsupported), do: {:error, :unavailable}

  @impl true
  def readiness_binding(%Resource{binding: {_connection, adapter}, instance: instance}) do
    case observe(adapter, instance, :physical) do
      {:ok, _native, _binding, resource, status} -> {:ok, resource, status}
      _unavailable -> {:error, :unavailable}
    end
  end

  defp matches?(native, binding, identity, mixer) do
    binding.mixer == mixer and
      binding.identity == Map.take(identity, [:tenant_id, :room_id, :incarnation_id]) and
      native.scope == {:participant, identity.participant_id} and
      binding.connection_id == identity.connection_id
  end

  defp observe(adapter, instance, mode) do
    with true <- Code.ensure_loaded?(adapter),
         true <- function_exported?(adapter, :recording_binding, 1),
         {:ok, %Resource{kind: :audio_output, instance: ^instance} = native, native_status} <-
           adapter.readiness(instance),
         true <- native.adapter == adapter and Resource.bound?(native),
         {:ok, ^native, %EgressHandoff{} = handoff, format} <- adapter.recording_binding(instance),
         mixer = EgressHandoff.receiver(handoff),
         {:ok, binding, tap_status} <- observe_tap(mixer, handoff, mode),
         true <- format == Map.take(binding, [:sample_rate, :channels, :frame_samples]),
         true <- native.binding == binding.connection_id,
         {:ok, ^native, ^handoff, ^format} <- adapter.recording_binding(instance),
         {:ok, ^native, current_status} <- adapter.readiness(instance) do
      resource = resource(native, binding)
      status = status([native_status, tap_status, current_status])
      {:ok, native, Map.put(binding, :mixer, mixer), resource, status}
    else
      _unavailable -> {:error, :unavailable}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp observe_tap(mixer, handoff, :installed),
    do: RoomMixer.recording_egress_readiness(mixer, handoff)

  defp observe_tap(mixer, handoff, :physical),
    do: RoomMixer.recording_tap_readiness(mixer, handoff)

  defp resource(native, binding) do
    %Resource{
      kind: :recording_output,
      scope: native.scope,
      binding: {native.binding, native.adapter},
      instance: native.instance,
      generation: native.generation,
      configuration: Resource.signature({native.configuration, binding.configuration}),
      policy_interval: nil,
      adapter: __MODULE__
    }
  end

  defp status(statuses) do
    cond do
      Enum.any?(statuses, &(&1 not in [:ready, :preparing])) -> :failed
      :preparing in statuses -> :preparing
      true -> :ready
    end
  end
end
