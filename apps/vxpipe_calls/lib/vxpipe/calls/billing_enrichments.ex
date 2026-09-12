defmodule Vxpipe.Calls.BillingEnrichments do
  @moduledoc "Coordinates bounded billing lookups and committed immutable usage enrichment."

  alias Vxpipe.Calls.{
    BillingCandidates,
    BillingEnrichmentReport,
    BillingLookupResult,
    BillingObservation,
    Principal,
    Repositories
  }

  @default_timeout 5_000
  @default_max_concurrency 4

  @spec enrich(Principal.t(), String.t(), keyword()) ::
          {:ok, BillingEnrichmentReport.t()} | {:error, term()}
  def enrich(%Principal{} = principal, call_id, options)
      when is_binary(call_id) and is_list(options) do
    with :ok <- authorize(principal),
         {:ok, settings} <- settings(options),
         {:ok, repository} <- Repositories.fetch(options, :usage_repository),
         {:ok, observations} <-
           Repositories.call(repository, :fetch_usage_observations, [
             principal.tenant_key,
             call_id
           ]),
         {:ok, candidates} <-
           BillingCandidates.build(observations, principal.tenant_key, call_id) do
      run(candidates, repository, call_id, settings)
    end
  end

  def enrich(_principal, _call_id, _options), do: {:error, :invalid_billing_enrichment_request}

  defp run(candidates, _repository, call_id, %{lookup: :unconfigured}) do
    {:ok, report(candidates, call_id, unsupported_count: length(candidates.requests))}
  end

  defp run(candidates, repository, call_id, settings) do
    initial = report(candidates, call_id, lookup_count: length(candidates.requests))

    candidates.requests
    |> Task.async_stream(&{&1, lookup(settings.lookup, &1)},
      ordered: true,
      max_concurrency: settings.max_concurrency,
      timeout: settings.timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({:ok, initial}, fn outcome, {:ok, report} ->
      case settle(outcome, repository, report) do
        {:ok, report} -> {:cont, {:ok, report}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp lookup({module, context}, request) do
    module.lookup(context, request)
  end

  defp settle(
         {:ok, {request, {:ok, %BillingLookupResult{} = result}}},
         repository,
         report
       ) do
    with {:ok, observation} <- BillingObservation.build(request, result),
         {:ok, _stored} <-
           Repositories.call(repository, :store_usage_observation, [observation]) do
      {:ok, increment(report, :stored_count)}
    end
  end

  defp settle({:ok, {_request, {:ok, :pending}}}, _repository, report),
    do: {:ok, increment(report, :pending_count)}

  defp settle({:ok, {_request, {:error, :unsupported}}}, _repository, report),
    do: {:ok, increment(report, :unsupported_count)}

  defp settle(_unavailable, _repository, report),
    do: {:ok, increment(report, :unavailable_count)}

  defp settings(options) do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])
    lookup = Keyword.get(options, :billing_lookup, Keyword.get(configured, :billing_lookup))
    timeout = Keyword.get(options, :billing_lookup_timeout, @default_timeout)

    max_concurrency =
      Keyword.get(options, :billing_lookup_max_concurrency, @default_max_concurrency)

    with {:ok, lookup} <- lookup(lookup),
         true <- is_integer(timeout) and timeout > 0,
         true <- is_integer(max_concurrency) and max_concurrency > 0 do
      {:ok, %{lookup: lookup, timeout: timeout, max_concurrency: max_concurrency}}
    else
      _invalid -> {:error, :billing_lookup_unavailable}
    end
  end

  defp lookup(nil), do: {:ok, :unconfigured}
  defp lookup({module, _context} = lookup) when is_atom(module), do: {:ok, lookup}
  defp lookup(_invalid), do: {:error, :billing_lookup_unavailable}

  defp authorize(%Principal{scopes: scopes}) do
    if MapSet.member?(scopes, :calls), do: :ok, else: {:error, :insufficient_scope}
  end

  defp report(candidates, call_id, overrides) do
    struct!(
      BillingEnrichmentReport,
      Keyword.merge(
        [
          call_id: call_id,
          candidate_count: candidates.candidate_count,
          lookup_count: 0,
          stored_count: 0,
          pending_count: 0,
          unsupported_count: 0,
          unavailable_count: candidates.unavailable_count,
          missing_reference_count: candidates.missing_reference_count
        ],
        overrides
      )
    )
  end

  defp increment(report, field), do: Map.update!(report, field, &(&1 + 1))
end
