defmodule Vxpipe.CallEngine.Archive.Writer do
  @moduledoc "Persistence-neutral writer invoked outside live room processes."

  @type context :: term()
  @type outcome :: :ok | {:retry, term()} | {:discard, term()}

  @callback write(context(), term()) :: outcome()
end
