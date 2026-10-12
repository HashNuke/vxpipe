defmodule Vxpipe.Providers.Telnyx.PhoneNumberCatalog do
  @moduledoc "Read-only Telnyx account number inventory adapter."
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

  def request(connection, %{"api_key" => key}, search, page) do
    params = [
      {"page[size]", 50},
      {"page[number]", page || "1"},
      {"filter[connection_id]", connection},
      {"filter[status]", "active"}
    ]

    params = params ++ if(search == "", do: [], else: [{"filter[phone_number]", search}])

    {:ok,
     [
       method: :get,
       url: "https://api.telnyx.com/v2/phone_numbers",
       auth: {:bearer, key},
       params: params
     ]}
  end

  def request(_, _, _, _), do: {:error, :phone_numbers_unavailable}

  def decode(connection, %{
        "data" => numbers,
        "meta" => %{"page_number" => page, "total_pages" => total}
      })
      when is_list(numbers) and length(numbers) <= 50 and is_integer(page) and is_integer(total) do
    eligible =
      Enum.filter(numbers, &(&1["connection_id"] == connection and &1["status"] == "active"))

    Vxpipe.Gateway.PhoneNumberPage.normalize(
      eligible,
      "id",
      "customer_reference",
      if(page < total, do: Integer.to_string(page + 1))
    )
  end

  def decode(_, _), do: {:error, :phone_numbers_unavailable}
end
