defmodule Vxpipe.CallEngine.Speech.STSProvider do
  @moduledoc """
  A supervised conversational speech-to-speech session. Configuration is pure
  and public; startup receives the descriptor, an opaque event channel and
  trusted private options. The provider owns its bidirectional model session,
  wire protocol, turn identifiers and model context. It never publishes to the
  room directly; semantic results flow through `Speech.Event.emit/3` for room
  attribution, policy and playback decisions.

  The consumer authorizes output with `Speech.Session.admit_output/2` after
  its policy checks. The provider receives
  `{:vxpipe_speech_output, channel, turn_ref, output_ref}` and uses that fresh
  reference with `Speech.Channel.submit/3`. Keep at most one PCM chunk in
  flight, wait for its matching `:vxpipe_speech_credit`, then emit
  `:output_completed` with both references after the last credit. Completion
  ends generation; only the consumer can settle local playout and release the
  output slot. Audio/text input admission never authorizes output on its own.

  Successful consumer settlement sends the producer
  `{:vxpipe_speech_output_settled, channel, turn_ref, output_ref, played_ms}`
  exactly once for that output. This is the engine's local playback fence,
  not proof of remote hearing. A provider may use it to retire generation
  state before a safe session-resumption handoff.
  """

  alias Vxpipe.CallEngine.Speech.Descriptor

  defdelegate start_link(module, private_init), to: Vxpipe.CallEngine.Speech.ProviderProcess

  @callback models() :: [Vxpipe.CallEngine.Speech.Model.t()]
  @callback configure(keyword()) :: {:ok, Descriptor.t()} | {:error, :invalid_configuration}
  @callback start_link(keyword()) :: GenServer.on_start()
  @callback push_audio(pid(), binary()) :: :ok | {:error, :busy | :session_failed}
  @doc """
  Atomic input and consumer-issued opaque origin for `response_start?` allocations.
  Contexts are engine-owned, never provider-issued. Required for opted-in
  descriptors; there is no legacy fallback. `:ok` reports input acceptance, not
  output authority. An early event can correlate staged input but cannot grant it.
  """
  @callback submit_input(
              pid(),
              reference(),
              {:audio, binary()}
              | {:text, reference(), String.t()}
              | {:opening, reference(), Vxpipe.CallEngine.Speech.Opening.t()}
              | {:activity, :started | :ended}
            ) :: :ok | {:error, :busy | :unsupported_operation | :session_failed}
  @optional_callbacks submit_input: 3
  @callback push_text(pid(), reference(), String.t()) :: :ok | {:error, atom()}
  @doc "Start agent speech without publishing caller input; fixed mode must preserve exact text."
  @callback begin_opening(pid(), reference(), Vxpipe.CallEngine.Speech.Opening.t()) ::
              :ok | {:error, atom()}
  @optional_callbacks begin_opening: 3
  @callback input_activity(pid(), :started | :ended) :: :ok | {:error, atom()}
  @doc "A bounded, provider-owned proof that no prior input can produce later native evidence."
  @callback input_quiescent?(pid()) :: boolean()
  @doc "Mute or resume caller input while keeping the provider session and its tools alive."
  @callback set_input_hold(pid(), boolean()) :: :ok | {:error, atom()}
  @doc "Record text already published to the room for a future history reseed."
  @callback append_history(pid(), {:caller | :agent, String.t()}) :: :ok | {:error, atom()}
  @callback interrupt(pid(), reference()) :: :ok | {:error, atom()}
  @callback send_tool_result(pid(), reference(), term()) :: :ok | {:error, atom()}
  @callback close(pid()) :: :ok | {:error, atom()}
  @optional_callbacks input_quiescent?: 1, set_input_hold: 2, append_history: 2
end
