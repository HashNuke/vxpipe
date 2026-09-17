defmodule Vxpipe.Calls.UsageProjections do
  @moduledoc "Database-neutral workflows for persisted usage observations and operator reports."

  alias Vxpipe.CallEngine.Usage.Observation
  alias Vxpipe.Calls.{CallReadAccess, Repositories, UsageReport}

  @spec store(Observation.t(), keyword()) :: {:ok, Observation.t()} | {:error, term()}
  def store(%Observation{} = observation, options) when is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :usage_repository) do
      Repositories.call(repository, :store_usage_observation, [observation])
    end
  end

  def store(_observation, _options), do: {:error, :invalid_usage_observation}

  @spec fetch_report(CallReadAccess.authority(), String.t(), keyword()) ::
          {:ok, UsageReport.t()} | {:error, term()}
  def fetch_report(authority, call_id, options)
      when is_binary(call_id) and is_list(options) do
    with {:ok, tenant_key} <- CallReadAccess.tenant_key(authority, :invalid_usage_request),
         {:ok, repository} <- Repositories.fetch(options, :usage_repository),
         {:ok, amounts} <-
           Repositories.call(repository, :fetch_usage_amounts, [tenant_key, call_id]) do
      UsageReport.new(amounts)
    end
  end

  def fetch_report(_principal, _call_id, _options), do: {:error, :invalid_usage_request}

end
