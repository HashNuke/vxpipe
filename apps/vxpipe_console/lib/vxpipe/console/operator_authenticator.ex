defmodule Vxpipe.Console.OperatorAuthenticator do
  @moduledoc "Authentication boundary for Console operator credentials."

  alias Vxpipe.Calls.Principal

  @callback authenticate(term(), String.t(), String.t()) ::
              {:ok, Principal.t()} | {:error, term()}
end
