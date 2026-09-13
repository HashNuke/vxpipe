defmodule Vxpipe.CallEngine.Recording.EgressReadiness do
  @moduledoc "Readiness of a native output's exact, mixer-authorized recording tap."

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.RoomMixer

  def prepare(%Resource{} = native, identity, mixer, policy) do
    with {:ok, ^native, binding, resource, status} <- observe(native.adapter, native.instance),
         true <- binding.mixer == mixer,
         true <- binding.identity == Map.take(identity, [:tenant_id, :room_id, :incarnation_id]),
         true <- native.scope == {:participant, identity.participant_id},
         true <- binding.connection_id == identity.connection_id,
         true <- resource.policy_interval == Snapshot.interval(policy, :recording),
         true <- status in [:ready, :preparing] do
      {:ok, Map.merge(binding, %{resource: resource, status: status})}
    else
      _unavailable -> {:error, :unavailable}
    end
  end

  @impl true
  def readiness(%Resource{} = resource), do: readiness_binding(resource)
  def readiness(_unsupported), do: {:error, :unavailable}

  @impl true
  def readiness_binding(%Resource{binding: {_connection, adapter}, instance: instance}) do
    case observe(adapter, instance) do
      {:ok, _native, _binding, resource, status} -> {:ok, resource, status}
      _unavailable -> {:error, :unavailable}
    end
  end

  defp observe(adapter, instance) do
    with true <- Code.ensure_loaded?(adapter),
         true <- function_exported?(adapter, :recording_binding, 1),
         {:ok, %Resource{kind: :audio_output, instance: ^instance} = native, native_status} <-
           adapter.readiness(instance),
         true <- native.adapter == adapter and Resource.bound?(native),
         {:ok, ^native, %EgressHandoff{} = handoff, format} <- adapter.recording_binding(instance),
         mixer = EgressHandoff.receiver(handoff),
         {:ok, binding, tap_status} <- RoomMixer.recording_egress_readiness(mixer, handoff),
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

  defp resource(native, binding) do
    %Resource{
      kind: :recording_output,
      scope: native.scope,
      binding: {native.binding, native.adapter},
      instance: native.instance,
      generation: native.generation,
      configuration: Resource.signature({native.configuration, binding.configuration}),
      policy_interval: binding.policy_interval,
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
