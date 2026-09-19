defmodule Vxpipe.Calls.AdminRepository do
  @moduledoc "Persistence port for bounded installation-operator reads."

  alias Vxpipe.Calls.{
    CallDirectorySummary,
    CallSpecFilter,
    CallSpecSummary,
    ProviderCredential,
    TelephonyService,
    Tenant
  }

  @type context :: term()

  @callback list_tenants(context(), pos_integer(), non_neg_integer()) ::
              {:ok, {[Tenant.t()], non_neg_integer()}} | {:error, term()}

  @callback list_call_specs(context(), String.t(), pos_integer(), non_neg_integer()) ::
              {:ok, {Tenant.t(), [CallSpecSummary.t()], non_neg_integer()}} | {:error, term()}

  @callback list_calls(
              context(),
              String.t(),
              String.t() | nil,
              pos_integer(),
              non_neg_integer()
            ) ::
              {:ok,
               {Tenant.t(), [CallSpecFilter.t()], boolean(), [CallDirectorySummary.t()],
                non_neg_integer()}}
              | {:error, term()}

  @callback list_services(context(), String.t()) ::
              {:ok, {Tenant.t(), [ProviderCredential.t()], [TelephonyService.t()], boolean()}}
              | {:error, term()}

  @doc "At most 100 scoped applications and 500 current published routes, with untruncated ambiguity counts."
  @callback list_telephony_applications(context(), String.t()) ::
              {:ok, {Tenant.t(), [TelephonyService.t()], [map()], boolean()}} | {:error, term()}
  @optional_callbacks list_telephony_applications: 2

  @callback fetch_call_context(context(), String.t(), String.t()) ::
              {:ok, {Tenant.t(), CallDirectorySummary.t()}} | {:error, term()}
end
