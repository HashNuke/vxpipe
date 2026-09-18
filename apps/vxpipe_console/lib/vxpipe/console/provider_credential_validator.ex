defmodule Vxpipe.Console.ProviderCredentialValidator do
  @moduledoc "Performs bounded, read-only authentication checks for supported provider credentials."

  @behaviour Vxpipe.Calls.ProviderCredentialValidator

  @google_url "https://generativelanguage.googleapis.com/v1beta/models"
  @deepgram_url "https://api.deepgram.com/v1/projects"
  @zenmux_url "https://zenmux.ai/api/v1/models"
  @telnyx_url "https://api.telnyx.com/v2/call_control_applications"
  @twilio_base_url "https://api.twilio.com/2010-04-01"

  @impl true
  def validate(options, provider, auth_kind, payload) when is_list(options) do
    with {:ok, request} <- request(provider, auth_kind, payload),
         {:ok, response} <- send_request(options, request) do
      classify(response)
    else
      {:error, :invalid_provider_auth} -> {:error, :provider_credential_rejected}
      {:error, _reason} -> {:error, :provider_validation_unavailable}
    end
  rescue
    _exception -> {:error, :provider_validation_unavailable}
  catch
    _kind, _reason -> {:error, :provider_validation_unavailable}
  end

  defp request("google", "api_key", %{"api_key" => api_key}) do
    {:ok,
     [
       url: @google_url,
       params: [pageSize: 1],
       headers: [{"accept", "application/json"}, {"x-goog-api-key", api_key}]
     ]}
  end

  defp request("deepgram", "api_key", %{"api_key" => api_key}) do
    {:ok,
     [
       url: @deepgram_url,
       headers: [{"accept", "application/json"}, {"authorization", "Token " <> api_key}]
     ]}
  end

  defp request("zenmux", "api_key", %{"api_key" => api_key}) do
    {:ok,
     [
       url: @zenmux_url,
       headers: [{"accept", "application/json"}, {"authorization", "Bearer " <> api_key}]
     ]}
  end

  defp request("telnyx", "api_key", %{"api_key" => api_key}) do
    {:ok,
     [
       url: @telnyx_url,
       params: [{"page[size]", 1}],
       headers: [{"accept", "application/json"}, {"authorization", "Bearer " <> api_key}]
     ]}
  end

  defp request(
         "twilio",
         "account_sid_auth_token",
         %{"account_sid" => account_sid, "auth_token" => auth_token}
       ) do
    {:ok,
     [
       url: @twilio_base_url <> "/Accounts/" <> account_sid <> ".json",
       headers: [
         {"accept", "application/json"},
         {"authorization", "Basic " <> Base.encode64(account_sid <> ":" <> auth_token)}
       ]
     ]}
  end

  defp request(_provider, _auth_kind, _payload), do: {:error, :invalid_provider_auth}

  defp send_request(options, request) do
    options
    |> Keyword.get(:request_options, [])
    |> Keyword.merge(request)
    |> Keyword.merge(method: :get, retry: false, redirect: false, receive_timeout: 10_000)
    |> Req.request()
  end

  defp classify(%Req.Response{status: status}) when status in 200..299, do: :ok

  defp classify(%Req.Response{status: status})
       when status in 400..499 and status not in [408, 425, 429],
       do: {:error, :provider_credential_rejected}

  defp classify(%Req.Response{}), do: {:error, :provider_validation_unavailable}
end
