defmodule Vxpipe.CallEngine.RoomRecording.Readiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.RoomMixer.Subscription

  def readiness(recording) do
    with {:ok, resource, status, _dependencies} <- observe(recording),
         do: {:ok, resource, status}
  end

  def resources(recording) do
    with {:ok, resource, _status, dependencies} <- observe(recording),
         do: {:ok, [resource | dependencies]}
  end

  def prepared_readiness(recording, token) do
    with {:ok, resource, status, _dependencies} <- observe(recording, token),
         do: {:ok, resource, status}
  end

  def prepared_resources(recording, token) do
    with {:ok, resource, _status, dependencies} <- observe(recording, token),
         do: {:ok, [resource | dependencies]}
  end

  defp observe(recording, token \\ nil) do
    request = if token, do: {:prepared_readiness_binding, token}, else: :readiness_binding

    with {:ok, binding} <- GenServer.call(recording, request, 1_000),
         {:ok, subscriptions} <- collect(binding.subscriptions, &Subscription.readiness/1),
         {:ok, writers} <- collect(binding.handles, &writer_readiness(binding.writer, &1)) do
      interval = interval(subscriptions)
      results = subscriptions ++ writers

      resource = %{
        binding.resource
        | configuration: signature(binding, results),
          policy_interval: interval
      }

      dependencies = for {%Resource{} = dependency, _status} <- results, do: dependency
      status = status(binding, interval, results)

      with :ok <- confirm(recording, binding, resource, status, dependencies),
           do: {:ok, resource, status, dependencies}
    else
      _unavailable -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp confirm(recording, %{preparation_token: token} = binding, resource, status, dependencies),
    do:
      GenServer.call(
        recording,
        {:confirm_prepared_recording, token, binding, resource, status, dependencies},
        1_000
      )

  defp confirm(_recording, _binding, _resource, _status, _dependencies), do: :ok

  def binding(state) do
    streams = state.streams |> Enum.sort() |> Enum.map(&elem(&1, 1))
    selections = Enum.map(streams, &{&1.subscription.id, required_modes(&1)})

    handles =
      Enum.flat_map(streams, fn stream ->
        Enum.map(required_modes(stream), fn mode ->
          case Map.fetch(stream.outputs, mode) do
            {:ok, output} -> output.writer_handle
            :error -> :missing
          end
        end)
      end)

    %{
      resource: state.readiness_resource,
      writer: state.configuration.writer,
      handles: handles,
      selections: selections,
      subscriptions: Enum.map(streams, & &1.subscription),
      tracks_ready?: Enum.all?(streams, &(&1.target == :full_mix or &1.required_modes != nil)),
      tracks_required?: Enum.any?(streams, &(&1.target != :full_mix)),
      prepared_interval: state.prepared_interval
    }
  end

  defp required_modes(%{required_modes: nil, target: :full_mix}), do: [:full_mix]
  defp required_modes(%{required_modes: nil}), do: []
  defp required_modes(stream), do: Enum.sort(stream.required_modes)

  defp collect(values, callback) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, results} ->
      case callback.(value) do
        {:ok, resource, status} when status in [:ready, :preparing, :failed] ->
          {:cont, {:ok, results ++ [{resource, status}]}}

        _unavailable ->
          {:halt, {:error, :unavailable}}
      end
    end)
  end

  defp writer_readiness(_writer, :missing), do: {:ok, nil, :preparing}

  defp writer_readiness(writer, handle) do
    if function_exported?(writer, :readiness, 1),
      do: validate_writer_report(writer.readiness(handle)),
      else: {:ok, nil, :failed}
  rescue
    _exception -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end

  defp validate_writer_report(
         {:ok, %Resource{kind: :recording_writer} = resource, status} = report
       )
       when status in [:ready, :preparing, :failed] do
    if Resource.bound?(resource), do: report, else: {:ok, nil, :failed}
  end

  defp validate_writer_report({:error, :unavailable} = error), do: error
  defp validate_writer_report(_invalid), do: {:ok, nil, :failed}

  defp interval(results) do
    case Enum.uniq_by(results, fn {resource, _status} -> resource.policy_interval end) do
      [{resource, _status}] -> resource.policy_interval
      _inconsistent -> nil
    end
  end

  defp signature(binding, results) do
    resources =
      Enum.map(results, fn
        {nil, _status} -> nil
        {resource, _status} -> %{resource | policy_interval: nil}
      end)

    Resource.signature({binding.resource.configuration, binding.selections, resources})
  end

  defp status(binding, interval, results) do
    statuses = Enum.map(results, &elem(&1, 1))

    cond do
      :failed in statuses or not function_exported?(binding.writer, :readiness, 1) -> :failed
      :preparing in statuses or not binding.tracks_ready? or is_nil(interval) -> :preparing
      binding.tracks_required? and binding.prepared_interval != interval -> :preparing
      true -> :ready
    end
  end
end
