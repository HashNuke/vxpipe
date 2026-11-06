defmodule Vxpipe.Calls.MCPOAuthAttemptRepository do
  @moduledoc "Trusted durable OAuth attempt port; Calls owns current browser authority checks."
  @callback issue(term(), String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  @callback locate(term(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  @callback claim(term(), String.t(), String.t(), map()) ::
              {:ok, Vxpipe.Calls.ResolvedMCPOAuthAttempt.t()} | {:error, term()}
end
