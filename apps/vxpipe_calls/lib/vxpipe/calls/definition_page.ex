defmodule Vxpipe.Calls.DefinitionPage do
  @moduledoc "One bounded page of a tenant's call-definition summaries."

  alias Vxpipe.Calls.{DefinitionSummary, Tenant}

  @enforce_keys [:tenant, :definitions, :page, :page_size, :total, :total_pages]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant: Tenant.t(),
          definitions: [DefinitionSummary.t()],
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer(),
          total_pages: non_neg_integer()
        }
end
