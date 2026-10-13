defmodule Vxpipe.Identity.Audit do
  @moduledoc "Safe access-event construction. Never includes passwords, hashes, or tokens."

  @actions ~w(setup_completed login logout password_reset user_created user_updated
    user_disabled user_enabled role_created role_updated role_deleted session_revoked
    recovery_used setup_proof_consumed)a

  @spec event(atom(), map()) :: {:ok, map()} | {:error, :invalid_audit_event}
  def event(action, attrs) when action in @actions and is_map(attrs) do
    safe =
      attrs
      |> Map.take([:actor_user_public_id, :target_user_public_id, :target_role_public_id, :summary])
      |> Map.put(:action, Atom.to_string(action))

    {:ok, Map.put_new(safe, :summary, %{})}
  end

  def event(_, _), do: {:error, :invalid_audit_event}

  @spec sanitize_summary(map()) :: map()
  def sanitize_summary(summary) when is_map(summary) do
    drop = ~w(password password_confirmation current_password hash password_hash token bearer_token secret)a ++
      ~w(password password_confirmation current_password hash password_hash token bearer_token secret)

    Map.drop(summary, drop)
  end
end
