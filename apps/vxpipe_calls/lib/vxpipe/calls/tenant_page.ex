defmodule Vxpipe.Calls.TenantPage do
  @moduledoc "One bounded page of installation-visible tenants."

  alias Vxpipe.Calls.Tenant

  @enforce_keys [:tenants, :page, :page_size, :total, :total_pages]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenants: [Tenant.t()],
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer(),
          total_pages: non_neg_integer()
        }
end
