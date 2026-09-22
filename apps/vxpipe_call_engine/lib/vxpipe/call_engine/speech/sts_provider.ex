defmodule Vxpipe.CallEngine.Speech.STSProvider do
  @moduledoc """
  A supervised conversational speech-to-speech session. Configuration is pure
  and public; startup receives the descriptor, an opaque event channel and
  trusted private options. The provider owns its bidirectional model session,
  wire protocol, turn identifiers and model context. It never publishes to the
  room directly; all results flow through `Speech.Event.emit/3` for room
  attribution, policy and playback decisions.
  """

  alias Vxpipe.CallEngine.Speech.Descriptor

  defdelegate start_link(module, private_init), to: Vxpipe.CallEngine.Speech.ProviderProcess

  @callback configure(keyword()) :: {:ok, Descriptor.t()} | {:error, :invalid_configuration}
  @callback start_link(keyword()) :: GenServer.on_start()
  @callback push_audio(pid(), binary()) :: :ok | {:error, :busy | :session_failed}
  @callback push_text(pid(), String.t()) :: :ok | {:error, atom()}
  @callback interrupt(pid(), reference()) :: :ok | {:error, atom()}
  @callback send_tool_result(pid(), reference(), term()) :: :ok | {:error, atom()}
  @callback close(pid()) :: :ok | {:error, atom()}
end
