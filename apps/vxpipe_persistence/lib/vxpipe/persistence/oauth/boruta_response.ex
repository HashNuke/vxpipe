defmodule Vxpipe.Persistence.OAuth.BorutaResponse do
  @moduledoc false
  def authorize_success(_conn, response), do: {:ok, response}
  def authorize_error(_conn, error), do: {:error, safe_error(error)}

  def token_success(_conn, response) do
    {:ok,
     %{
       token_type: response.token_type,
       access_token: response.access_token,
       refresh_token: response.refresh_token,
       expires_in: response.expires_in,
       scope: "mcp"
     }}
  end

  def token_error(_conn, error), do: {:error, safe_error(error)}

  defp safe_error(%{error: error})
       when error in [:invalid_request, :invalid_grant, :invalid_client, :invalid_scope],
       do: error

  defp safe_error(_), do: :invalid_request
end
