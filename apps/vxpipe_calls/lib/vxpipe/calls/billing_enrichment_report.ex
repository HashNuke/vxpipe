defmodule Vxpipe.Calls.BillingEnrichmentReport do
  @moduledoc "Bounded outcome counts for one call's billing-enrichment pass."

  @enforce_keys [
    :call_id,
    :candidate_count,
    :lookup_count,
    :stored_count,
    :pending_count,
    :unsupported_count,
    :unavailable_count,
    :missing_reference_count
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          call_id: String.t(),
          candidate_count: non_neg_integer(),
          lookup_count: non_neg_integer(),
          stored_count: non_neg_integer(),
          pending_count: non_neg_integer(),
          unsupported_count: non_neg_integer(),
          unavailable_count: non_neg_integer(),
          missing_reference_count: non_neg_integer()
        }
end
