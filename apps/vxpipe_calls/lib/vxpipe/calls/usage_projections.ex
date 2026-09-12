defmodule Vxpipe.Calls.UsageProjections do
  @moduledoc "Database-neutral workflows for persisted usage observations and operator reports."

  alias Vxpipe.CallEngine.Usage.Observation
  alias Vxpipe.Calls.{Principal, Repositories, UsageReport}

  @spec store(Observation.t(), keyword()) :: {:ok, Observation.t()} | {:error, term()}
  def store(%Observation{} = observation, options) when is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :usage_repository) do
      Repositories.call(repository, :store_usage_observation, [observation])
    end
  end

  def store(_observation, _options), do: {:error, :invalid_usage_observation}

  @spec fetch_report(Principal.t(), String.t(), keyword()) ::
          {:ok, UsageReport.t()} | {:error, term()}
  def fetch_report(%Principal{} = principal, call_id, options)
      when is_binary(call_id) and is_list(options) do
    with :ok <- authorize(principal),
         {:ok, repository} <- Repositories.fetch(options, :usage_repository),
         {:ok, amounts} <-
           Repositories.call(repository, :fetch_usage_amounts, [principal.tenant_key, call_id]) do
      UsageReport.new(amounts)
    end
  end

  def fetch_report(_principal, _call_id, _options), do: {:error, :invalid_usage_request}

  defp authorize(%Principal{scopes: scopes}) do
    if MapSet.member?(scopes, :calls), do: :ok, else: {:error, :insufficient_scope}
  end
end
