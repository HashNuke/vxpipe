defmodule Vxpipe.Calls.CallSpecPage do
  @moduledoc "One bounded page of a tenant's call spec summaries."

  alias Vxpipe.Calls.{CallSpecSummary, Tenant}

  @enforce_keys [:tenant, :call_specs, :page, :page_size, :total, :total_pages]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant: Tenant.t(),
          call_specs: [CallSpecSummary.t()],
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer(),
          total_pages: non_neg_integer()
        }
end
