defmodule Vxpipe.Gateway.CallCreationErrors do
  @moduledoc "Safe, shared HTTP and MCP call-creation errors."

  def response(%Vxpipe.CallEngine.Error{} = reason),
    do: {422, Vxpipe.CallEngine.Error.to_public(reason)}

  def response(reason) do
    {status, code, message, retryable} =
      case reason do
        :invalid_api_key ->
          {401, "invalid_api_key", "The API key is invalid.", false}

        forbidden
        when forbidden in [
               :not_authorized,
               :insufficient_scope,
               :forbidden,
               :tenant_access_forbidden
             ] ->
          {403, "not_authorized", "The actor cannot manage calls.", false}

        :not_found ->
          {404, "call_spec_not_found", "The call spec does not exist.", false}

        :unsupported_call_entry ->
          {422, "unsupported_call_entry", "The call spec needs a web entry or an outgoing entry.",
           false}

        :invalid_tenant_key ->
          {400, "invalid_request", "The request is invalid.", false}

        :call_spec_not_published ->
          {422, "call_spec_not_published", "The call spec has no published revision.", false}

        :call_spec_not_outgoing ->
          {422, "call_spec_not_outgoing", "The call spec cannot start an outgoing call.", false}

        :to_required ->
          {422, "to_required", "This call spec needs a to number in E.164 form.", false}

        :invalid_to ->
          {422, "invalid_to", "The to number must be in E.164 form, such as +14155550123.", false}

        :to_not_allowed ->
          {422, "to_not_allowed", "This call spec fixes the number it dials; omit to.", false}

        :idempotency_conflict ->
          {409, "idempotency_conflict", "The key was used for a different request.", false}

        invalid
        when invalid in [:invalid_request, :invalid_idempotency_key, :invalid_outgoing_call] ->
          {400, "invalid_request", "The request is invalid.", false}

        :outgoing_call_start_failed ->
          {503, "outgoing_call_start_failed", "The outgoing call could not be started.", false}

        :outgoing_submission_unknown ->
          {503, "outgoing_submission_unknown", "The dial submission could not be confirmed.",
           false}

        _unavailable ->
          {503, "call_management_unavailable", "Call management is unavailable.", true}
      end

    {status, %{code: code, message: message, retryable: retryable, details: %{}}}
  end
end
