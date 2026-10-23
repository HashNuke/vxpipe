defmodule Vxpipe.Calls.ConfiguredSamples do
  @moduledoc "Actual-actor preparation of configured browser samples without ambient keys or runtime state."

  alias Vxpipe.CallEngine.CallSpec

  alias Vxpipe.Calls.{
    Admissions,
    CallClaims,
    CallManagementAuthorization,
    CallSpecAuthoring,
    CallSpecs,
    PreparedCall,
    Repositories
  }

  alias Vxpipe.Identity.Principal

  def prepare(actor, config, options \\ [])

  def prepare(%Principal{} = actor, %{tenant_key: tenant} = config, options)
      when is_list(options) do
    with :ok <- CallManagementAuthorization.authorize(actor, tenant),
         {:ok, source} <- source(config),
         :ok <- web_entry(source),
         {:ok, selected} <- ensure_spec(actor, tenant, source, options),
         {:ok, call} <-
           CallClaims.claim(
             actor,
             tenant,
             selected.call_spec_id,
             config.initial_variables,
             nil,
             nil,
             Keyword.put(options, :expected_call_spec_revision, selected.revision)
           ) do
      Admissions.issue_call_token(actor, tenant, call.id, nil, options)
    end
  end

  def prepare(_actor, _config, _options), do: {:error, :forbidden}

  def transfer(actor, config, tenant, call_id, options \\ [])

  def transfer(%Principal{} = actor, %{tenant_key: configured} = config, tenant, call_id, options)
      when is_list(options) do
    with :ok <- CallManagementAuthorization.authorize(actor, configured),
         :ok <- target(configured, tenant, call_id),
         {:ok, ref} <- transfer_ref(config),
         {:ok, source} <- source(config),
         {:ok, repository} <- Repositories.fetch(options, :call_spec_repository),
         {:ok, [id]} <-
           Repositories.call(repository, :find_by_original_name, [tenant, source["name"]]),
         {:ok, %PreparedCall{tenant_key: ^tenant, id: ^call_id, call_spec_id: ^id} = call} <-
           Admissions.fetch(tenant, call_id, options),
         {:ok, key} <- transfer_key(call, ref) do
      Admissions.issue_call_token(actor, tenant, call_id, key, options)
    else
      {:ok, _other} -> {:error, :not_found}
      error -> error
    end
  end

  def transfer(_actor, _config, _tenant, _call_id, _options), do: {:error, :forbidden}

  defp source(%{call_spec: source, initial_variables: variables})
       when is_map(source) and is_map(variables) do
    normalized = source |> JSON.encode!() |> JSON.decode!()

    case normalized["name"] do
      name when is_binary(name) and byte_size(name) in 1..256 -> {:ok, normalized}
      _invalid -> {:error, :invalid_sample_configuration}
    end
  end

  defp source(_config), do: {:error, :invalid_sample_configuration}

  defp web_entry(source) do
    with {:ok, spec} <- CallSpec.new(source, resource_id: "configured-sample", revision: 1),
         :incoming <- spec.direction,
         %{connection: %{service: :web, mode: :receive, admission: :start_call}} <-
           Map.fetch!(spec.participants, spec.entry_caller) do
      :ok
    else
      _invalid -> {:error, :invalid_sample_configuration}
    end
  end

  defp ensure_spec(actor, tenant, source, options) do
    :global.trans({{__MODULE__, tenant}, self()}, fn ->
      with {:ok, repository} <- Repositories.fetch(options, :call_spec_repository),
           {:ok, ids} <-
             Repositories.call(repository, :find_by_original_name, [tenant, source["name"]]) do
        ensure_revision(ids, actor, tenant, source, repository, options)
      end
    end)
  end

  defp ensure_revision([], actor, tenant, source, _repository, options) do
    with {:ok, draft} <- CallSpecAuthoring.save(actor, tenant, source, options),
         {:ok, published} <-
           CallSpecAuthoring.publish(actor, tenant, draft.call_spec_id, draft.revision, options) do
      {:ok, published}
    end
  end

  defp ensure_revision([id], actor, tenant, source, repository, options) do
    case Repositories.call(repository, :fetch_published_revision, [tenant, id]) do
      {:ok, %{tenant_key: ^tenant, call_spec_id: ^id, source: ^source} = published} ->
        {:ok, published}

      {:ok, _different} ->
        {:error, :sample_spec_conflict}

      {:error, :call_spec_not_published} ->
        publish_draft(actor, tenant, id, source, repository, options)

      error ->
        error
    end
  end

  defp ensure_revision(_ambiguous, _actor, _tenant, _source, _repository, _options),
    do: {:error, :sample_spec_conflict}

  defp publish_draft(actor, tenant, id, source, repository, options) do
    with {:ok, next} <- Repositories.call(repository, :next_revision, [tenant, id]),
         {:ok, %{tenant_key: ^tenant, call_spec_id: ^id, source: ^source} = draft} <-
           CallSpecs.fetch(tenant, id, next - 1, options),
         {:ok, published} <- CallSpecAuthoring.publish(actor, tenant, id, draft.revision, options) do
      {:ok, published}
    else
      {:ok, _different} -> {:error, :sample_spec_conflict}
      error -> error
    end
  end

  defp target(tenant, tenant, id) when is_binary(id) and byte_size(id) in 1..128, do: :ok

  defp target(_configured, tenant, id) when not is_binary(tenant) or not is_binary(id),
    do: {:error, :invalid_sample_target}

  defp target(_configured, _tenant, _id), do: {:error, :not_found}

  defp transfer_ref(%{transfer_participant: ref}) when is_binary(ref) and byte_size(ref) > 0,
    do: {:ok, ref}

  defp transfer_ref(_config), do: {:error, :disabled}

  defp transfer_key(call, ref) do
    with [{key, ^ref}] <-
           Enum.filter(call.participant_routes, fn {_key, participant} -> participant == ref end),
         %{connection: %{service: :web, mode: :receive, admission: :transfer}} <-
           Map.get(call.plan.participants, ref) do
      {:ok, key}
    else
      _invalid -> {:error, :participant_not_found}
    end
  end
end
