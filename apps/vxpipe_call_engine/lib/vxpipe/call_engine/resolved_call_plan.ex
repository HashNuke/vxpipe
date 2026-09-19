defmodule Vxpipe.CallEngine.ResolvedCallPlan do
  @moduledoc """
  A self-contained immutable call plan pinned before live room startup.
  """

  alias Vxpipe.CallEngine.CallSpec.TransferPolicy

  alias Vxpipe.CallEngine.ResolvedCallPlan.{
    CallVariables,
    Capabilities,
    MediaPolicy,
    Participant,
    ToolBinding,
    ToolVisibility
  }

  @enforce_keys [
    :call_spec_id,
    :call_spec_revision,
    :schema_version,
    :tenant_id,
    :actor_id,
    :call_id,
    :room_id,
    :transport,
    :entry_caller,
    :entry_receiver,
    :opening_audio,
    :media_policy,
    :participants,
    :transfer_policy,
    :call_variables,
    :tool_visibility,
    :max_duration_ms
  ]
  defstruct @enforce_keys ++
              [
                credential_bindings: nil,
                wait_sounds: %Vxpipe.CallEngine.CallSpec.WaitSounds{},
                wait_sound_assets: nil
              ]

  # Safe external-term decoding can only use atoms already loaded in the VM.
  # These fixed data and enum owners describe the plan; never load names from stored bytes.
  @data_modules [
    __MODULE__,
    Participant,
    Capabilities,
    MediaPolicy,
    ToolBinding,
    ToolVisibility,
    CallVariables,
    Vxpipe.CallEngine.ResolvedCallPlan.OpeningAudio,
    Vxpipe.CallEngine.ResolvedCallPlan.VariableSection,
    Vxpipe.CallEngine.CallSpec.Participant,
    Vxpipe.CallEngine.CallSpec.ConnectionIntent,
    Vxpipe.CallEngine.CallSpec.NumberFromVariable,
    Vxpipe.CallEngine.CallSpec.CapabilitySelection,
    Vxpipe.CallEngine.CallSpec.ToolSelection,
    Vxpipe.CallEngine.CallSpec.ToolVisibility,
    Vxpipe.CallEngine.CallSpec.OpeningAudio,
    Vxpipe.CallEngine.CallSpec.TransferHistory,
    TransferPolicy,
    Vxpipe.CallEngine.CallSpec.VariablePermissions,
    Vxpipe.CallEngine.CallSpec.WaitSounds,
    Vxpipe.CallEngine.RemoteMCP.ResolvedTool,
    Vxpipe.CallEngine.WaitSounds.PreparedAssets,
    Vxpipe.CallEngine.OpeningAudio.Asset,
    Vxpipe.CallEngine.OpeningAudio.WaveDecoder,
    Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding,
    Vxpipe.CallEngine.Telephony.ServiceReference,
    Vxpipe.CallEngine.CallSpecCompiler,
    JSV.Root,
    JSV.Subschema,
    JSV.BooleanSchema,
    JSV.Ref,
    JSV.Vocabulary.V202012.Validation,
    JSV.Vocabulary.V202012.Applicator,
    MapSet
  ]

  @doc false
  def ensure_data_loaded!, do: Enum.each(@data_modules, &Code.ensure_loaded!/1)

  @type t :: %__MODULE__{
          call_spec_id: String.t(),
          call_spec_revision: pos_integer(),
          schema_version: String.t(),
          tenant_id: String.t(),
          credential_bindings: nil | %{{String.t(), String.t()} => map()},
          actor_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          transport: :web,
          entry_caller: String.t(),
          entry_receiver: String.t(),
          opening_audio: nil | Vxpipe.CallEngine.ResolvedCallPlan.OpeningAudio.t(),
          wait_sounds: Vxpipe.CallEngine.CallSpec.WaitSounds.t(),
          wait_sound_assets: Vxpipe.CallEngine.WaitSounds.PreparedAssets.t() | nil,
          media_policy: MediaPolicy.t(),
          participants: %{String.t() => Participant.t()},
          transfer_policy: TransferPolicy.t(),
          call_variables: CallVariables.t(),
          tool_visibility: ToolVisibility.t(),
          max_duration_ms: pos_integer()
        }
end
