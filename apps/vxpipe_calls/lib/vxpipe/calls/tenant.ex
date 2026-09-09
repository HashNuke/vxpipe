defmodule Vxpipe.Calls.Tenant do
  @moduledoc "A tenant identity independent from persistence primary keys."

  @enforce_keys [:key, :name, :inserted_at]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          key: String.t(),
          name: String.t(),
          inserted_at: DateTime.t()
        }
end
