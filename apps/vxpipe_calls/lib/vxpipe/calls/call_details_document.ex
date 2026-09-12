defmodule Vxpipe.Calls.CallDetailsDocument do
  @moduledoc "Exact published JSON bytes available to an authorized operator."

  @fields [
    :id,
    :recorded_at,
    :filename,
    :completeness,
    :checksum,
    :contents,
    :published_at
  ]

  @derive {Inspect, except: [:contents]}
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          id: String.t(),
          recorded_at: DateTime.t(),
          filename: String.t(),
          completeness: :complete | :incomplete,
          checksum: String.t(),
          contents: binary(),
          published_at: DateTime.t()
        }
end
