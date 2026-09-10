defmodule Vxpipe.CallEngine.OpeningAudio.CachedPlaybackRequest do
  @moduledoc false

  @derive {Inspect,
           only: [
             :tenant_id,
             :room_id,
             :incarnation_id,
             :participant_id,
             :connection_id,
             :command_id,
             :correlation_id
           ]}
  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :connection_id,
    :command_id,
    :correlation_id,
    :output_sink
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          connection_id: String.t(),
          command_id: String.t(),
          correlation_id: String.t(),
          output_sink: pid()
        }

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = request) do
    Enum.all?(
      [
        request.tenant_id,
        request.room_id,
        request.incarnation_id,
        request.participant_id,
        request.connection_id,
        request.command_id,
        request.correlation_id
      ],
      &(is_binary(&1) and byte_size(&1) > 0)
    ) and is_pid(request.output_sink)
  end

  def valid?(_request), do: false
end
