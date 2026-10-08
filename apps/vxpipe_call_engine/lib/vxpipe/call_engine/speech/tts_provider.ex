defmodule Vxpipe.CallEngine.Speech.TTSProvider do
  @moduledoc """
  A supervised synthesizer accepting bounded complete-text requests. Configuration
  is pure; private startup owns credentials and I/O. Publish submission and terminal
  evidence through `Speech.Event`, and one credited chunk through `Speech.Channel`.
  Provider control must remain responsive while waiting asynchronously for credit.
  """

  alias Vxpipe.CallEngine.Speech.Descriptor

  defdelegate start_link(module, private_init), to: Vxpipe.CallEngine.Speech.ProviderProcess

  @doc "Match one exact Channel audio-credit notification without decoding its private message."
  @spec credit(term(), pid(), reference(), reference()) :: :ok | :stale
  def credit(
        {:vxpipe_speech_credit, channel, request_ref, credit_ref, :ok},
        channel,
        request_ref,
        credit_ref
      ),
      do: :ok

  def credit(_message, _channel, _request_ref, _credit_ref), do: :stale

  @callback models() :: [Vxpipe.CallEngine.Speech.Model.t()]
  @callback configure(keyword()) :: {:ok, Descriptor.t()} | {:error, :invalid_configuration}
  @callback start_link(keyword()) :: GenServer.on_start()
  @callback speak(pid(), reference(), String.t()) :: :ok | {:error, atom()}
  @callback cancel(pid(), reference(), struct()) :: :ok | {:error, atom()}
  @callback close(pid()) :: :ok | {:error, atom()}
end
