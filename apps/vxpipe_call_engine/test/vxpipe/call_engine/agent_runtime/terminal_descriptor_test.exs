defmodule Vxpipe.CallEngine.AgentRuntime.TerminalDescriptorTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.AgentRuntime.ToolDescriptors
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.Tool.{Hangup, ParticipantTransfer}

  test "transfer and hangup aliases are typed terminal, ordinary tools are not" do
    transfer_binding = %ToolBinding{
      name: "transfer",
      type: :participant_transfer,
      conversation_mode: :blocking,
      transfer: %ParticipantTransfer.Binding{
        source_call_spec_key: "reception",
        source_participant_id: "participant-reception",
        source_activation_id: "activation-reception",
        targets: %{
          "sales" => %{
            call_spec_key: "sales",
            participant_id: "participant-sales",
            description: "Sales",
            reason_required: false
          }
        }
      }
    }

    hangup_alias = %ToolBinding{
      name: "end_call",
      type: :platform,
      conversation_mode: :blocking,
      action: Hangup
    }

    hangup_canonical = %ToolBinding{
      name: "hangup",
      type: :platform,
      conversation_mode: :blocking,
      action: Hangup
    }

    assert {:ok, [transfer_descriptor]} =
             ToolDescriptors.compile(%{"transfer" => transfer_binding})

    assert transfer_descriptor.terminal? == true

    assert {:ok, [alias_descriptor]} =
             ToolDescriptors.compile(%{"end_call" => hangup_alias})

    assert alias_descriptor.terminal? == true

    assert {:ok, [canonical_descriptor]} =
             ToolDescriptors.compile(%{"hangup" => hangup_canonical})

    assert canonical_descriptor.terminal? == true
  end
end
