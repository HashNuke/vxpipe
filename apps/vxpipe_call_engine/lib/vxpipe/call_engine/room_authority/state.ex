defmodule Vxpipe.CallEngine.RoomAuthority.State do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{FirstMessage, OpeningAudio, SpokenHistory}

  @enforce_keys [
    :archive_recorder,
    :call_lifecycle,
    :first_message,
    :media_policy_authority,
    :opening_audio,
    :room_mixer,
    :transcript_router,
    :snapshot,
    :spoken_history,
    :speech_to_text_runtime,
    :startup_ready?,
    :text_capability_required?
  ]
  defstruct @enforce_keys ++
              [
                connection_monitors: %{},
                connections: %{},
                participant_transfer_runtime: nil,
                activated_agent_participant_ids: MapSet.new(),
                pending_participant_transfer: nil,
                agent_turns: %{},
                background_tool_calls: %{},
                pending_agent_teardowns: %{},
                pending_connection_promotions: %{},
                next_sequence: 1,
                participant_monitors: %{},
                participant_supervisors: %{},
                participant_ids: MapSet.new(),
                participant_roles: %{},
                readiness_options: [],
                speech_to_text_monitors: %{},
                text_capability: nil,
                text_to_speech_capability: nil,
                text_to_speech_runtime: nil
              ]

  @type t :: %__MODULE__{
          archive_recorder: Recorder.t(),
          participant_transfer_runtime:
            nil | Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Runtime.t(),
          activated_agent_participant_ids: MapSet.t(String.t()),
          call_lifecycle: nil | pid(),
          connection_monitors: %{optional(reference()) => String.t()},
          connections: map(),
          first_message: FirstMessage.t(),
          media_policy_authority: nil | pid(),
          agent_turns: map(),
          background_tool_calls: map(),
          next_sequence: pos_integer(),
          opening_audio: OpeningAudio.t(),
          room_mixer: nil | pid(),
          transcript_router: nil | pid(),
          pending_participant_transfer:
            nil
            | Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Pending.t()
            | Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Restoration.t(),
          pending_agent_teardowns: %{optional(pid()) => map()},
          pending_connection_promotions: %{optional(String.t()) => map()},
          participant_monitors: %{optional(reference()) => String.t()},
          participant_supervisors: %{optional(String.t()) => pid()},
          participant_ids: MapSet.t(String.t()),
          participant_roles: %{optional(String.t()) => atom()},
          readiness_options: keyword(),
          snapshot: Snapshot.t(),
          spoken_history: SpokenHistory.t(),
          speech_to_text_runtime: :application | map(),
          startup_ready?: boolean(),
          text_capability_required?: boolean(),
          speech_to_text_monitors: %{optional(reference()) => String.t()},
          text_capability: nil | map(),
          text_to_speech_capability: nil | map(),
          text_to_speech_runtime: nil | Vxpipe.CallEngine.TextToSpeechRuntime.t()
        }

  @spec new(
          Recorder.t(),
          Snapshot.t(),
          :application | map(),
          OpeningAudio.t(),
          FirstMessage.t(),
          nil | pid(),
          nil | pid(),
          nil | pid(),
          nil | pid()
        ) :: t()
  def new(
        %Recorder{} = archive_recorder,
        %Snapshot{} = snapshot,
        speech_to_text_runtime,
        %OpeningAudio{} = opening_audio \\ OpeningAudio.open(),
        %FirstMessage{} = first_message \\ FirstMessage.completed(),
        call_lifecycle \\ nil,
        media_policy_authority \\ nil,
        transcript_router \\ nil,
        room_mixer \\ nil
      ) do
    %__MODULE__{
      archive_recorder: archive_recorder,
      call_lifecycle: call_lifecycle,
      first_message: first_message,
      media_policy_authority: media_policy_authority,
      opening_audio: opening_audio,
      room_mixer: room_mixer,
      transcript_router: transcript_router,
      snapshot: snapshot,
      spoken_history: SpokenHistory.new(),
      speech_to_text_runtime: speech_to_text_runtime,
      startup_ready?: is_nil(call_lifecycle),
      text_capability_required?: true
    }
  end
end
