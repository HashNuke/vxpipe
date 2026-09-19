defmodule Vxpipe.CallEngine.Speech.STTProvider do
  @moduledoc """
  A supervised speech recognizer. Configuration is pure and public; startup receives
  the descriptor, an opaque event channel and trusted private options. Publish
  cumulative turn transcripts through `Speech.Event.emit/3`. Closing discards input.
  """

  alias Vxpipe.CallEngine.Speech.Descriptor

  @doc """
  Start a GenServer provider within the absolute startup deadline in private init.
  Providers must use bounded OTP startup (this helper or an equivalent) and bind
  their event channel before blocking work. The OTP timeout owns the child even
  before bind, including a child trapping exits during initialization.
  """
  def start_link(module, private_init) do
    remaining =
      Keyword.fetch!(private_init, :start_deadline) - System.monotonic_time(:millisecond)

    GenServer.start_link(module, private_init, timeout: max(remaining, 1))
  end

  @callback configure(keyword()) :: {:ok, Descriptor.t()} | {:error, :invalid_configuration}
  @callback start_link(keyword()) :: GenServer.on_start()
  @callback push_audio(pid(), binary()) :: :ok | {:error, atom()}
  @callback close(pid()) :: :ok | {:error, atom()}
end
