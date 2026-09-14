defmodule Vxpipe.Gateway.Media.OutputArbiter.Readiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.Gateway.Media.OutputArbiter.PreparedRoom

  def readiness(output, selection \\ :private) do
    with {:ok, resource, status, _native} <- observe(output, selection),
         do: {:ok, resource, status}
  end

  def resources(output) do
    with {:ok, resource, _status, native} <- observe(output, :private),
         do: {:ok, [resource | if(native, do: [native], else: [])]}
  end

  def binding(state, :private) do
    {:ok,
     %{
       resource: state.readiness_resource,
       native: state.native,
       adapter: state.native_adapter,
       status: if(state.clearing? or state.draining?, do: :preparing, else: :ready)
     }}
  end

  def binding(%{binding: %{token: token} = room} = state, {:room, token}),
    do: room_binding(state, room)

  def binding(
        %{prepared_room: %{binding: %{token: token} = room} = pending} = state,
        {:room, token}
      ) do
    if PreparedRoom.valid?(state, pending),
      do: room_binding(state, room),
      else: {:error, :unavailable}
  end

  def binding(_state, _stale), do: {:error, :unavailable}

  defp room_binding(state, room) do
    {:ok, private} = binding(state, :private)

    resource = %{
      private.resource
      | kind: :room_output_binding,
        generation: room.token,
        configuration:
          Resource.signature({private.resource.configuration, room.caller, room.identity})
    }

    status = if state.pending_binding, do: :preparing, else: private.status
    {:ok, %{private | resource: resource, status: status}}
  end

  # Keep dependent calls out of the arbiter's receive loop and recheck its binding afterward.
  defp observe(output, selection) do
    with {:ok, binding} <- GenServer.call(output, {:readiness_binding, selection}, 1_000),
         {:ok, native, status} <- native_readiness(binding),
         {:ok, ^binding} <- GenServer.call(output, {:readiness_binding, selection}, 1_000) do
      resource = %{
        binding.resource
        | configuration: Resource.signature({binding.resource.configuration, native})
      }

      {:ok, resource, combine(binding.status, status), native}
    else
      _unavailable -> {:error, :unavailable}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp native_readiness(binding) do
    if is_atom(binding.adapter) and function_exported?(binding.adapter, :readiness, 1) do
      binding.adapter.readiness(binding.native) |> validate_native(binding)
    else
      {:ok, nil, :failed}
    end
  end

  defp validate_native({:ok, %Resource{kind: :audio_output} = native, status}, binding)
       when status in [:ready, :preparing, :failed] do
    if Resource.bound?(native) and native.instance == binding.native and
         native.scope == binding.resource.scope and native.binding == binding.resource.binding,
       do: {:ok, native, status},
       else: {:ok, nil, :failed}
  end

  defp validate_native({:error, :unavailable} = error, _binding), do: error
  defp validate_native(_invalid, _binding), do: {:ok, nil, :failed}

  defp combine(_own, :failed), do: :failed
  defp combine(:ready, :ready), do: :ready
  defp combine(_own, _native), do: :preparing
end
