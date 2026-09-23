defmodule Vxpipe.Gateway.WebRTC.IncomingAudio do
  @moduledoc false

  alias ExRTP.Packet
  alias ExWebRTC.RTPCodecParameters
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.Media.{RoomAudioIngress, STSInput}
  alias Vxpipe.Gateway.WebRTC.{AudioFrame, OpusInput, SpeechInput}

  def forward_connection(codec, track_id, packet, state, options \\ [])

  def forward_connection(nil, _track_id, _packet, state, _options), do: {:drop, state}

  def forward_connection(codec, track_id, packet, state, options) do
    if receive_only?(state.attachment) do
      {:drop, state}
    else
      prepare_and_deliver_audio(codec, track_id, packet, state, options)
    end
  end

  @spec forward(
          RTPCodecParameters.t() | nil,
          ExWebRTC.MediaStreamTrack.id(),
          Packet.t(),
          keyword()
        ) ::
          {:ok | :drop | :unavailable, map() | nil}
  def forward(nil, _track_id, %Packet{}, options), do: {:drop, Keyword.get(options, :sts_input)}

  def forward(%RTPCodecParameters{} = codec, track_id, %Packet{} = packet, options) do
    attachment = Keyword.fetch!(options, :attachment)
    input = Keyword.get(options, :sts_input)

    {result, input} =
      if receive_only?(attachment) do
        {:drop, input}
      else
        with {:ok, frame} <-
               AudioFrame.from_rtp(
                 Keyword.fetch!(options, :session),
                 Keyword.fetch!(options, :connection_id),
                 track_id,
                 codec,
                 packet,
                 Keyword.fetch!(options, :received_at)
               ) do
          frame = %{frame | source_epoch: Keyword.get(options, :source_epoch)}
          deliver(frame, options)
        else
          error -> {error, input}
        end
      end

    {classify(result), input}
  end

  @doc false
  def receive_only?(%ConnectionAttachment{
        media_ingress: nil,
        room_audio_input_mode: :disabled
      }),
      do: true

  def receive_only?(%ConnectionAttachment{}), do: false

  defp prepare_and_deliver_audio(codec, track_id, packet, state, options) do
    with {:ok, channels} <- OpusInput.track_channels(codec) do
      track = %{
        track_id: to_string(track_id),
        codec: :opus,
        sample_rate: codec.clock_rate,
        channels: channels
      }

      case SpeechInput.prepare(state.attachment, track, state.speech_input) do
        {:ok, _output, input} ->
          state = %{state | speech_input: input}
          deliver_audio(codec, track_id, packet, state, options)

        {:error, _reason} ->
          {:unavailable, state}
      end
    else
      {:error, :unsupported_codec} -> {:drop, state}
    end
  end

  defp deliver_audio(codec, track_id, packet, state, options) do
    {result, input} =
      forward(codec, track_id, packet,
        session: state.session,
        connection_id: state.connection_id,
        attachment: state.attachment,
        room_audio_ingress: state.room_audio_ingress,
        speech_input: state.speech_input,
        sts_input: state.sts_input,
        received_at: Keyword.get(options, :received_at, System.monotonic_time(:millisecond)),
        source_epoch: Keyword.get(options, :source_epoch)
      )

    {result, %{state | sts_input: input}}
  end

  defp deliver(frame, options) do
    attachment = Keyword.fetch!(options, :attachment)

    deliver_to_inputs(attachment, frame, options)
  end

  defp deliver_to_inputs(attachment, frame, options) do
    {sts_result, input} = STSInput.push(attachment, frame, Keyword.get(options, :sts_input))

    results = [
      sts_result,
      deliver_speech_audio(attachment, frame, Keyword.get(options, :speech_input)),
      RoomAudioIngress.push(Keyword.get(options, :room_audio_ingress), frame)
    ]

    result =
      cond do
        Enum.any?(results, &fatal_audio_result?/1) -> :unavailable
        Enum.any?(results, &(&1 == :ok)) -> :ok
        Enum.any?(results, &drop_audio_result?/1) -> :drop
        true -> :unavailable
      end

    {result, input}
  end

  defp deliver_speech_audio(%ConnectionAttachment{media_ingress: nil}, _frame, _input),
    do: :disabled

  defp deliver_speech_audio(%ConnectionAttachment{} = attachment, frame, input) do
    with {:ok, speech_frame} <- SpeechInput.frame(frame, input),
         do: CallEngine.push_audio(attachment, speech_frame)
  end

  defp classify(result) when result in [:ok, :drop, :unavailable], do: result
  defp classify({:error, reason}) when reason in [:unsupported_codec, :invalid_packet], do: :drop
  defp classify({:error, _reason}), do: :unavailable

  defp fatal_audio_result?(:ok), do: false
  defp fatal_audio_result?(:disabled), do: false
  defp fatal_audio_result?({:error, reason}), do: not drop_audio_reason?(reason)

  defp drop_audio_result?({:error, reason}), do: drop_audio_reason?(reason)
  defp drop_audio_result?(_result), do: false

  defp drop_audio_reason?(reason) do
    reason in [
      :buffer_full,
      :duplicate_frame,
      :invalid_packet,
      :media_overloaded,
      :policy_denied,
      :queue_full,
      :stale_frame,
      :stale_policy_interval,
      :stale_policy_revision,
      :stale_sequence,
      :stale_timestamp
    ]
  end
end
