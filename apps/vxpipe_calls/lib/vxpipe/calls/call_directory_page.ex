defmodule Vxpipe.Calls.CallDirectoryPage do
  @moduledoc "One bounded page of tenant calls and bounded call spec filter options."

  alias Vxpipe.Calls.{CallDirectorySummary, CallSpecFilter, Tenant}

  @enforce_keys [
    :tenant,
    :call_specs,
    :call_specs_truncated,
    :selected_call_spec_id,
    :calls,
    :page,
    :page_size,
    :total,
    :total_pages
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant: Tenant.t(),
          call_specs: [CallSpecFilter.t()],
          call_specs_truncated: boolean(),
          selected_call_spec_id: String.t() | nil,
          calls: [CallDirectorySummary.t()],
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer(),
          total_pages: non_neg_integer()
        }
end
