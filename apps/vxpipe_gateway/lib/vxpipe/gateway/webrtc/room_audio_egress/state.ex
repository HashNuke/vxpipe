defmodule Vxpipe.Gateway.WebRTC.RoomAudioEgress.State do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.Gateway.WebRTC.{ConnectionPeerSupervisor, RoomAudioOutputPipeline}

  @enforce_keys [
    :attachment,
    :connection_id,
    :drain_pending?,
    :engine,
    :identity,
    :in_flight,
    :owner,
    :peer_connection,
    :pipeline,
    :pipeline_generation,
    :pipeline_id,
    :pipeline_monitor,
    :pipeline_options,
    :pipeline_pid,
    :pipeline_ready?,
    :pipeline_supervisor,
    :policy,
    :subscription,
    :subscription_id,
    :track_id
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          attachment: term(),
          connection_id: String.t(),
          drain_pending?: boolean(),
          engine: module(),
          identity: map(),
          in_flight: {String.t(), non_neg_integer()} | nil,
          owner: pid(),
          peer_connection: pid(),
          pipeline: module(),
          pipeline_generation: non_neg_integer(),
          pipeline_id: String.t() | nil,
          pipeline_monitor: reference() | nil,
          pipeline_options: keyword(),
          pipeline_pid: pid() | nil,
          pipeline_ready?: boolean(),
          pipeline_supervisor: module(),
          policy: Snapshot.t() | nil,
          subscription: term() | nil,
          subscription_id: String.t(),
          track_id: String.t()
        }

  @spec new(keyword()) :: t()
  def new(options) do
    connection_id = Keyword.fetch!(options, :connection_id)

    %__MODULE__{
      attachment: Keyword.fetch!(options, :attachment),
      connection_id: connection_id,
      drain_pending?: false,
      engine: Keyword.get(options, :engine, Vxpipe.CallEngine),
      identity: %{
        tenant_id: Keyword.fetch!(options, :tenant_id),
        room_id: Keyword.fetch!(options, :room_id),
        incarnation_id: Keyword.fetch!(options, :incarnation_id),
        participant_id: Keyword.fetch!(options, :participant_id)
      },
      in_flight: nil,
      owner: Keyword.fetch!(options, :owner),
      peer_connection: Keyword.fetch!(options, :peer_connection),
      pipeline: Keyword.get(options, :pipeline, RoomAudioOutputPipeline),
      pipeline_generation: 0,
      pipeline_id: nil,
      pipeline_monitor: nil,
      pipeline_options: Keyword.get(options, :pipeline_options, []),
      pipeline_pid: nil,
      pipeline_ready?: false,
      pipeline_supervisor: Keyword.get(options, :pipeline_supervisor, ConnectionPeerSupervisor),
      policy: nil,
      subscription: nil,
      subscription_id: "#{connection_id}:room-output",
      track_id: Keyword.fetch!(options, :track_id)
    }
  end
end
