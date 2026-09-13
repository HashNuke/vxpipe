defmodule Vxpipe.Gateway.Telephony.Telnyx.AudioIngressPipeline do
  @moduledoc """
  Normalizes one authenticated Telnyx Opus stream into room-ready PCM frames.
  """

  use Membrane.Pipeline

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  import Membrane.ChildrenSpec

  alias Membrane.{Buffer, Pipeline, Time}
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.Gateway.Media.{MonoMixer, PCMFrame, PCMSink}

  alias Vxpipe.Gateway.Telephony.Telnyx.AudioIngressPipeline.{
    ClockAligner,
    PacketSource
  }

  @sample_rate 48_000
  @channels 1
  @input_format %{codec: :opus, sample_rate: 16000, channels: 1}

  @spec start_link(keyword()) :: Pipeline.on_start()
  def start_link(options) do
    pipeline_id = Keyword.fetch!(options, :pipeline_id)
    Pipeline.start_link(__MODULE__, options, name: via(pipeline_id))
  end

  @spec push(String.t(), AudioFrame.t()) :: :ok | {:error, atom()}
  def push(pipeline_id, %AudioFrame{} = frame) do
    Pipeline.call(via(pipeline_id), {:push, frame})
  end

  def prepare_track(pipeline, track), do: call(pipeline, {:prepare_track, track})

  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness(pipeline), do: call(pipeline, :readiness)

  @impl true
  def handle_init(_context, options) do
    preparation_reference = make_ref()

    state = %{
      pipeline_id: Keyword.fetch!(options, :pipeline_id),
      owner: Keyword.fetch!(options, :owner),
      tenant_id: Keyword.fetch!(options, :tenant_id),
      room_id: Keyword.fetch!(options, :room_id),
      incarnation_id: Keyword.fetch!(options, :incarnation_id),
      participant_id: Keyword.fetch!(options, :participant_id),
      connection_id: Keyword.fetch!(options, :connection_id),
      track_id: Keyword.fetch!(options, :track_id),
      preparation_reference: preparation_reference,
      preparation_status: :preparing,
      input_resource:
        Resource.new(
          :audio_input,
          {:participant, Keyword.fetch!(options, :participant_id)},
          __MODULE__,
          {@input_format, options},
          binding: Keyword.fetch!(options, :connection_id)
        ),
      last_sequence_number: nil,
      last_timestamp: nil
    }

    specification =
      child(:source, %PacketSource{preparation_reference: preparation_reference})
      |> child(:clock_aligner, %ClockAligner{
        clock_origin_ms: Keyword.fetch!(options, :clock_origin_ms)
      })
      |> child(:decoder, %Membrane.Opus.Decoder{sample_rate: @sample_rate})
      |> child(:mono_mixer, MonoMixer)
      |> child(:frame_parser, %Membrane.RawAudioParser{
        chunk_duration: Time.milliseconds(20)
      })
      |> child(:sink, PCMSink)

    {[spec: specification], state}
  end

  @impl true
  def handle_call(:readiness, _context, state) do
    {[reply: {:ok, state.input_resource, state.preparation_status}], state}
  end

  def handle_call({:prepare_track, track}, _context, state) do
    {[reply: validate_preparation(track, state.track_id)], state}
  end

  def handle_call({:push, %AudioFrame{} = frame}, _context, state) do
    case validate(frame, state) do
      :ok ->
        state = %{
          state
          | last_sequence_number: frame.sequence_number,
            last_timestamp: frame.timestamp
        }

        {[notify_child: {:source, {:push, frame}}, reply: :ok], state}

      {:error, reason} ->
        {[reply: {:error, reason}], state}
    end
  end

  @impl true
  def handle_child_notification(
        {:input_prepared, reference},
        :sink,
        _context,
        %{preparation_reference: reference} = state
      ) do
    send(state.owner, {:vxpipe_audio_pipeline_ready, state.pipeline_id})
    {[], %{state | preparation_status: :ready}}
  end

  def handle_child_notification(
        {:input_preparation_failed, reference},
        :sink,
        _context,
        %{preparation_reference: reference} = state
      ) do
    {[], %{state | preparation_status: :failed}}
  end

  def handle_child_notification({:pcm, %Buffer{} = buffer}, :sink, _context, state) do
    frame = %PCMFrame{
      tenant_id: state.tenant_id,
      room_id: state.room_id,
      incarnation_id: state.incarnation_id,
      participant_id: state.participant_id,
      connection_id: state.connection_id,
      track_id: state.track_id,
      timestamp: Time.as_seconds(buffer.pts * @sample_rate, :round),
      sample_rate: @sample_rate,
      channels: @channels,
      payload: buffer.payload
    }

    send(state.owner, {:vxpipe_audio_pipeline, state.pipeline_id, frame})
    {[], state}
  end

  def handle_child_notification(_notification, _child, _context, state), do: {[], state}

  defp validate_preparation(%{track_id: track_id} = track, expected) do
    cond do
      track_id != expected -> {:error, :wrong_track}
      Map.delete(track, :track_id) != @input_format -> {:error, :unsupported_audio}
      true -> :ok
    end
  end

  defp validate_preparation(_track, _expected), do: {:error, :unsupported_audio}

  defp validate(%AudioFrame{connection_id: value}, %{connection_id: expected})
       when value != expected,
       do: {:error, :wrong_connection}

  defp validate(%AudioFrame{tenant_id: value}, %{tenant_id: expected}) when value != expected,
    do: {:error, :wrong_tenant}

  defp validate(%AudioFrame{room_id: value}, %{room_id: expected}) when value != expected,
    do: {:error, :wrong_room}

  defp validate(%AudioFrame{incarnation_id: value}, %{incarnation_id: expected})
       when value != expected,
       do: {:error, :wrong_incarnation}

  defp validate(%AudioFrame{participant_id: value}, %{participant_id: expected})
       when value != expected,
       do: {:error, :wrong_participant}

  defp validate(%AudioFrame{track_id: value}, %{track_id: expected}) when value != expected,
    do: {:error, :wrong_track}

  defp validate(%AudioFrame{codec: :opus, sample_rate: 16_000, channels: 1} = frame, state),
    do: validate_order(frame, state)

  defp validate(%AudioFrame{}, _state), do: {:error, :unsupported_audio}

  defp validate_order(_frame, %{last_sequence_number: nil}), do: :ok

  defp validate_order(%AudioFrame{sequence_number: sequence}, %{last_sequence_number: previous})
       when sequence <= previous,
       do: {:error, :stale_sequence}

  defp validate_order(%AudioFrame{timestamp: timestamp}, %{last_timestamp: previous})
       when timestamp < previous,
       do: {:error, :stale_timestamp}

  defp validate_order(_frame, _state), do: :ok

  defp via(pipeline_id) do
    {:via, Registry, {Vxpipe.Gateway.Media.Registry, {:telnyx_audio_ingress, pipeline_id}}}
  end

  defp call(pipeline, message) do
    server = if is_pid(pipeline), do: pipeline, else: via(pipeline)
    Pipeline.call(server, message, 1_000)
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
