defmodule Vxpipe.Persistence.CallPublicationReadiness do
  @moduledoc false

  def check(%{gateway_cleanup_required: true, gateway_cleanup_completed_at: nil}),
    do: {:error, :call_cleanup_pending}

  def check(%{state: state, ended_at: %DateTime{}}) when state in [:ended, :failed], do: :ok

  def check(%{gateway_cleanup_required: true}), do: {:error, :call_cleanup_pending}
  def check(_call), do: {:error, :call_not_ended}
end
