defmodule Vxpipe.Calls.CallDirectoryPage do
  @moduledoc "One bounded page of tenant calls and bounded definition filter options."

  alias Vxpipe.Calls.{CallDirectorySummary, CallFilterDefinition, Tenant}

  @enforce_keys [
    :tenant,
    :definitions,
    :definitions_truncated,
    :selected_definition_id,
    :calls,
    :page,
    :page_size,
    :total,
    :total_pages
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant: Tenant.t(),
          definitions: [CallFilterDefinition.t()],
          definitions_truncated: boolean(),
          selected_definition_id: String.t() | nil,
          calls: [CallDirectorySummary.t()],
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer(),
          total_pages: non_neg_integer()
        }
end
