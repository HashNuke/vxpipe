defmodule Vxpipe.Console.CallSpecRevisionJSON do
  @moduledoc false

  defdelegate render(revision), to: Vxpipe.Gateway.CallSpecJSON, as: :revision
end
