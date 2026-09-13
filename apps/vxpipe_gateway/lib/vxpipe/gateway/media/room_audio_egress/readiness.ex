defmodule Vxpipe.Gateway.Media.RoomAudioEgress.Readiness do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.Resource

  def readiness(egress) do
    with {:ok, resource, status, _dependencies} <- observe(egress),
         do: {:ok, resource, status}
  end

  def resources(egress) do
    with {:ok, resource, _status, dependencies} <- observe(egress),
         do: {:ok, [resource | dependencies]}
  end

  def binding(state) do
    interval =
      if state.policy,
        do: Snapshot.interval(state.policy, :audio_output, state.identity.participant_id)

    %{
      resource: %{state.readiness_resource | policy_interval: interval},
      pipeline_ready?: state.pipeline_ready?,
      engine: state.engine,
      subscription: state.subscription,
      subscription_id: state.subscription_id
    }
  end

  # Query the mixer outside the egress loop: it can be waiting for this enforcer's ack.
  defp observe(egress) do
    with {:ok, binding} <- GenServer.call(egress, :readiness_binding, 1_000),
         {:ok, subscription, subscription_status} <- subscription_readiness(binding) do
      dependencies = if subscription, do: [subscription], else: []
      stable_dependencies = Enum.map(dependencies, &%{&1 | policy_interval: nil})

      resource = %{
        binding.resource
        | configuration: Resource.signature({binding.resource.configuration, stable_dependencies})
      }

      {:ok, resource, status(binding, subscription, subscription_status), dependencies}
    else
      _unavailable -> {:error, :unavailable}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp subscription_readiness(%{subscription: nil}), do: {:ok, nil, :preparing}

  defp subscription_readiness(binding) do
    if function_exported?(binding.engine, :room_audio_subscription_readiness, 1) do
      binding.engine.room_audio_subscription_readiness(binding.subscription)
      |> validate_subscription(binding)
    else
      {:ok, nil, :failed}
    end
  end

  defp validate_subscription(
         {:ok, %Resource{kind: :audio_subscription} = resource, status},
         binding
       )
       when status in [:ready, :preparing, :failed] do
    if Resource.bound?(resource) and resource.scope == binding.resource.scope and
         resource.binding == binding.subscription_id,
       do: {:ok, resource, status},
       else: {:ok, nil, :failed}
  end

  defp validate_subscription({:error, :unavailable} = error, _binding), do: error
  defp validate_subscription(_invalid, _binding), do: {:ok, nil, :failed}

  defp status(_binding, _subscription, :failed), do: :failed

  defp status(binding, %Resource{} = subscription, :ready) do
    if binding.pipeline_ready? and binding.resource.policy_interval != nil and
         binding.resource.policy_interval == subscription.policy_interval,
       do: :ready,
       else: :preparing
  end

  defp status(_binding, _subscription, _status), do: :preparing
end
