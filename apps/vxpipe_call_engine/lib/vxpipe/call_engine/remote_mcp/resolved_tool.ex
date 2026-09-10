defmodule Vxpipe.CallEngine.RemoteMCP.ResolvedTool do
  @moduledoc """
  Public descriptor and safe generation identity pinned into one call plan.
  """

  @enforce_keys [
    :scope,
    :integration_id,
    :configuration_generation,
    :credential_generation,
    :catalog_generation,
    :remote_name,
    :description,
    :input_schema,
    :invocation_deadline_ms,
    :maximum_result_bytes
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          scope: :application | {:tenant, String.t()},
          integration_id: String.t(),
          configuration_generation: String.t(),
          credential_generation: String.t(),
          catalog_generation: String.t(),
          remote_name: String.t(),
          description: String.t(),
          input_schema: map(),
          invocation_deadline_ms: pos_integer(),
          maximum_result_bytes: pos_integer()
        }
end
