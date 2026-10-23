defmodule Vxpipe.Gateway.Telephony.MediaCleanup do
  @moduledoc false

  alias Vxpipe.Gateway.{CallCleanup, CallCleanupSupervisor}
  alias Vxpipe.Gateway.Telephony.MediaBinding

  def lookup(binding) do
    case MediaBinding.cleanup_binding(binding) do
      {:ok, nil} -> {:ok, nil}
      {:ok, cleanup} -> CallCleanupSupervisor.lookup(cleanup)
      {:error, _reason} = error -> error
    end
  end

  def register(binding, kind) when kind in [:telephony_media, :telephony_socket] do
    with {:ok, tracker} <- lookup(binding),
         :ok <- register_root(tracker, kind) do
      {:ok, tracker}
    end
  catch
    :exit, _reason -> {:error, :cleanup_unavailable}
  end

  defp register_root(nil, _kind), do: :ok

  defp register_root(tracker, kind) do
    with :ok <- CallCleanup.register(tracker, kind, self()) do
      # Local media has no independent carrier or durable usage obligation.
      # Completion still requires orderly DOWN of the entire registered root.
      CallCleanup.acknowledge(tracker, self(), :complete)
    end
  end
end
