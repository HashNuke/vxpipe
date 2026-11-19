defmodule Vxpipe.Identity.Ports.DiagnosticsSettings do
  @moduledoc "Durable benchmark opt-in; adapters revalidate current session and built-in role."
  alias Vxpipe.Identity.Principal

  @type settings :: %{
          enabled: boolean(),
          revision: non_neg_integer(),
          updated_at: DateTime.t() | nil,
          updated_by: String.t() | nil
        }

  @callback fetch(Principal.t()) :: {:ok, settings()} | {:error, atom()}
  @callback update(Principal.t(), boolean(), non_neg_integer()) ::
              {:ok, settings()} | {:error, atom()}
end
