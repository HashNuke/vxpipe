defmodule Vxpipe.Gateway.AccountErrors do
  @moduledoc "Bounded public account errors shared by HTTP and MCP."

  @invalid [
    :invalid_account,
    :invalid_user_id,
    :invalid_email,
    :invalid_password,
    :too_short,
    :too_long,
    :confirmation_mismatch,
    :invalid_memberships,
    :memberships_not_allowed,
    :invalid_pagination,
    :invalid_search,
    :invalid_role_filter,
    :page_out_of_range,
    :invalid_user,
    :unknown_role,
    :unknown_tenant
  ]

  def response(reason) do
    {status, code, message, retryable} =
      case reason do
        :invalid_api_key ->
          {401, "invalid_api_key", "The API key is invalid.", false}

        :forbidden ->
          {403, "forbidden", "The actor cannot perform this account operation.", false}

        :not_found ->
          {404, "not_found", "The requested account or role does not exist.", false}

        :last_superadmin ->
          {409, "last_superadmin", "An enabled superadmin must remain.", false}

        :email_taken ->
          {409, "email_taken", "The email is already in use.", false}

        :stale ->
          {409, "stale", "The account changed; fetch it again before retrying.", false}

        invalid when invalid in @invalid ->
          {422, Atom.to_string(invalid), "The account request is invalid.", false}

        _unavailable ->
          {503, "account_management_unavailable", "Account management is unavailable.", true}
      end

    {status, %{code: code, message: message, retryable: retryable, details: %{}}}
  end
end
