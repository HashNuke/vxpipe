defmodule Vxpipe.Gateway.PhoneNumberCatalog do
  @moduledoc "Bounded, read-only inventory of existing carrier-owned voice numbers."

  def list(provider, connection, credentials, search, page, options \\ []) do
    case provider do
      "twilio" ->
        Vxpipe.Providers.Twilio.Adapter.list_phone_numbers(
          connection,
          credentials,
          search,
          page,
          options
        )

      "telnyx" ->
        Vxpipe.Providers.Telnyx.Adapter.list_phone_numbers(
          connection,
          credentials,
          search,
          page,
          options
        )

      _ ->
        {:error, :phone_numbers_unavailable}
    end
  end

  def fetch(adapter, connection, credentials, search, page, options) do
    with {:ok, request} <- adapter.request(connection, credentials, search, page),
         {:ok, %Req.Response{status: 200, body: body}} <-
           Req.request(
             Keyword.merge(
               options,
               request ++ [retry: false, redirect: false, receive_timeout: 10_000]
             )
           ),
         {:ok, result} <- adapter.decode(connection, body) do
      {:ok, result}
    else
      _ -> {:error, :phone_numbers_unavailable}
    end
  rescue
    _ -> {:error, :phone_numbers_unavailable}
  end
end
