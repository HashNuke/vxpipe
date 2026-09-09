defmodule Vxpipe.Gateway.RTVI.ToolProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility
  alias Vxpipe.Gateway.RTVI.Codec

  @spec encode(struct(), ToolVisibility.t()) :: :hidden | {:ok, binary()}
  def encode(event, %ToolVisibility{} = policy) do
    participant_levels = Map.get(policy.overrides, event.participant_id, %{})
    level = Map.get(participant_levels, event.name, policy.default)

    case level do
      :hidden -> :hidden
      level when level in [:metadata, :full] -> Codec.encode_event(event, level)
    end
  end
end
