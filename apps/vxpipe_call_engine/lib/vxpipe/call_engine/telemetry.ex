defmodule Vxpipe.CallEngine.Telemetry do
  @moduledoc """
  Emits bounded operational events owned by the call engine.

  Durations use the Erlang `:native` time unit from a monotonic clock. Event
  metadata contains only closed capability, provider, outcome, and observation
  categories; conversational and correlation data is deliberately excluded.
  """

  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}

  @model_first_token_event [:vxpipe, :call_engine, :model, :first_token]
  @model_request_stop_event [:vxpipe, :call_engine, :model, :request, :stop]
  @tts_first_audio_event [:vxpipe, :call_engine, :tts, :first_audio]
  @provider_failure_event [:vxpipe, :call_engine, :provider, :failure]
  @runtime_sample_event [:vxpipe, :call_engine, :runtime, :sample]

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

  defp provider(:req_llm), do: :req_llm
  defp provider(:local_fixture), do: :local_fixture
  defp provider(Flux), do: :deepgram
  defp provider(FluxTextToSpeech), do: :deepgram
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
