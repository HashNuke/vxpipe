defmodule Vxpipe.Gateway.CallHangupErrors do
  @moduledoc "Fixed whole-call hangup errors shared by HTTP and MCP."

  def response(reason) do
    {status, code, message} =
      case reason do
        invalid when invalid in [:invalid_api_key, :missing_credentials] ->
          {401, "invalid_api_key", "The API key is invalid."}

        denied
        when denied in [
               :not_authorized,
               :forbidden,
               :insufficient_scope,
               :tenant_access_forbidden
             ] ->
          {403, "not_authorized", "The actor cannot manage calls."}

        :not_found ->
          {404, "call_not_found", "The call does not exist."}

        invalid when invalid in [:invalid_request, :invalid_tenant_key, :invalid_call_hangup] ->
          {400, "invalid_request", "The request is invalid."}

        :call_hangup_unknown ->
          {503, "call_hangup_unknown",
           "Cancellation was requested but cleanup could not be confirmed."}

        _unavailable ->
          {503, "call_hangup_unavailable", "Call hangup is unavailable."}
      end

    {status, %{code: code, message: message, retryable: false, details: %{}}}
  end
end
