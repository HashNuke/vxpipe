defmodule Vxpipe.Console.OAuth.AuthorizationController do
  @moduledoc "Explicit browser consent for a registered MCP client."
  use Phoenix.Controller, formats: [:html]
  alias Vxpipe.Console.OAuth.{Browser, ConsentPage}
  alias Vxpipe.Identity.{OAuth.Profile, Principal}

  def start(conn, _params) do
    conn = Browser.ensure_binding(conn)
    options = conn.assigns.oauth_options

    case options.backend.begin_authorization(
           conn.assigns.oauth_params,
           options.resource,
           Browser.browser_binding(conn)
         ) do
      {:ok, id} ->
        if Browser.opaque?(id),
          do: redirect(conn, to: "/oauth/authorize/" <> id),
          else: failure(conn, :unavailable)

      {:error, reason} ->
        failure(conn, reason)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, principal} <- browser_principal(conn),
         {:ok, consent} <-
           conn.assigns.oauth_options.backend.consent(
             id,
             Browser.browser_binding(conn),
             principal
           ) do
      ConsentPage.render(%{
        consent: consent,
        id: id,
        csrf_token: Plug.CSRFProtection.get_csrf_token()
      })
      |> Phoenix.HTML.Safe.to_iodata()
      |> then(&html(conn, &1))
    else
      {:error, reason} -> failure(conn, reason)
    end
  end

  def decide(conn, %{"id" => id}) do
    decision = if conn.assigns.oauth_params["decision"] == "approve", do: :approve, else: :deny

    with {:ok, principal} <- browser_principal(conn),
         {:ok, result} <-
           conn.assigns.oauth_options.backend.complete_authorization(
             id,
             Browser.browser_binding(conn),
             principal,
             decision
           ),
         {:ok, location} <- callback(result) do
      conn |> put_resp_header("location", location) |> send_resp(302, "")
    else
      {:error, reason} -> failure(conn, reason)
    end
  end

  defp browser_principal(%{
         assigns: %{user_principal: %Principal{credential_kind: :browser_session} = principal}
       }),
       do: {:ok, principal}

  defp browser_principal(_conn), do: {:error, :forbidden}

  defp callback(%{redirect_uri: uri} = result) do
    if Profile.redirect_uri?(uri) do
      parsed = URI.parse(uri)

      additions =
        result
        |> Map.take([:code, :error, :state])
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> URI.encode_query()

      query =
        case parsed.query do
          existing when is_binary(existing) and existing != "" -> existing <> "&" <> additions
          _ -> additions
        end

      {:ok, URI.to_string(%{parsed | query: query})}
    else
      {:error, :unavailable}
    end
  end

  defp failure(conn, reason) do
    status =
      case reason do
        :forbidden -> 403
        :unavailable -> 503
        :rate_limited -> 429
        _ -> 400
      end

    conn
    |> put_status(status)
    |> html("This authorization request could not be completed. Start again from your client.")
  end
end
