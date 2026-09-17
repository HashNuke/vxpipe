defmodule Vxpipe.Calls.AdminRepository do
  @moduledoc "Persistence port for bounded installation-operator reads."

  alias Vxpipe.Calls.{
    CallDirectorySummary,
    CallFilterDefinition,
    DefinitionSummary,
    ProviderCredential,
    TelephonyService,
    Tenant
  }

  @type context :: term()

  @callback list_tenants(context(), pos_integer(), non_neg_integer()) ::
              {:ok, {[Tenant.t()], non_neg_integer()}} | {:error, term()}

  @callback list_definitions(context(), String.t(), pos_integer(), non_neg_integer()) ::
              {:ok, {Tenant.t(), [DefinitionSummary.t()], non_neg_integer()}} | {:error, term()}

  @callback list_calls(
              context(),
              String.t(),
              String.t() | nil,
              pos_integer(),
              non_neg_integer()
            ) ::
              {:ok,
               {Tenant.t(), [CallFilterDefinition.t()], boolean(), [CallDirectorySummary.t()],
                non_neg_integer()}}
              | {:error, term()}

  @callback list_services(context(), String.t()) ::
              {:ok, {Tenant.t(), [ProviderCredential.t()], [TelephonyService.t()], boolean()}}
              | {:error, term()}
end
