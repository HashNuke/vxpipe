defmodule Vxpipe.Console.CallRecordingBackend do
  @moduledoc "Private recording lookup boundary used by Console playback."

  alias Vxpipe.Calls.CallReadAccess
  alias Vxpipe.Console.CallRecording.{Source, Summary}

  @callback list(term(), CallReadAccess.authority(), String.t()) ::
              {:ok, [Summary.t()]} | {:error, term()}

  @callback open(term(), CallReadAccess.authority(), String.t(), String.t()) ::
              {:ok, Source.t()} | {:error, term()}
end
