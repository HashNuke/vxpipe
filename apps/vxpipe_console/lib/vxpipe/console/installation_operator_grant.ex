defmodule Vxpipe.Console.InstallationOperatorGrant do
  @moduledoc "The single installation-wide authority established by local operator login."

  @enforce_keys [:issued_at_unix, :expires_at_unix]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          issued_at_unix: non_neg_integer(),
          expires_at_unix: pos_integer()
        }
end
