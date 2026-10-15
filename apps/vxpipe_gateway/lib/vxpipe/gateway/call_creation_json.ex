defmodule Vxpipe.Gateway.CallCreationJSON do
  @moduledoc "Public call-creation metadata, excluding the pinned plan and variables."

  def call(call) do
    %{
      id: call.id,
      call_spec_id: call.call_spec_id,
      revision: call.call_spec_revision,
      state: Atom.to_string(call.state),
      outgoing_outcome: call.outgoing_outcome && Atom.to_string(call.outgoing_outcome)
    }
  end
end
