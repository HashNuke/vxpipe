defmodule Vxpipe.CallEngine.Telemetry do
  @moduledoc """
  Emits bounded operational events owned by the call engine.

  Durations use the Erlang `:native` time unit from a monotonic clock. Event
  metadata contains only closed capability, provider, outcome, and observation
  categories; conversational, tool, and correlation data is deliberately
  excluded.
  """

  alias Vxpipe.CallEngine.Provider.Deepgram.Flux

  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech.Session,
    as: DeepgramTextToSpeech

  alias Vxpipe.CallEngine.Provider.Deepgram.Flux.Session, as: FluxSession
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSTTSession
  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseCodeTTS

  @model_first_token_event [:vxpipe, :call_engine, :model, :first_token]
  @model_request_stop_event [:vxpipe, :call_engine, :model, :request, :stop]
  @tts_first_audio_event [:vxpipe, :call_engine, :tts, :first_audio]
  @opening_audio_stop_event [:vxpipe, :call_engine, :opening_audio, :stop]
  @startup_progress_event [:vxpipe, :call_engine, :startup, :progress]
  @startup_stop_event [:vxpipe, :call_engine, :startup, :stop]
  @transfer_phase_stop_event [:vxpipe, :call_engine, :transfer, :phase, :stop]
  @transfer_worker_stop_event [:vxpipe, :call_engine, :transfer, :worker, :stop]
  @wait_sound_pressure_event [:vxpipe, :call_engine, :wait_sounds, :pressure]
  @provider_failure_event [:vxpipe, :call_engine, :provider, :failure]
  @background_tool_admission_event [:vxpipe, :call_engine, :background_tool, :admission]
  @background_tool_stop_event [:vxpipe, :call_engine, :background_tool, :stop]
  @background_tool_handoff_event [:vxpipe, :call_engine, :background_tool, :handoff]
  @runtime_sample_event [:vxpipe, :call_engine, :runtime, :sample]
  @events [
    @model_first_token_event,
    @model_request_stop_event,
    @tts_first_audio_event,
    @opening_audio_stop_event,
    @startup_progress_event,
    @startup_stop_event,
    @transfer_phase_stop_event,
    @transfer_worker_stop_event,
    @wait_sound_pressure_event,
    @provider_failure_event,
    @background_tool_admission_event,
    @background_tool_stop_event,
    @background_tool_handoff_event,
    @runtime_sample_event
  ]

  @doc "Returns the complete framework-independent call-engine event contract."
  @spec events() :: [nonempty_list(atom())]
  def events, do: @events

  @doc "Returns a timestamp from the clock used for elapsed measurements."
  @spec started_at() :: integer()
  def started_at, do: System.monotonic_time()

  @doc "Emits model time to first non-empty output."
  @spec model_first_token(integer(), term()) :: :ok
  def model_first_token(started_at, provider) do
    execute_duration(@model_first_token_event, started_at, %{provider: provider(provider)})
  end

  @doc "Emits a terminal model request outcome and whether output was observed."
  @spec model_request_stop(integer(), term(), term(), boolean()) :: :ok
  def model_request_stop(started_at, provider, reason, first_output_observed?) do
    outcome = model_outcome(reason)

    execute_duration(@model_request_stop_event, started_at, %{
      provider: provider(provider),
      outcome: outcome,
      first_output: if(first_output_observed?, do: :observed, else: :missing)
    })

    if outcome in [:unavailable, :timeout, :invalid_response] do
      provider_failure(:model, provider, outcome)
    end

    :ok
  end

  @doc "Emits TTS time to the first decoded provider audio frame."
  @spec tts_first_audio(integer(), term()) :: :ok
  def tts_first_audio(started_at, provider) do
    execute_duration(@tts_first_audio_event, started_at, %{provider: provider(provider)})
  end

  @doc "Emits one terminal opening-audio outcome without call or content identity."
  @spec opening_audio_stop(integer(), :file_url | :text, :completed | :failed) :: :ok
  def opening_audio_stop(started_at, source, outcome)
      when is_integer(started_at) and source in [:file_url, :text] and
             outcome in [:completed, :failed] do
    :telemetry.execute(
      @opening_audio_stop_event,
      %{count: 1, duration: System.monotonic_time() - started_at},
      %{outcome: outcome, source: source}
    )
  end

  @doc "Emits a changed setup blocker set without resource or call identity."
  def startup_progress(started_at, blockers) do
    execute_startup(@startup_progress_event, started_at, %{
      blockers: Vxpipe.CallEngine.Readiness.Blockers.kinds(blockers)
    })
  end

  @doc "Emits total setup time and the final bounded blocker set."
  def startup_stop(started_at, outcome, blockers)
      when outcome in [:ready, :failed, :timeout, :disconnected] do
    execute_startup(@startup_stop_event, started_at, %{
      outcome: outcome,
      blockers: Vxpipe.CallEngine.Readiness.Blockers.kinds(blockers)
    })
  end

  defp execute_startup(event, started_at, metadata) do
    :telemetry.execute(
      event,
      %{count: 1, duration: System.monotonic_time() - started_at},
      metadata
    )
  end

  @doc "Emits elapsed time for a transfer phase without call identity."
  @spec transfer_phase_stop(
          integer(),
          :audience | :prepare | :release | :recover | :briefing | :acceptance | :cue,
          :ok | :failed | :timeout | :terminated | :cancelled
        ) :: :ok
  def transfer_phase_stop(started_at, phase, outcome)
      when is_integer(started_at) and
             phase in [:audience, :prepare, :release, :recover, :briefing, :acceptance, :cue] and
             outcome in [:ok, :failed, :timeout, :terminated, :cancelled] do
    :telemetry.execute(
      @transfer_phase_stop_event,
      %{count: 1, duration: System.monotonic_time() - started_at},
      %{phase: phase, outcome: outcome}
    )
  end

  @doc "Counts forced phase termination at its surviving supervisor or monitor owner."
  def transfer_worker_stop(outcome) when outcome in [:cancelled, :unexpected],
    do: :telemetry.execute(@transfer_worker_stop_event, %{count: 1}, %{outcome: outcome})

  @doc "Reports pending private playback slots without listener identity or audio."
  def wait_sound_pressure(kind, status, depth, limit)
      when kind in [:wait, :cue] and
             status in [:queued, :draining, :paused, :stopped, :completed, :failed] and
             is_integer(depth) and is_integer(limit) and depth >= 0 and depth <= limit and
             limit > 0 do
    :telemetry.execute(@wait_sound_pressure_event, %{count: 1, depth: depth, limit: limit}, %{
      kind: kind,
      status: status
    })
  end

  @doc "Emits one safe provider failure category."
  @spec provider_failure(:model | :stt | :tts, term(), term()) :: :ok
  def provider_failure(capability, provider, reason) when capability in [:model, :stt, :tts] do
    :telemetry.execute(
      @provider_failure_event,
      %{count: 1},
      %{
        capability: capability,
        provider: provider(provider),
        category: failure_category(reason)
      }
    )
  end

  @doc "Emits one background-tool admission outcome and reservation pressure at that boundary."
  @spec background_tool_admission(
          :accepted | :saturated | :start_failed | :unavailable | :invalid_tool,
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  def background_tool_admission(outcome, reserved, limit)
      when outcome in [:accepted, :saturated, :start_failed, :unavailable, :invalid_tool] and
             is_integer(reserved) and reserved >= 0 and is_integer(limit) and limit >= 0 do
    execute_pressure(@background_tool_admission_event, outcome, :reserved, reserved, limit)
  end

  @doc "Emits one terminal local background-worker outcome and elapsed duration."
  @spec background_tool_stop(integer(), :ok | :failed | :unknown | :terminated) :: :ok
  def background_tool_stop(started_at, outcome)
      when is_integer(started_at) and outcome in [:ok, :failed, :unknown, :terminated] do
    :telemetry.execute(
      @background_tool_stop_event,
      %{count: 1, duration: System.monotonic_time() - started_at},
      %{outcome: outcome}
    )
  end

  @doc "Emits one completion-mailbox outcome and its bounded queue depth."
  @spec background_tool_handoff(
          :queued | :duplicate | :overflow | :consumed,
          non_neg_integer(),
          pos_integer()
        ) :: :ok
  def background_tool_handoff(outcome, depth, limit)
      when outcome in [:queued, :duplicate, :overflow, :consumed] and is_integer(depth) and
             depth >= 0 and is_integer(limit) and limit > 0 do
    execute_pressure(@background_tool_handoff_event, outcome, :depth, depth, limit)
  end

  @doc "Emits one sampled active-room and VM-health observation."
  @spec runtime_sample(map()) :: :ok
  def runtime_sample(measurements) do
    :telemetry.execute(@runtime_sample_event, measurements, %{})
  end

  defp execute_duration(event, started_at, metadata) do
    :telemetry.execute(
      event,
      %{duration: System.monotonic_time() - started_at},
      metadata
    )
  end

  defp execute_pressure(event, outcome, pressure_key, pressure, limit) do
    :telemetry.execute(
      event,
      %{pressure_key => pressure, count: 1, limit: limit},
      %{outcome: outcome}
    )
  end

  defp provider(:req_llm), do: :req_llm
  defp provider(:local_fixture), do: :local_fixture
  defp provider(Flux), do: :deepgram
  defp provider(FluxSession), do: :deepgram
  defp provider(DeepgramTextToSpeech), do: :deepgram
  defp provider(MorseSTTSession), do: :morse
  defp provider(MorseCodeTTS), do: :morse
  defp provider(_other), do: :other

  defp model_outcome(:ok), do: :ok

  defp model_outcome(reason) when reason in [:provider_unavailable, :unavailable],
    do: :unavailable

  defp model_outcome(reason) when reason in [:provider_timeout, :timeout], do: :timeout
  defp model_outcome(:interrupted), do: :cancelled
  defp model_outcome(_reason), do: :invalid_response

  defp failure_category(reason)
       when reason in [:provider_unavailable, :provider_failed, :transport_closed, :unavailable],
       do: :unavailable

  defp failure_category(reason) when reason in [:provider_timeout, :timeout], do: :timeout

  defp failure_category(reason)
       when reason in [:invalid_provider_message, :invalid_provider_state, :invalid_response],
       do: :invalid_response

  defp failure_category(reason)
       when reason in [:audio_output_busy, :audio_output_failed, :output_failure],
       do: :output_failure

  defp failure_category(_reason), do: :unknown
end
