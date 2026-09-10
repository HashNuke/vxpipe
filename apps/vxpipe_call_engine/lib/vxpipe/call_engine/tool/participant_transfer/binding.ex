defmodule Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding do
  @moduledoc false

  @derive {Inspect, only: [:source_definition_key]}
  @enforce_keys [
    :source_definition_key,
    :source_participant_id,
    :source_activation_id,
    :targets
  ]
  defstruct @enforce_keys

  @type target :: %{
          required(:definition_key) => String.t(),
          required(:participant_id) => String.t(),
          required(:description) => nil | String.t()
        }

  @type t :: %__MODULE__{
          source_definition_key: String.t(),
          source_participant_id: String.t(),
          source_activation_id: String.t(),
          targets: %{required(String.t()) => target()}
        }
end
