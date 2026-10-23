defmodule Vxpipe.Identity.AccountPage do
  @moduledoc "Bounded application pagination and account-directory search validation."

  def filters(filters) when is_map(filters) do
    page = Map.get(filters, :page, 1)
    size = Map.get(filters, :page_size, 25)
    search = Map.get(filters, :search)
    role = Map.get(filters, :role_public_id)

    cond do
      not (is_integer(page) and page in 1..2_147_483_647 and is_integer(size) and size in 1..50) ->
        {:error, :invalid_pagination}

      not valid_search?(search) ->
        {:error, :invalid_search}

      not (is_nil(role) or Vxpipe.Identity.ApiKeyActor.valid_id?(role)) ->
        {:error, :invalid_role_filter}

      true ->
        {:ok,
         %{
           page: page,
           page_size: size,
           search: if(search, do: String.trim(search)),
           role_public_id: role
         }}
    end
  end

  def filters(_filters), do: {:error, :invalid_pagination}

  def result(%{total: total} = result, %{page: page, page_size: size})
      when is_integer(total) and total >= 0 do
    pages = if total == 0, do: 0, else: div(total + size - 1, size)

    if page <= max(pages, 1),
      do: {:ok, Map.merge(result, %{page: page, page_size: size, total_pages: pages})},
      else: {:error, :page_out_of_range}
  end

  def result(_result, _filters), do: {:error, :unavailable}

  defp valid_search?(nil), do: true

  defp valid_search?(search) when is_binary(search),
    do:
      String.valid?(search) and String.length(String.trim(search)) <= 120 and
        not String.contains?(search, <<0>>)

  defp valid_search?(_search), do: false
end
