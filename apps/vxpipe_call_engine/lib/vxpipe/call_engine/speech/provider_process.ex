defmodule Vxpipe.CallEngine.Speech.ProviderProcess do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.ProviderName

  def start_link(module, private_init) do
    remaining =
      Keyword.fetch!(private_init, :start_deadline) - System.monotonic_time(:millisecond)

    if remaining > 0 do
      allocation = Keyword.fetch!(private_init, :allocation)

      GenServer.start_link(module, private_init,
        timeout: remaining,
        name: ProviderName.address(allocation)
      )
    else
      {:error, :startup_timeout}
    end
  end
end
