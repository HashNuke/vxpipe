defmodule Vxpipe.CallEngine.Speech.TTSProvider do
  @moduledoc """
  A supervised synthesizer accepting bounded complete-text requests. Configuration
  is pure; private startup owns credentials and I/O. Publish submission and terminal
  evidence through `Speech.Event`, and one credited chunk through `Speech.Channel`.
  Provider control must remain responsive while waiting asynchronously for credit.
  """

  alias Vxpipe.CallEngine.Speech.Descriptor

  defdelegate start_link(module, private_init), to: Vxpipe.CallEngine.Speech.ProviderProcess

  @callback configure(keyword()) :: {:ok, Descriptor.t()} | {:error, :invalid_configuration}
  @callback start_link(keyword()) :: GenServer.on_start()
  @callback speak(pid(), reference(), String.t()) :: :ok | {:error, atom()}
  @callback cancel(pid(), reference(), struct()) :: :ok | {:error, atom()}
  @callback close(pid()) :: :ok | {:error, atom()}
end
