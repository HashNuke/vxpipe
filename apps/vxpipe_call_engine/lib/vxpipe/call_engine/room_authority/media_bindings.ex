defmodule Vxpipe.CallEngine.RoomAuthority.MediaBindings do
  @moduledoc "Binds room media authorities and registers their policy enforcers at startup."

  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.{ResolvedCallPlan, RoomMixer, TranscriptRouter}
  alias Vxpipe.CallEngine.MediaPolicy.Authority, as: MediaPolicyAuthority

  def bind_media_policy_authority(%CreateRoom{}, _incarnation_id), do: {:ok, nil}

  def bind_media_policy_authority(%ResolvedCallPlan{}, incarnation_id) do
    case MediaPolicyAuthority.whereis(incarnation_id) do
      authority when is_pid(authority) -> {:ok, authority}
      nil -> {:error, :media_policy_unavailable}
    end
  end

  def bind_transcript_router(%CreateRoom{}, _incarnation_id, nil), do: {:ok, nil}

  def bind_transcript_router(%ResolvedCallPlan{}, incarnation_id, media_policy_authority) do
    case TranscriptRouter.whereis(incarnation_id) do
      router when is_pid(router) ->
        case MediaPolicyAuthority.register_enforcer(media_policy_authority, router) do
          {:ok, _snapshot} -> {:ok, router}
          {:error, _reason} -> {:error, :media_policy_unavailable}
        end

      nil ->
        {:error, :transcript_router_unavailable}
    end
  end

  def bind_room_mixer(%CreateRoom{}, _incarnation_id, nil), do: {:ok, nil}

  def bind_room_mixer(%ResolvedCallPlan{}, incarnation_id, media_policy_authority) do
    case RoomMixer.whereis(incarnation_id) do
      mixer when is_pid(mixer) ->
        case MediaPolicyAuthority.register_enforcer(media_policy_authority, mixer) do
          {:ok, _snapshot} -> {:ok, mixer}
          {:error, _reason} -> {:error, :media_policy_unavailable}
        end

      nil ->
        {:error, :room_mixer_unavailable}
    end
  end
end
