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
  defdelegate start_link(module, private_init), to: Vxpipe.CallEngine.Speech.ProviderProcess

  @callback configure(keyword()) :: {:ok, Descriptor.t()} | {:error, :invalid_configuration}
  @callback start_link(keyword()) :: GenServer.on_start()
  @doc """
  Accept one bounded chunk into the provider's bounded processing/transport slot.
  `:ok` proves acceptance; processing and transcript delivery may finish later.
  Return `{:error, :busy}` only when this chunk was not accepted and existing work
  remains valid. The caller decides whether to submit again; nothing is replayed.
  Every other error or unexpected return retires the allocation with a fixed safe
  error. The API-entry command deadline bounds this operation independently of provider
  responsiveness. Never return success merely for an unbounded mailbox enqueue.
  """
  @callback push_audio(pid(), binary()) :: :ok | {:error, :busy | :session_failed}
  @callback close(pid()) :: :ok | {:error, atom()}

  @doc """
  Bounded finite-input finalization for agent-output STT.

  Called once at the STS generation boundary after the last output chunk was
  admitted. The provider flushes recognition for the finite fed input and emits
  its turn evidence; it must not invent conversational onset or turn-end rules
  beyond its declared descriptor. Human conversational onset and turn-end
  requirements are unchanged. Optional: providers without finite fed input
  simply omit it.
  """
  @callback finish_input(pid()) :: :ok | {:error, atom()}

  @optional_callbacks finish_input: 1
end
