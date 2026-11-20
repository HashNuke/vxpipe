defmodule Vxpipe.Calls.Diagnostics.Attachment do
  @moduledoc "Constructs immutable diagnostic runs from admitted Engine source context."
  alias Vxpipe.CallEngine.Diagnostics.{AttachmentLease, CaptureHandoff}
  alias Vxpipe.CallEngine.Speech.{ActivityBoundary, Silero}
  alias Vxpipe.Calls.Diagnostics.{Collector, Supervisor}
  alias Vxpipe.Calls.LatencyRun
  alias Vxpipe.Providers.ElevenLabs.Scribe

  @acknowledgement_fields [
    :model_id,
    :sample_rate,
    :audio_format,
    :commit_strategy,
    :vad_silence_threshold_secs,
    :vad_threshold,
    :min_speech_duration_ms,
    :min_silence_duration_ms,
    :keepalive_interval_ms
  ]

  def start(context, options) do
    with %AttachmentLease{} = lease <- Map.get(context, :attachment_lease),
         {:ok, run} <- run(context),
         {:ok, collector} <-
           AttachmentLease.operation(lease, fn ->
             Supervisor.start_collector(
               [
                 run: run,
                 attachment_lease: lease,
                 generation: context.generation,
                 origin_us: context.origin_us,
                 owner: context.capability,
                 coordinator: context.coordinator,
                 settings: context.settings,
                 utc_now: Keyword.get(options, :utc_now, &DateTime.utc_now/0),
                 writer_supervisor:
                   Keyword.get(
                     options,
                     :writer_supervisor,
                     Vxpipe.Calls.Diagnostics.WriterSupervisor
                   ),
                 writer_options: [
                   repository: Keyword.fetch!(options, :repository),
                   task_supervisor:
                     Keyword.get(
                       options,
                       :task_supervisor,
                       Vxpipe.Calls.Diagnostics.TaskSupervisor
                     )
                 ]
               ],
               Keyword.get(
                 options,
                 :collector_supervisor,
                 Vxpipe.Calls.Diagnostics.CollectorSupervisor
               )
             )
           end),
         %CaptureHandoff{} = handoff <- Collector.handoff(collector) do
      {:ok, handoff}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp run(context) do
    with {:ok, %{missing: [], acknowledged: acknowledged}} <-
           Scribe.validate_acknowledgement(context.provider_profile, :vad, "scribe_v2_realtime") do
      acknowledgement =
        @acknowledgement_fields
        |> Map.new(fn field -> {field, Map.fetch!(acknowledged, Atom.to_string(field))} end)
        |> Map.put(:commit_strategy, :vad)

      profile =
        Map.merge(ActivityBoundary.profile(), %{
          provider: "elevenlabs",
          model: "scribe_v2_realtime",
          commit_strategy: :vad,
          inference_source: context.mode,
          vad_model: Silero.Model.version(),
          provider_acknowledgement: acknowledgement
        })

      LatencyRun.new(%{
        id: context.run_id,
        tenant_key: context.identity.tenant_id,
        call_id: context.identity.call_id,
        room_id: context.identity.room_id,
        incarnation_id: context.identity.incarnation_id,
        participant_id: context.participant_id,
        connection_id: context.connection_id,
        source_epoch: context.source_id,
        clock_id: context.clock_id,
        settings_revision: context.settings_revision,
        anchor_utc: context.anchor_utc,
        profile: profile
      })
    end
  end
end
