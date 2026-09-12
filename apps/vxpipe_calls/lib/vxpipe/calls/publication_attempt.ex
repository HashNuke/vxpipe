defmodule Vxpipe.Calls.PublicationAttempt do
  @moduledoc "Runs one reserve, immutable-object write, and publication-commit attempt."

  alias Vxpipe.Calls.{
    CallDetailsObject,
    CallDetailsPublication,
    CallDetailsSnapshot,
    PublicationJob,
    Repositories
  }

  @type outcome ::
          {:ok, CallDetailsPublication.t(), :published | :already_published} | {:error, term()}

  @spec run(PublicationJob.t()) :: outcome()
  def run(%PublicationJob{} = job) do
    with {:ok, %CallDetailsPublication{} = publication, _disposition} <- reserve(job) do
      deliver(job, publication)
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_publication_repository_response}
    end
  end

  defp reserve(%PublicationJob{source: %CallDetailsSnapshot{} = snapshot} = job) do
    Repositories.call(job.repository, :reserve, [job.tenant_key, job.call_id, snapshot])
  end

  defp reserve(%PublicationJob{source: %CallDetailsPublication{} = publication}),
    do: {:ok, publication, :existing}

  defp deliver(_job, %CallDetailsPublication{status: :published} = publication),
    do: {:ok, publication, :already_published}

  defp deliver(job, %CallDetailsPublication{status: :pending} = publication) do
    with {:ok, %CallDetailsObject{} = object} <- write(job.artifact_writer, publication),
         {:ok, %CallDetailsPublication{status: :published} = published} <-
           commit(job, publication, object) do
      {:ok, published, :published}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_publication_delivery_response}
    end
  end

  defp write({module, context}, publication), do: module.write(context, publication)

  defp commit(job, publication, object) do
    Repositories.call(job.repository, :mark_published, [
      job.tenant_key,
      job.call_id,
      publication.id,
      object
    ])
  end
end
