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
  defstruct @enforce_keys ++ [admission_owner: nil, cleanup_binding: nil]

  @type t :: %__MODULE__{
          session_id: String.t(),
          tenant_id: String.t(),
          actor_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          tool_visibility: Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility.t(),
          expires_at: DateTime.t(),
          admission_owner: pid() | nil,
          cleanup_binding: map() | nil
        }

  @doc false
  def cleanup_binding(%__MODULE__{cleanup_binding: nil}), do: {:ok, nil}

  def cleanup_binding(%__MODULE__{
        tenant_id: tenant,
        room_id: room,
        incarnation_id: incarnation,
        cleanup_binding:
          %{
            tenant_key: tenant,
            call_id: call,
            room_id: room,
            incarnation_id: incarnation
          } = binding
      })
      when map_size(binding) == 4 and is_binary(call) and byte_size(call) in 1..128,
      do: {:ok, binding}

  def cleanup_binding(%__MODULE__{}), do: {:error, :invalid_cleanup_binding}

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
