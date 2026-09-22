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

  @callback configure(keyword()) :: {:ok, Descriptor.t()} | {:error, :invalid_configuration}
  @callback start_link(keyword()) :: GenServer.on_start()
  @callback push_audio(pid(), binary()) :: :ok | {:error, :busy | :session_failed}
  @callback push_text(pid(), reference(), String.t()) :: :ok | {:error, atom()}
  @callback input_activity(pid(), :started | :ended) :: :ok | {:error, atom()}
  @callback interrupt(pid(), reference()) :: :ok | {:error, atom()}
  @callback send_tool_result(pid(), reference(), term()) :: :ok | {:error, atom()}
  @callback close(pid()) :: :ok | {:error, atom()}
end
