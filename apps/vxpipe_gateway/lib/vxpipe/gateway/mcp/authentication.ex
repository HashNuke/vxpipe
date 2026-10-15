defmodule Vxpipe.Gateway.MCP.Authentication do
  @moduledoc false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{InstallationOperator, Principal}

  def authenticate(options, secret), do: Calls.authenticate_api_key(secret, options)

  def principal_id(conn, _request, _token_info), do: conn.assigns.mcp_identity

  def resolve(conn, {module, context}) do
    with {:ok, secret} <- credential(Plug.Conn.get_req_header(conn, "authorization")),
         {:ok, actor} <- checked_authenticate(module, context, secret),
         {:ok, identity} <- identity(actor) do
      {:ok, actor, identity}
    end
  end

  defp credential([]), do: {:error, :missing_credentials}

  defp credential([header]) when byte_size(header) <= 263 do
    case Regex.run(~r/^Bearer ([A-Za-z0-9._~+\/-]+=*)$/i, header) do
      [_, secret] when byte_size(secret) <= 256 -> {:ok, secret}
      _invalid -> {:error, :malformed_credentials}
    end
  end

  defp credential(_headers), do: {:error, :malformed_credentials}

  defp checked_authenticate(module, context, secret) do
    case module.authenticate(context, secret) do
      {:ok, actor} ->
        {:ok, actor}

      {:error, reason} when reason in [:invalid_api_key, :revoked_api_key, :not_found] ->
        {:error, :invalid_credentials}

      _unavailable ->
        {:error, :authentication_unavailable}
    end
  rescue
    _exception -> {:error, :authentication_unavailable}
  catch
    :exit, _reason -> {:error, :authentication_unavailable}
    :throw, _reason -> {:error, :authentication_unavailable}
  end

  defp identity(%Principal{api_key_id: id, tenant_key: tenant})
       when is_binary(id) and id != "" and is_binary(tenant) and tenant != "",
       do: {:ok, "tenant:#{tenant}:#{id}"}

  defp identity(%InstallationOperator{
         grant: :installation_operator,
         credential_kind: :platform_api_key,
         api_key_id: id
       })
       when is_binary(id) and id != "",
       do: {:ok, "platform:#{id}"}

  defp identity(_actor), do: {:error, :invalid_credentials}
end
