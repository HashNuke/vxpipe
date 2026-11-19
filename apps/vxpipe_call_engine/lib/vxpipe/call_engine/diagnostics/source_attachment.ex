defmodule Vxpipe.CallEngine.Diagnostics.SourceAttachment do
  @moduledoc "Coordinator-owned source attachment; all lifecycle waits stay outside call callbacks."
  alias Vxpipe.CallEngine.Capability.SpeechToText

  alias Vxpipe.CallEngine.Diagnostics.{
    AttachmentLease,
    CaptureHandoff,
    SettingsProjection,
    SourceSupervisor,
    SourceWorker,
    SourcePort
  }

  alias Vxpipe.CallEngine.RoomAuthority.{DiagnosticInputs, DiagnosticSources}

  @doc "Attach a room-owned accepted STT input without assigning acoustic ownership to an agent."
  def start_input(candidate, packet, options) do
    AttachmentLease.operation(options.attachment_lease, fn ->
      start(Map.put(candidate, :ownership, :participant_input), packet, options)
    end)
  end

  def start(
        candidate,
        {:source_ready, generation, intervals, track, epoch, codec, rate, channels, mode},
        options
      ) do
    with true <- AttachmentLease.current?(options.attachment_lease),
         {:ok, grant} <- SettingsProjection.grant(options.projection),
         true <- grant == candidate.grant,
         true <- current_candidate?(candidate) do
      context = %{
        identity: candidate.identity,
        participant_id: candidate.source.participant_id,
        connection_id: candidate.source.connection_id,
        capability: candidate.source.capability,
        coordinator: options.coordinator,
        attachment_lease: options.attachment_lease,
        generation: generation,
        provider_generation: candidate.provider_generation,
        provider_profile: candidate.provider_profile,
        policy_intervals: intervals,
        settings_revision: elem(grant, 0),
        source_epoch: epoch,
        run_id: id("run"),
        source_id: id("source"),
        clock_id: id("clock"),
        origin_us: System.monotonic_time(:microsecond),
        anchor_utc: DateTime.utc_now(),
        mode: mode,
        media_format: %{codec: codec, sample_rate: rate, channels: channels}
      }

      context =
        case candidate do
          %{ownership: :participant_input} -> context
          %{agent: agent} -> Map.put(context, :agent_id, agent.participant_id)
        end

      attach(candidate, context, track, options)
    else
      _ -> {:error, :stale_source}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end

  def start(_candidate, _packet, _options), do: {:error, :invalid_source}

  def current?(entry), do: current_candidate?(entry.candidate)

  def close(entry) do
    AttachmentLease.cancel(entry.context.attachment_lease)
    CaptureHandoff.close(entry.input)
    CaptureHandoff.close(entry.output)
    :ok
  end

  defp current_candidate?(%{ownership: :participant_input} = candidate) do
    case DiagnosticInputs.for_connection(candidate.room, candidate.source.connection_id) do
      {:ok, page} ->
        SourcePort.current?(Map.get(candidate, :source_port)) and
          page.identity == candidate.identity and candidate.source in page.sources

      _ ->
        false
    end
  end

  defp current_candidate?(candidate) do
    case DiagnosticSources.for_connection(candidate.room, candidate.source.connection_id) do
      {:ok, page} ->
        page.identity == candidate.identity and
          page.agent.participant_id == candidate.agent.participant_id and
          candidate.source in page.sources

      _ ->
        false
    end
  end

  defp attach(candidate, context, track, options) do
    case collector(options.collector, context) do
      {:ok, %CaptureHandoff{} = output}
      when output.owner == context.capability and
             output.projection == options.projection and output.grant == candidate.grant ->
        result =
          if current_candidate?(candidate),
            do: start_worker(candidate, context, track, output, options),
            else: {:error, :stale_source}

        if match?({:error, _}, result), do: CaptureHandoff.close(output)
        result

      _ ->
        {:error, :collector_unavailable}
    end
  end

  defp start_worker(candidate, context, track, output, options) do
    worker_options = [
      source_port: Map.get(candidate, :source_port),
      owner: context.capability,
      coordinator: context.coordinator,
      attachment_lease: context.attachment_lease,
      output: output,
      projection: options.projection,
      mode: context.mode,
      source_epoch: context.source_epoch,
      source_id: context.source_id,
      clock_id: context.clock_id,
      origin_us: context.origin_us
    ]

    result =
      case candidate do
        %{ownership: :participant_input} ->
          SourceSupervisor.start_input_source(
            worker_options,
            options.workers,
            options.runtime,
            options.source_admission
          )

        %{agent: agent} ->
          SourceSupervisor.start_source(
            Keyword.put(worker_options, :agent, agent),
            options.workers,
            options.runtime
          )
      end

    case result do
      {:ok, worker} -> finish(worker, candidate, context, track, output, options.workers)
      {:error, _} = error when candidate.ownership == :participant_input -> error
      _ -> {:error, :source_capacity}
    end
  end

  defp finish(worker, candidate, context, track, output, workers) do
    result = bind(worker, candidate, context, track)

    case result do
      {:ok, input} ->
        {:ok,
         %{
           room: candidate.room,
           candidate: candidate,
           worker: worker,
           input: input,
           output: output,
           context: context
         }}

      _ ->
        _ =
          AttachmentLease.operation(context.attachment_lease, fn ->
            DynamicSupervisor.terminate_child(workers, worker)
          end)

        {:error, :stale_source}
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp bind(worker, candidate, context, track) do
    source = %{track_id: track, source_epoch: context.source_epoch}

    with %CaptureHandoff{} = input <- SourceWorker.handoff(worker, 250),
         true <- current_candidate?(candidate),
         :ok <-
           SpeechToText.attach_diagnostics(
             context.capability,
             context.generation,
             context.policy_intervals,
             source,
             input,
             candidate.discovery_token,
             250
           ),
         true <- CaptureHandoff.current?(input),
         do: {:ok, input}
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp collector(factory, context) do
    factory.(context)
  rescue
    _ -> {:error, :collector_unavailable}
  catch
    _, _ -> {:error, :collector_unavailable}
  end

  defp id(prefix),
    do: prefix <> "_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
end
