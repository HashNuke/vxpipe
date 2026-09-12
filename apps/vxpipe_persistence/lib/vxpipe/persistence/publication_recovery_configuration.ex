defmodule Vxpipe.Persistence.PublicationRecoveryConfiguration do
  @moduledoc false

  alias Vxpipe.Calls.{PublicationArtifactWriter, PublicationRecovery}

  alias Vxpipe.Persistence.{CallDetailsPublicationStore, Repo}

  @spec children(keyword()) ::
          {:ok, [Supervisor.child_spec() | {module(), keyword()}]}
          | {:error, :invalid_publication_recovery_configuration}
  def children(options) when is_list(options) do
    case Keyword.get(options, :enabled, false) do
      false -> {:ok, []}
      true -> enabled_children(options)
      _invalid -> {:error, :invalid_publication_recovery_configuration}
    end
  end

  def children(_options), do: {:error, :invalid_publication_recovery_configuration}

  defp enabled_children(options) do
    with {writer, _context} when is_atom(writer) <-
           Keyword.get(options, :publication_artifact_writer),
         true <- PublicationArtifactWriter.valid?(writer) do
      recovery_options =
        options
        |> Keyword.delete(:enabled)
        |> Keyword.put(
          :publication_repository,
          {CallDetailsPublicationStore, Repo}
        )

      {:ok, [{PublicationRecovery, recovery_options}]}
    else
      _invalid -> {:error, :invalid_publication_recovery_configuration}
    end
  end
end
