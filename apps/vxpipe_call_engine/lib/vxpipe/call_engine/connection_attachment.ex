defmodule Vxpipe.CallEngine.ConnectionAttachment do
  @moduledoc """
  Internal handles granted to one authorized transport connection.

  This struct is never part of a public snapshot or wire protocol.
  """

  @enforce_keys [:room_monitor, :media_ingress]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          room_monitor: reference(),
          media_ingress: pid() | nil
        }
end
