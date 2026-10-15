defmodule Vxpipe.Gateway.CatalogPage do
  @moduledoc "Bounded pagination of already-authorized static provider and model catalogs."

  def paginate(items, page, page_size)
      when is_list(items) and is_integer(page) and page in 1..2_147_483_647 and
             is_integer(page_size) and page_size in 1..50 do
    total = length(items)
    pages = if total == 0, do: 0, else: div(total + page_size - 1, page_size)

    if page <= max(pages, 1) do
      {:ok,
       %{
         items: Enum.slice(items, (page - 1) * page_size, page_size),
         pagination: %{page: page, page_size: page_size, total: total, total_pages: pages}
       }}
    else
      {:error, :page_out_of_range}
    end
  end

  def paginate(_items, _page, _page_size), do: {:error, :invalid_page}
end
