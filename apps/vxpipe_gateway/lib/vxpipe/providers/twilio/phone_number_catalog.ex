defmodule Vxpipe.Providers.Twilio.PhoneNumberCatalog do
  @moduledoc "Read-only Twilio account number inventory adapter."
  def list(connection, credentials, search, page, options) do
    Vxpipe.Gateway.PhoneNumberCatalog.fetch(
      __MODULE__,
      connection,
      credentials,
      search,
      page,
      options
    )
  end

  def request(account, %{"account_sid" => account, "auth_token" => token}, search, page) do
    params =
      [{"PageSize", 50}] ++ if(search == "", do: [], else: [{"PhoneNumber", "*#{search}*"}])

    params = params ++ if(is_nil(page), do: [], else: [{"PageToken", page}])

    {:ok,
     [
       method: :get,
       url:
         "https://api.twilio.com/2010-04-01/Accounts/#{URI.encode(account)}/IncomingPhoneNumbers.json",
       auth: {:basic, "#{account}:#{token}"},
       params: params
     ]}
  end

  def request(_, _, _, _), do: {:error, :phone_numbers_unavailable}

  def decode(_connection, %{"incoming_phone_numbers" => numbers} = body)
      when is_list(numbers) and length(numbers) <= 50 do
    voices = Enum.filter(numbers, &(get_in(&1, ["capabilities", "voice"]) == true))

    next =
      case body["next_page_uri"] do
        path when is_binary(path) ->
          path
          |> URI.parse()
          |> Map.get(:query)
          |> then(&URI.decode_query(&1 || ""))
          |> Map.get("PageToken")

        _ ->
          nil
      end

    Vxpipe.Gateway.PhoneNumberPage.normalize(voices, "sid", "friendly_name", next)
  end

  def decode(_, _), do: {:error, :phone_numbers_unavailable}
end
