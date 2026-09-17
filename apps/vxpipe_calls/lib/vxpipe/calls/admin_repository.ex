defmodule Vxpipe.Calls.AdminRepository do
  @moduledoc "Persistence port for bounded installation-operator reads."

  alias Vxpipe.Calls.{DefinitionSummary, Tenant}

  @type context :: term()

  @callback list_tenants(context(), pos_integer(), non_neg_integer()) ::
              {:ok, {[Tenant.t()], non_neg_integer()}} | {:error, term()}

  @callback list_definitions(context(), String.t(), pos_integer(), non_neg_integer()) ::
              {:ok, {Tenant.t(), [DefinitionSummary.t()], non_neg_integer()}} | {:error, term()}
end
