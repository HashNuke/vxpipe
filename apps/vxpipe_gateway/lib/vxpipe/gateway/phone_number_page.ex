defmodule Vxpipe.Gateway.PhoneNumberPage do
  @moduledoc "Normalizes public number pages without exposing carrier credentials or payloads."
  def normalize(numbers, id, label, next) do
    if Enum.all?(
         numbers,
         &(is_binary(&1[id]) and is_binary(&1["phone_number"]) and
             Regex.match?(~r/^\+[1-9][0-9]{1,14}$/, &1["phone_number"]))
       ) do
      {:ok,
       %{
         numbers:
           Enum.map(
             numbers,
             &%{
               id: &1[id],
               number: &1["phone_number"],
               name: if(is_binary(&1[label]), do: &1[label], else: &1["phone_number"])
             }
           ),
         next_page: next
       }}
    else
      {:error, :phone_numbers_unavailable}
    end
  end
end
