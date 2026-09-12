defmodule Vxpipe.Calls.PublicationFinalizers do
  @moduledoc "Starts post-call assessment through the Calls-owned finalizer supervisor."

  alias Vxpipe.Calls.{PublicationFinalizer, PublicationFinalizerJob}

  @default_supervisor Vxpipe.Calls.PublicationFinalizerSupervisor

  @spec start(String.t(), String.t(), keyword()) ::
          {:ok, pid(), :started | :existing} | {:error, term()}
  def start(tenant_key, call_id, options) when is_list(options) do
    with {:ok, job} <- PublicationFinalizerJob.new(tenant_key, call_id, options),
         {:ok, supervisor} <- supervisor(options) do
      start_child(supervisor, job)
    end
  end

  def start(_tenant_key, _call_id, _options),
    do: {:error, :invalid_publication_finalizer}

  defp start_child(supervisor, job) do
    case DynamicSupervisor.start_child(supervisor, {PublicationFinalizer, job}) do
      {:ok, finalizer} -> {:ok, finalizer, :started}
      {:error, {:already_started, finalizer}} -> {:ok, finalizer, :existing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp supervisor(options) do
    case Keyword.get(options, :publication_finalizer_supervisor, @default_supervisor) do
      value when is_atom(value) or is_pid(value) -> {:ok, value}
      _invalid -> {:error, :invalid_publication_finalizer_supervisor}
    end
  end
end
