defmodule Vxpipe.Calls.MCPCatalogRefreshRepository do
  @moduledoc "Metadata-only catalog scheduling and current-attempt lookup for trusted maintenance."

  @callback enqueue_due(term(), keyword()) :: {:ok, non_neg_integer()} | {:error, atom()}
  @callback fetch_due(term(), map(), keyword()) :: {:ok, map() | :obsolete} | {:error, atom()}
end
