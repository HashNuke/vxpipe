defmodule Vxpipe.Artifacts.S3ObjectStore.Session do
  @moduledoc false

  alias Vxpipe.Artifacts.ArtifactSpec

  @derive {Inspect, except: [:client_options, :buffer]}
  @enforce_keys [
    :spec,
    :bucket,
    :client,
    :client_options,
    :upload_id,
    :part_size_bytes,
    :buffer,
    :buffer_bytes,
    :parts,
    :next_part_number
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          spec: ArtifactSpec.t(),
          bucket: String.t(),
          client: module(),
          client_options: keyword(),
          upload_id: String.t(),
          part_size_bytes: pos_integer(),
          buffer: iodata(),
          buffer_bytes: non_neg_integer(),
          parts: [{pos_integer(), String.t()}],
          next_part_number: pos_integer()
        }
end
