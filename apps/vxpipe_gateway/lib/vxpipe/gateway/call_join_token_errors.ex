defmodule Vxpipe.Gateway.CallJoinTokenErrors do
  @moduledoc "Fixed public join-token failures without backend details."

  def response(reason) when reason in [:invalid_api_key, :missing_credentials],
    do: error(401, "invalid_api_key", "The API key is invalid.")

  def response(reason)
      when reason in [:not_authorized, :forbidden, :insufficient_scope, :tenant_access_forbidden],
      do: error(403, "not_authorized", "The actor cannot manage calls.")

  def response(reason) when reason in [:not_found, :participant_not_found, :route_unavailable],
    do: error(404, "call_route_not_found", "The call route does not exist.")

  def response(:participant_required),
    do: error(400, "participant_required", "Select an eligible web participant.")

  def response(reason)
      when reason in [:invalid_request, :invalid_tenant_key, :invalid_join_token_configuration],
      do: error(400, "invalid_request", "The request is invalid.")

  def response(reason)
      when reason in [
             :call_unavailable,
             :participant_admission_pending,
             :participant_admission_unavailable,
             :participant_not_entry_caller
           ],
      do: error(409, "call_unavailable", "The call cannot accept that request.")

  def response(_reason),
    do: error(503, "call_management_unavailable", "Call management is unavailable.", true)

  defp error(status, code, message, retryable \\ false),
    do: {status, %{code: code, message: message, retryable: retryable, details: %{}}}
end
