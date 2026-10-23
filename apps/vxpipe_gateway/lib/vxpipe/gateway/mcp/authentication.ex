defmodule Vxpipe.Gateway.MCP.Authentication do
  @moduledoc false

  alias Vxpipe.Identity.{Authorization, OAuth, Principal}

  def authenticate(options, secret) do
    case Keyword.fetch(options, :resource) do
      {:ok, resource} when is_binary(resource) and resource != "" ->
        OAuth.authenticate(secret, resource)

      _unconfigured ->
        {:error, :unavailable}
    end
  end

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

      {:error, reason} when reason in [:invalid_token, :invalid_grant] ->
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

  defp identity(%Principal{credential_kind: :oauth} = actor) do
    if Authorization.require_actor_identity(actor) == :ok,
      do: {:ok, "oauth:#{actor.oauth_grant_public_id}"},
      else: {:error, :invalid_credentials}
  end

  defp identity(_actor), do: {:error, :invalid_credentials}
end
