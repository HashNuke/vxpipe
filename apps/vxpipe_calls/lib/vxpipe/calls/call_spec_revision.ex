defmodule Vxpipe.Calls.CallSpecRevision do
  @moduledoc "An immutable stored source revision and reusable validation metadata."

  alias Vxpipe.Calls.{ParticipantRoute, TelephonyRoute}

  @enforce_keys [
    :tenant_key,
    :call_spec_id,
    :revision,
    :schema_version,
    :source,
    :source_digest,
    :compiled_metadata,
    :validation_errors,
    :routes,
    :telephony_routes,
    :published_at,
    :inserted_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_key: String.t(),
          call_spec_id: String.t(),
          revision: pos_integer(),
          schema_version: String.t(),
          source: map(),
          source_digest: String.t(),
          compiled_metadata: map(),
          validation_errors: [map()],
          routes: [ParticipantRoute.t()],
          telephony_routes: [TelephonyRoute.t()],
          published_at: nil | DateTime.t(),
          inserted_at: DateTime.t()
        }
end
