defmodule Vxpipe.Gateway.Media.PrivateMedia do
  @moduledoc false

  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.MediaPolicy.Enforcer
  alias Vxpipe.Gateway.Media.{RoomAudioEgress, RoomAudioIngress, SharedOutputPipeline}

  def prepare(
        %{
          attachment: %ConnectionAttachment{
            admission: :transfer_preparation,
            transfer_attempt_id: attempt_id
          }
        } = state,
        attempt_id,
        options
      ) do
    engine = Keyword.fetch!(options, :engine)
    command = %{state.attach_command | deadline: DateTime.add(DateTime.utc_now(), 5, :second)}

    case engine.prepare_transfer_media(command, attempt_id) do
      {:ok, context} -> prepare_authorized(state, context, options)
      {:error, %Error{code: :participant_transfer_rejected}} = error -> error
      {:error, reason} -> {:stop, reason}
    end
  end

  def prepare(_state, _attempt_id, _options), do: {:error, :wrong_attempt}

  defp prepare_authorized(%{private_media: nil} = state, context, options) do
    speech = context.speech_to_text
    attachment = %{state.attachment | media_ingress: if(speech, do: speech.ingress)}

    common =
      Map.to_list(
        Map.take(state.attach_command, [:tenant_id, :room_id, :incarnation_id, :participant_id])
      ) ++
        [
          connection_id: state.connection_id,
          attachment: attachment,
          owner: self(),
          engine: Keyword.fetch!(options, :engine),
          pipeline_supervisor: Keyword.fetch!(options, :supervisor)
        ]

    actors = [
      {:input,
       {RoomAudioIngress,
        common ++
          [
            configuration: context.configuration,
            pipeline: Keyword.fetch!(options, :input_pipeline),
            pipeline_options: Keyword.fetch!(options, :input_options)
          ]}},
      {:output,
       {RoomAudioEgress,
        common ++
          [
            pipeline: SharedOutputPipeline,
            pipeline_options: [output_sink: Keyword.fetch!(options, :output)]
          ]}}
    ]

    case start_actors(actors, state.connection_id, context, Keyword.fetch!(options, :supervisor)) do
      {:ok, actors} ->
        enforcers = speech_enforcers(speech) ++ [actors.input, actors.output]

        private =
          context
          |> Map.put(:enforcers, enforcers)
          |> Map.put(:monitors, Map.new(enforcers, &{Process.monitor(&1), &1}))

        state = %{
          state
          | private_media: private,
            attachment: attachment,
            room_audio_ingress: actors.input,
            room_audio_egress: actors.output
        }

        {:ok, receipt(private), state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp prepare_authorized(state, context, _options) do
    private = state.private_media

    with true <-
           Map.take(private, [:owner, :attempt_id, :deadline_ms, :speech_to_text]) ==
             Map.take(context, [:owner, :attempt_id, :deadline_ms, :speech_to_text]),
         :ok <- refresh(private, context) do
      {:ok, receipt(private), %{state | private_media: %{private | policy: context.policy}}}
    else
      _changed -> {:stop, :private_media_changed}
    end
  end

  defp start_actors(actors, connection_id, context, supervisor) do
    Enum.reduce_while(actors, {:ok, %{}}, fn {kind, spec}, {:ok, started} ->
      with {:ok, actor} <- supervisor.start_child(connection_id, spec),
           :ok <- apply_base(actor, context) do
        {:cont, {:ok, Map.put(started, kind, actor)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp refresh(%{policy: policy}, %{policy: policy}), do: :ok

  defp refresh(private, context) do
    Enum.reduce_while(private.enforcers, :ok, fn actor, :ok ->
      case apply_base(actor, context) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp apply_base(actor, context) do
    remaining = min(context.deadline_ms - System.monotonic_time(:millisecond), 1_000)

    if remaining > 0,
      do: Enforcer.apply(actor, context.policy, remaining),
      else: {:error, :deadline_elapsed}
  end

  defp speech_enforcers(nil), do: []
  defp speech_enforcers(speech), do: [speech.capability, speech.ingress]
  defp receipt(private), do: Map.take(private, [:owner, :attempt_id, :deadline_ms, :enforcers])
end
