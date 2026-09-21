defmodule Vxpipe.Console.ProviderCredentialValidator do
  @moduledoc "Performs bounded, read-only authentication checks for supported provider credentials."

  @behaviour Vxpipe.Calls.ProviderCredentialValidator

  alias Vxpipe.Console.Provider

  @credential_validators %{
    "twilio" => Provider.Twilio.CredentialValidation,
    "zenmux" => Provider.Zenmux.CredentialValidation
  }

  @impl true
  def validate(options, provider, auth_kind, payload) when is_list(options) do
    with {:ok, request} <- request(provider, auth_kind, payload),
         {:ok, response} <- send_request(options, request) do
      classify(response)
    else
      {:error, :invalid_provider_auth} -> {:error, :provider_credential_rejected}
      {:error, :provider_validation_unsupported} = error -> error
      {:error, _reason} -> {:error, :provider_validation_unavailable}
    end
  rescue
    _exception -> {:error, :provider_validation_unavailable}
  catch
    _kind, _reason -> {:error, :provider_validation_unavailable}
  end

  defp request(provider, auth_kind, payload)
       when provider in ["deepgram", "google", "rime", "telnyx"] do
    with {:ok, validator} <-
           Vxpipe.Providers.Registry.resolve_capability(provider, :credential_validation) do
      validator.request(auth_kind, payload)
    end
  end

  defp request(provider, auth_kind, payload) do
    with {:ok, validator} <- Map.fetch(@credential_validators, provider) do
      validator.request(auth_kind, payload)
    else
      :error -> {:error, :provider_validation_unsupported}
    end
  end

  defp send_request(options, request) do
    options
    |> Keyword.get(:request_options, [])
    |> Keyword.put(:method, :get)
    |> Keyword.merge(request)
    |> Keyword.merge(retry: false, redirect: false, receive_timeout: 10_000)
    |> Req.request()
  end

  defp classify(%Req.Response{status: status}) when status in 200..299, do: :ok

  defp classify(%Req.Response{status: status})
       when status in 400..499 and status not in [408, 425, 429],
       do: {:error, :provider_credential_rejected}

  defp classify(%Req.Response{}), do: {:error, :provider_validation_unavailable}
end
