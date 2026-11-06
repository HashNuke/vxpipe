defmodule Vxpipe.Console.IntegrationsDirectory.Client do
  @moduledoc "Fetches validated public directory pages without local connection state."

  alias Vxpipe.Console.IntegrationsDirectory.{Page, Request, Transport}

  def fetch(resource, params, options \\ []) do
    with {:ok, request} <- build_request(resource, params, options),
         {:ok, response} <- Transport.fetch(request, options),
         {:ok, page} <- Page.validate(response.body, request) do
      {:ok, %{response | body: page}}
    end
  end

  defp build_request(resource, params, options) do
    case Keyword.fetch(options, :origin) do
      {:ok, origin} -> Request.build(resource, params, origin)
      :error -> Request.build(resource, params)
    end
  end
end
