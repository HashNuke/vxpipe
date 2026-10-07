defmodule Vxpipe.CallEngine.Readiness.Watch do
  @moduledoc """
  Push notification of readiness changes from a resource owner to its collectors.

  Collectors subscribe to the process that owns a resource; the owner calls `changed/0`
  when its readiness status changes, so a collector re-probes at once instead of waiting
  for its next poll. The notification carries no status: collectors still probe through
  the resource's adapter, and polling remains the fallback for owners that never notify.
  """

  @registry Vxpipe.CallEngine.ReadinessWatchRegistry

  @spec subscribe(pid()) :: :ok
  def subscribe(instance) when is_pid(instance) do
    {:ok, _owner} = Registry.register(@registry, instance, nil)
    :ok
  end

  @spec unsubscribe(pid()) :: :ok
  def unsubscribe(instance) when is_pid(instance), do: Registry.unregister(@registry, instance)

  @doc "Tells every collector watching the calling process that its readiness changed."
  @spec changed() :: :ok
  def changed do
    instance = self()

    Registry.dispatch(@registry, instance, fn subscribers ->
      Enum.each(subscribers, fn {collector, nil} ->
        send(collector, {:vxpipe_readiness_resource_changed, instance})
      end)
    end)
  end
end
