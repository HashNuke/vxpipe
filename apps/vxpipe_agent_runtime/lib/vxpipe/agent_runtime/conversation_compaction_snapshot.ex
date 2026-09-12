defmodule Vxpipe.AgentRuntime.ConversationCompactionSnapshot do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Conversation.Entry

  @enforce_keys [:base_entries, :leading_entries, :selected_entries, :trailing_entries]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          base_entries: [Entry.t()],
          leading_entries: [Entry.t()],
          selected_entries: [Entry.t()],
          trailing_entries: [Entry.t()]
        }

  @spec retained_entries(t()) :: [Entry.t()]
  def retained_entries(%__MODULE__{} = snapshot) do
    snapshot.leading_entries ++ snapshot.trailing_entries
  end
end
