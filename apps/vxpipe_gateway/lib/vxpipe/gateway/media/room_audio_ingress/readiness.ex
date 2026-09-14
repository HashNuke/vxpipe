defmodule Vxpipe.Gateway.Media.RoomAudioIngress.Readiness do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.Resource

  def readiness(ingress) do
    with {:ok, resource, status, _dependencies} <- observe(ingress),
         do: {:ok, resource, status}
  end

  def resources(ingress, token \\ nil) do
    with {:ok, resource, _status, dependencies} <- observe(ingress, token),
         do: {:ok, [resource | dependencies]}
  end

  def readiness_binding(%Resource{instance: ingress, binding: {_id, :prepared_policy, token}}) do
    with {:ok, resource, status, _dependencies} <- observe(ingress, token),
         do: {:ok, resource, status}
  end

  def readiness_binding(%Resource{instance: ingress}), do: readiness(ingress)

  def prepare_track(ingress, track, token \\ nil) do
    with {:ok, binding} <- call(ingress, token),
         :ok <- prepare_pipeline(binding, track),
         {:ok, current} <- call(ingress, token),
         true <- same_binding?(binding, current) do
      :ok
    else
      {:error, _reason} = error -> error
      _changed -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def binding(state) do
    interval =
      if state.policy,
        do: Snapshot.interval(state.policy, :audio_input, state.identity.participant_id)

    %{
      connection_id: state.connection_id,
      resource: %{state.readiness_resource | policy_interval: interval},
      pipeline: state.pipeline,
      pipeline_id: state.pipeline_id,
      pipeline_pid: state.pipeline_pid,
      pipeline_ready?: state.pipeline_ready?
    }
  end

  def same_binding?(left, right),
    do: Map.drop(left, [:pipeline_ready?]) == Map.drop(right, [:pipeline_ready?])

  defp observe(ingress, token \\ nil) do
    with {:ok, original} <- call(ingress, token),
         {:ok, input, input_status} <- pipeline_readiness(original),
         {:ok, binding} <- call(ingress, token),
         true <- same_binding?(original, binding) do
      resource = %{
        binding.resource
        | configuration: Resource.signature({binding.resource.configuration, input})
      }

      status =
        cond do
          input_status == :failed -> :failed
          not binding.pipeline_ready? or resource.policy_interval == nil -> :preparing
          true -> input_status
        end

      with :ok <- confirm(ingress, token, binding, status),
           do: {:ok, resource, status, if(input, do: [input], else: [])}
    else
      _unavailable_or_changed -> {:error, :unavailable}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp prepare_pipeline(%{pipeline_id: nil}, _track), do: {:error, :unavailable}

  defp prepare_pipeline(binding, track) do
    if Code.ensure_loaded?(binding.pipeline) and
         function_exported?(binding.pipeline, :prepare_track, 2),
       do: binding.pipeline.prepare_track(binding.pipeline_id, track),
       else: {:error, :unsupported_pipeline}
  end

  defp pipeline_readiness(%{pipeline_id: nil}), do: {:ok, nil, :preparing}

  defp pipeline_readiness(binding) do
    # The stored PID supervises Membrane; the registered ID addresses its actual pipeline.
    if Code.ensure_loaded?(binding.pipeline) and
         function_exported?(binding.pipeline, :readiness, 1),
       do: validate(binding.pipeline.readiness(binding.pipeline_id), binding),
       else: {:ok, nil, :failed}
  end

  defp validate({:ok, %Resource{kind: :audio_input} = input, status}, binding)
       when status in [:preparing, :ready, :failed] do
    if Resource.bound?(input) and input.scope == binding.resource.scope and
         input.binding == binding.connection_id and input.adapter == binding.pipeline,
       do: {:ok, input, status},
       else: {:ok, nil, :failed}
  end

  defp validate({:error, :unavailable} = error, _binding), do: error
  defp validate(_invalid, _binding), do: {:ok, nil, :failed}

  defp call(ingress, nil), do: GenServer.call(ingress, :readiness_binding, 1_000)

  defp call(ingress, token),
    do: GenServer.call(ingress, {:policy_readiness_binding, token}, 1_000)

  defp confirm(_ingress, nil, _binding, _status), do: :ok

  defp confirm(ingress, token, binding, status),
    do: GenServer.call(ingress, {:confirm_policy_readiness, token, binding, status}, 1_000)
end
