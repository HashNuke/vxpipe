defmodule Vxpipe.CallEngine.RoomAuthority.State do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Room.Snapshot

  @enforce_keys [:archive_recorder, :snapshot, :speech_to_text_runtime]
  defstruct @enforce_keys ++
              [
                connection_monitors: %{},
                connections: %{},
                agent_turns: %{},
                background_tool_calls: %{},
                next_sequence: 1,
                participant_monitors: %{},
                participant_ids: MapSet.new(),
                participant_roles: %{},
                speech_to_text_monitors: %{},
                text_capability: nil,
                text_to_speech_capability: nil
              ]

  @type t :: %__MODULE__{
          archive_recorder: Recorder.t(),
          connection_monitors: %{optional(reference()) => String.t()},
          connections: map(),
          agent_turns: map(),
          background_tool_calls: map(),
          next_sequence: pos_integer(),
          participant_monitors: %{optional(reference()) => String.t()},
          participant_ids: MapSet.t(String.t()),
          participant_roles: %{optional(String.t()) => atom()},
          snapshot: Snapshot.t(),
          speech_to_text_runtime: :application | map(),
          speech_to_text_monitors: %{optional(reference()) => String.t()},
          text_capability: nil | map(),
          text_to_speech_capability: nil | map()
        }

  @spec new(Recorder.t(), Snapshot.t(), :application | map()) :: t()
  def new(%Recorder{} = archive_recorder, %Snapshot{} = snapshot, speech_to_text_runtime) do
    %__MODULE__{
      archive_recorder: archive_recorder,
      snapshot: snapshot,
      speech_to_text_runtime: speech_to_text_runtime
    }
  end
end
