defmodule Vxpipe.Calls.PublicationWorkers do
  @moduledoc "Starts call-details delivery through the Calls-owned worker supervisor."

  alias Vxpipe.Calls.{
    CallDetailsPublication,
    CallDetailsSnapshot,
    PublicationJob,
    PublicationWorker
  }

  @default_supervisor Vxpipe.Calls.PublicationWorkerSupervisor

  @spec start(String.t(), String.t(), CallDetailsSnapshot.t(), keyword()) ::
          {:ok, pid(), :started | :existing} | {:error, term()}
  def start(tenant_key, call_id, %CallDetailsSnapshot{} = snapshot, options)
      when is_list(options) do
    with {:ok, job} <- PublicationJob.new(tenant_key, call_id, snapshot, options),
         {:ok, supervisor} <- supervisor(options) do
      start_child(supervisor, job)
    end
  end

  def start(_tenant_key, _call_id, _snapshot, _options),
    do: {:error, :invalid_publication_job}

  @spec resume(CallDetailsPublication.t(), keyword()) ::
          {:ok, pid(), :started | :existing} | {:error, term()}
  def resume(%CallDetailsPublication{} = publication, options) when is_list(options) do
    with {:ok, job} <- PublicationJob.resume(publication, options),
         {:ok, supervisor} <- supervisor(options) do
      start_child(supervisor, job)
    end
  end

  def resume(_publication, _options), do: {:error, :invalid_publication_job}

  defp start_child(supervisor, job) do
    case DynamicSupervisor.start_child(supervisor, {PublicationWorker, job}) do
      {:ok, worker} -> {:ok, worker, :started}
      {:error, {:already_started, worker}} -> {:ok, worker, :existing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp supervisor(options) do
    case Keyword.get(options, :publication_worker_supervisor, @default_supervisor) do
      value when is_atom(value) or is_pid(value) -> {:ok, value}
      _invalid -> {:error, :invalid_publication_worker_supervisor}
    end
  end
end
