defmodule Vxpipe.Gateway.Session.Snapshot do
  @moduledoc """
  The public, time-bounded gateway binding used to start one transport connection.
  """

  @enforce_keys [
    :session_id,
    :tenant_id,
    :actor_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :tool_visibility,
    :expires_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          session_id: String.t(),
          tenant_id: String.t(),
          actor_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          tool_visibility: Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility.t(),
          expires_at: DateTime.t()
        }

  @spec to_public(t()) :: map()
  def to_public(%__MODULE__{} = snapshot) do
    %{
      "session_id" => snapshot.session_id,
      "room_id" => snapshot.room_id,
      "incarnation_id" => snapshot.incarnation_id,
      "participant_id" => snapshot.participant_id,
      "expires_at" => DateTime.to_iso8601(snapshot.expires_at)
    }
  end
end
