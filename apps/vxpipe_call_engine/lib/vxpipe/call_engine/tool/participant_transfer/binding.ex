defmodule Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding do
  @moduledoc false

  @derive {Inspect, only: [:source_call_spec_key]}
  @enforce_keys [
    :source_call_spec_key,
    :source_participant_id,
    :source_activation_id,
    :targets
  ]
  # Digest of the sender's before_outgoing_transfer questions at plan time
  # (nil when none are configured). The execution gate fails closed when a
  # digest is present but no verdict can be produced or consumed.
  defstruct @enforce_keys ++
              [
                guardrails_policy_digest: nil,
                guardrails_policy_revision: nil
              ]

  @type target :: %{
          required(:call_spec_key) => String.t(),
          required(:participant_id) => String.t(),
          required(:description) => nil | String.t(),
          required(:reason_required) => boolean()
        }

  @type t :: %__MODULE__{
          source_call_spec_key: String.t(),
          source_participant_id: String.t(),
          source_activation_id: String.t(),
          targets: %{required(String.t()) => target()},
          guardrails_policy_digest: nil | binary(),
          guardrails_policy_revision: nil | non_neg_integer()
        }
end
