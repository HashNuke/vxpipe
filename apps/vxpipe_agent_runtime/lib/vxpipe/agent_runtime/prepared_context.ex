defmodule Vxpipe.AgentRuntime.PreparedContext do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{CompactionResult, Conversation, ModelRequest}

  @enforce_keys [:conversation, :request, :input_tokens, :compaction]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          conversation: Conversation.t(),
          request: ModelRequest.t(),
          input_tokens: non_neg_integer(),
          compaction: CompactionResult.t() | nil
        }
end
