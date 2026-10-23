defmodule Vxpipe.Gateway.TestCleanupCompletionRepository do
  @moduledoc false

  alias Vxpipe.Calls.PreparedCall

  def complete_call_cleanup(observer, binding, completed_at) do
    send(observer, {:complete_cleanup, self(), binding, completed_at})

    receive do
      :complete ->
        {:ok, completed_call(binding, completed_at)}

      :unavailable ->
        {:error, :storage_unavailable}

      :commit_then_die ->
        send(observer, {:cleanup_committed, binding, completed_at})
        Process.exit(self(), :kill)
    end
  end

  def completed_call(binding, completed_at) do
    struct(PreparedCall,
      id: binding.call_id,
      tenant_key: binding.tenant_key,
      room_id: binding.room_id,
      incarnation_id: binding.incarnation_id,
      gateway_cleanup_required: true,
      gateway_cleanup_completed_at: completed_at
    )
  end
end
