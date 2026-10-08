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

  @callback models() :: [Vxpipe.CallEngine.Speech.Model.t()]
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
  admitted. `:ok` proves acceptance, not completion. A provider declaring
  `finite_input?: true` flushes all recognition segments, then emits the ordered,
  fieldless `:input_finished` event after every final `:turn_ended`. No subsequent
  audio or recognition events belong to this allocation. Repeated finalization
  must not duplicate the terminal event. The consumer retires the allocation.

  Segment endpointing remains governed by the descriptor; a speech endpoint,
  callback return or quiet period is not finite-stream terminal evidence. Human
  conversational STT does not require this optional operation. Providers without
  implemented terminal proof leave `finite_input?` false and cannot serve as
  agent-output recognizers.
  """
  @callback finish_input(pid()) :: :ok | {:error, atom()}

  @optional_callbacks finish_input: 1
end
