defmodule Vxpipe.Console.CallRecordingBackend do
  @moduledoc "Private recording lookup boundary used by Console playback."

  alias Vxpipe.Calls.Principal
  alias Vxpipe.Console.CallRecording.{Source, Summary}

  @callback list(term(), Principal.t(), String.t()) ::
              {:ok, [Summary.t()]} | {:error, term()}

  @callback open(term(), Principal.t(), String.t(), String.t()) ::
              {:ok, Source.t()} | {:error, term()}
end
