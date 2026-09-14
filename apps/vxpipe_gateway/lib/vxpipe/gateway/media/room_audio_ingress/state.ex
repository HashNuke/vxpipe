defmodule Vxpipe.Gateway.Media.RoomAudioIngress.State do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.Gateway.WebRTC.{AudioPipeline, ConnectionPeerSupervisor}

  @enforce_keys [
    :attachment,
    :connection_id,
    :clock,
    :configuration,
    :engine,
    :identity,
    :next_sequence_number,
    :owner,
    :readiness_resource,
    :pipeline,
    :pipeline_generation,
    :pipeline_id,
    :pipeline_monitor,
    :pipeline_options,
    :pipeline_pid,
    :pipeline_ready?,
    :pipeline_supervisor,
    :policy,
    :ready_waiters,
    :reject_received_through_ms
  ]
  defstruct @enforce_keys ++ [pending_policy: nil, adopted_policy_token: nil]

  @type t :: %__MODULE__{
          attachment: term(),
          connection_id: String.t(),
          clock: (-> integer()),
          configuration: map(),
          engine: module(),
          identity: map(),
          next_sequence_number: pos_integer(),
          owner: pid(),
          readiness_resource: Resource.t(),
          pipeline: module(),
          pipeline_generation: non_neg_integer(),
          pipeline_id: String.t() | nil,
          pipeline_monitor: reference() | nil,
          pipeline_options: keyword(),
          pipeline_pid: pid() | nil,
          pipeline_ready?: boolean(),
          pipeline_supervisor: module(),
          policy: Snapshot.t() | nil,
          ready_waiters: [GenServer.from()],
          reject_received_through_ms: integer() | nil
        }

  @spec new(keyword()) :: t()
  def new(options) do
    %__MODULE__{
      attachment: Keyword.fetch!(options, :attachment),
      connection_id: Keyword.fetch!(options, :connection_id),
      clock: Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end),
      engine: Keyword.get(options, :engine, Vxpipe.CallEngine),
      identity: %{
        tenant_id: Keyword.fetch!(options, :tenant_id),
        room_id: Keyword.fetch!(options, :room_id),
        incarnation_id: Keyword.fetch!(options, :incarnation_id),
        participant_id: Keyword.fetch!(options, :participant_id)
      },
      configuration: Keyword.fetch!(options, :configuration),
      next_sequence_number: 1,
      owner: Keyword.fetch!(options, :owner),
      readiness_resource:
        Resource.new(
          :room_audio_ingress,
          {:participant, Keyword.fetch!(options, :participant_id)},
          Vxpipe.Gateway.Media.RoomAudioIngress,
          options,
          binding: Keyword.fetch!(options, :connection_id)
        ),
      pipeline: Keyword.get(options, :pipeline, AudioPipeline),
      pipeline_generation: 0,
      pipeline_id: nil,
      pipeline_monitor: nil,
      pipeline_options: Keyword.get(options, :pipeline_options, []),
      pipeline_pid: nil,
      pipeline_ready?: false,
      pipeline_supervisor: Keyword.get(options, :pipeline_supervisor, ConnectionPeerSupervisor),
      policy: nil,
      ready_waiters: [],
      reject_received_through_ms: nil
    }
  end
end
