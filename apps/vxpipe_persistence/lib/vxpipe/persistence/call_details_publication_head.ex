defmodule Vxpipe.Persistence.CallDetailsPublicationHead do
  @moduledoc false

  alias Vxpipe.Persistence.Schema.Call
  alias Vxpipe.Persistence.Schema.CallDetailsPublication, as: StoredPublication

  @spec advance(module(), Call.t(), StoredPublication.t()) :: :ok | {:error, term()}
  def advance(repo, call, candidate) do
    current = latest(repo, call.latest_details_publication_id)

    if newer?(candidate, current) do
      case repo.update(Call.latest_details_publication_changeset(call, candidate.id)) do
        {:ok, _call} -> :ok
        {:error, %Ecto.Changeset{}} -> {:error, :latest_publication_update_failed}
      end
    else
      :ok
    end
  end

  defp latest(_repo, nil), do: nil
  defp latest(repo, id), do: repo.get(StoredPublication, id)

  defp newer?(_candidate, nil), do: true

  defp newer?(candidate, current),
    do: DateTime.compare(candidate.recorded_at, current.recorded_at) == :gt
end
