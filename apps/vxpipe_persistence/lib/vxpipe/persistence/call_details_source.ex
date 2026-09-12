defmodule Vxpipe.Persistence.CallDetailsSource do
  @moduledoc "Builds tenant-scoped call-details assessments from one coherent PostgreSQL snapshot."

  @behaviour Vxpipe.Calls.PublicationSource

  alias Vxpipe.Persistence.{CallDetailsSourceProjection, CallDetailsSourceStore}

  @impl true
  def read(options, tenant_key, call_id)
      when is_list(options) and is_binary(tenant_key) and tenant_key != "" and
             is_binary(call_id) and call_id != "" do
    with repo when is_atom(repo) <- Keyword.get(options, :repo),
         recording when recording in [:configured, :unconfigured] <-
           Keyword.get(options, :recording, :unconfigured) do
      transaction(repo, tenant_key, call_id, recording)
    else
      _invalid -> {:error, :invalid_call_details_source_configuration}
    end
  end

  def read(_options, _tenant_key, _call_id),
    do: {:error, :invalid_call_details_source_configuration}

  defp transaction(repo, tenant_key, call_id, recording) do
    repo.transaction(
      fn ->
        with {:ok, read} <- CallDetailsSourceStore.read(repo, tenant_key, call_id),
             {:ok, assessment} <- CallDetailsSourceProjection.project(read, recording) do
          assessment
        else
          {:error, reason} -> repo.rollback(reason)
        end
      end,
      isolation: :repeatable_read
    )
    |> case do
      {:ok, assessment} -> {:ok, assessment}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _error -> {:error, :call_details_source_unavailable}
  catch
    :exit, _reason -> {:error, :call_details_source_unavailable}
  end
end
