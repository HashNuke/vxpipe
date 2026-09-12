defmodule Vxpipe.Calls.PublicationFinalizer.State do
  @moduledoc false

  alias Vxpipe.Calls.PublicationFinalizerJob

  @enforce_keys [:job]
  defstruct @enforce_keys ++ [timer: nil, timer_token: nil]

  @type t :: %__MODULE__{
          job: PublicationFinalizerJob.t(),
          timer: term(),
          timer_token: nil | reference()
        }
end
