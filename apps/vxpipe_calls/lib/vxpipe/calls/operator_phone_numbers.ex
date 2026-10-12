defmodule Vxpipe.Calls.OperatorPhoneNumbers do
  @moduledoc "Installation-authorized carrier inventory with current published number assignments."
  alias Vxpipe.Calls.{InstallationOperator, ProviderAuth, Repositories, TelephonyServices}

  def list(%InstallationOperator{grant: :installation_operator}, tenant, service, query, options) do
    with :ok <- ProviderAuth.tenant_key(tenant),
         :ok <- validate_query(query),
         {:ok, snapshot} <- TelephonyServices.resolve(tenant, service, options),
         {:ok, reader} <- Keyword.fetch(options, :number_reader),
         {:ok, page} <- reader.(snapshot, query),
         {:ok, repository} <- Repositories.fetch(options, :call_spec_repository),
         {:ok, assignments} <-
           Repositories.call(repository, :list_number_assignments, [
             tenant,
             Enum.map(page.numbers, & &1.number)
           ]) do
      excluded = Map.get(query, :call_spec_id)

      by_number =
        assignments |> Enum.reject(&(&1.call_spec_id == excluded)) |> Enum.group_by(& &1.number)

      numbers =
        Enum.map(page.numbers, fn number ->
          used = Map.get(by_number, number.number, [])
          Map.merge(number, %{available: used == [], assigned_to: Enum.map(used, & &1.name)})
        end)

      {:ok, %{numbers: numbers, next_page: page.next_page}}
    else
      :error -> {:error, :phone_numbers_unavailable}
      {:error, _} = error -> error
    end
  end

  def list(_, _, _, _, _), do: {:error, :installation_operator_required}

  defp validate_query(%{search: search, page: page} = query)
       when is_binary(search) and byte_size(search) <= 64 do
    if (is_nil(page) or (is_binary(page) and byte_size(page) in 1..256)) and
         (is_nil(Map.get(query, :call_spec_id)) or
            (is_binary(query.call_spec_id) and byte_size(query.call_spec_id) <= 128)),
       do: :ok,
       else: {:error, :invalid_request}
  end

  defp validate_query(_), do: {:error, :invalid_request}
end
