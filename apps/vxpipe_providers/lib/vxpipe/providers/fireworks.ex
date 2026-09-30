defmodule Vxpipe.Providers.Fireworks do
  @moduledoc "Fireworks's declared service capabilities. Model inference belongs to ReqLLM."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "fireworks"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.APIKeyCredential
    }
  end
end
