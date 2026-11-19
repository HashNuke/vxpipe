defmodule Vxpipe.CallEngine.Diagnostics.SourceAttachment do
  @moduledoc "Coordinator-owned source attachment; all lifecycle waits stay outside call callbacks."
  alias Vxpipe.CallEngine.Capability.SpeechToText

  alias Vxpipe.CallEngine.Diagnostics.{
    CaptureHandoff,
    SettingsProjection,
    SourceSupervisor,
    SourceWorker
  }

  alias Vxpipe.CallEngine.RoomAuthority.DiagnosticSources

  def start(
        candidate,
        {:source_ready, generation, revision, track, epoch, codec, rate, channels, mode},
        options
      ) do
    with {:ok, grant} <- SettingsProjection.grant(options.projection),
         true <- grant == candidate.grant,
         true <- current_candidate?(candidate) do
      context = %{
        identity: candidate.identity,
        participant_id: candidate.source.participant_id,
        connection_id: candidate.source.connection_id,
        agent_id: candidate.agent.participant_id,
        capability: candidate.source.capability,
        coordinator: self(),
        generation: generation,
        provider_generation: candidate.provider_generation,
        provider_profile: candidate.provider_profile,
        policy_revision: revision,
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

      attach(candidate, context, track, options)
    else
      _ -> {:error, :stale_source}
    end
  end

  def start(_candidate, _packet, _options), do: {:error, :invalid_source}

  def current?(entry), do: current_candidate?(entry.candidate)

  def close(entry) do
    CaptureHandoff.close(entry.input)
    CaptureHandoff.close(entry.output)
    :ok
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
      agent: candidate.agent,
      owner: context.capability,
      coordinator: self(),
      output: output,
      projection: options.projection,
      mode: context.mode,
      source_epoch: context.source_epoch,
      source_id: context.source_id,
      clock_id: context.clock_id,
      origin_us: context.origin_us
    ]

    case SourceSupervisor.start_source(worker_options, options.workers, options.runtime) do
      {:ok, worker} -> finish(worker, candidate, context, track, output, options.workers)
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
           monitor: Process.monitor(worker),
           context: context
         }}

      _ ->
        _ = DynamicSupervisor.terminate_child(workers, worker)
        {:error, :stale_source}
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp bind(worker, candidate, context, track) do
    input = SourceWorker.handoff(worker, 250)
    source = %{track_id: track, source_epoch: context.source_epoch}

    with true <- current_candidate?(candidate),
         :ok <-
           SpeechToText.attach_diagnostics(
             context.capability,
             context.generation,
             context.policy_revision,
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
