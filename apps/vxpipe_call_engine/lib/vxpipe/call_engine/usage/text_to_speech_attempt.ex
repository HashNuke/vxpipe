defmodule Vxpipe.CallEngine.Usage.TextToSpeechAttempt do
  @moduledoc false

  alias Membrane.{RawAudio, Time}
  alias Vxpipe.CallEngine.Provider.TextToSpeech.Signal
  alias Vxpipe.CallEngine.TextToSpeechRequest

  alias Vxpipe.CallEngine.Usage.{
    Attribution,
    Measurement,
    Observation,
    ProviderContext
  }

  @derive {Inspect,
           only: [
             :attempt_id,
             :call_id,
             :activation_id,
             :provider,
             :generated_audio_bytes
           ]}
  @enforce_keys [
    :attempt_id,
    :call_id,
    :activation_id,
    :provider,
    :request,
    :audio_format,
    :generated_audio_bytes
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          attempt_id: String.t(),
          call_id: String.t(),
          activation_id: String.t() | nil,
          provider: ProviderContext.t(),
          request: TextToSpeechRequest.t(),
          audio_format: RawAudio.t(),
          generated_audio_bytes: non_neg_integer()
        }

  @spec start(
          TextToSpeechRequest.t(),
          String.t(),
          String.t(),
          String.t() | nil,
          ProviderContext.t(),
          map()
        ) :: t()
  def start(
        %TextToSpeechRequest{} = request,
        attempt_id,
        call_id,
        activation_id,
        %ProviderContext{} = provider,
        media_format
      )
      when is_binary(attempt_id) and is_binary(call_id) and
             (is_binary(activation_id) or is_nil(activation_id)) do
    %__MODULE__{
      attempt_id: attempt_id,
      call_id: call_id,
      activation_id: activation_id,
      provider: provider,
      request: request,
      audio_format: raw_audio_format(media_format),
      generated_audio_bytes: 0
    }
  end

  @spec observe_signal(t(), Signal.t()) :: t()
  def observe_signal(%__MODULE__{} = attempt, %Signal{} = signal) do
    provider = %{
      attempt.provider
      | request_id: signal.request_id || attempt.provider.request_id,
        operation_id: signal.provider_speech_id || attempt.provider.operation_id
    }

    %{attempt | provider: provider}
  end

  @spec observe_audio(t(), binary()) :: t()
  def observe_audio(%__MODULE__{} = attempt, payload) when is_binary(payload) do
    %{attempt | generated_audio_bytes: attempt.generated_audio_bytes + byte_size(payload)}
  end

  @spec finish(t(), :succeeded | :failed | :cancelled, DateTime.t()) ::
          {:ok, [Observation.t()]} | {:error, :invalid_text_to_speech_usage}
  def finish(%__MODULE__{} = attempt, outcome, %DateTime{} = observed_at)
      when outcome in [:succeeded, :failed, :cancelled] do
    with {:ok, attribution} <- attribution(attempt),
         {:ok, measurements} <- measurements(attempt),
         {:ok, observations} <-
           observations(attempt, attribution, measurements, outcome, observed_at) do
      {:ok, observations}
    else
      _invalid -> {:error, :invalid_text_to_speech_usage}
    end
  end

  defp attribution(attempt) do
    request = attempt.request

    Attribution.new(
      room_id: request.room_id,
      incarnation_id: request.incarnation_id,
      participant_id: request.participant_id,
      activation_id: attempt.activation_id,
      turn_id: request.correlation_id
    )
  end

  defp measurements(attempt) do
    with {:ok, characters} <- measurement("input_characters", :characters, text_length(attempt)),
         {:ok, duration} <- audio_duration_measurement(attempt) do
      {:ok, [characters | duration]}
    end
  end

  defp text_length(attempt), do: String.length(attempt.request.text)

  defp audio_duration_measurement(%{generated_audio_bytes: 0}), do: {:ok, []}

  defp audio_duration_measurement(attempt) do
    milliseconds =
      attempt.generated_audio_bytes
      |> RawAudio.bytes_to_time(attempt.audio_format)
      |> div(Time.millisecond())

    case measurement("generated_audio_duration", :milliseconds, milliseconds) do
      {:ok, measurement} -> {:ok, [measurement]}
      {:error, :invalid_measurement} = error -> error
    end
  end

  defp measurement(component, unit, quantity) do
    Measurement.new(
      component: component,
      unit: unit,
      quantity: quantity,
      mode: :cumulative,
      status: :final,
      provenance: :locally_measured
    )
  end

  defp observations(attempt, attribution, measurements, outcome, observed_at) do
    measurements
    |> Enum.reduce_while({:ok, []}, fn measurement, {:ok, observations} ->
      case observation(attempt, attribution, measurement, outcome, observed_at) do
        {:ok, observation} -> {:cont, {:ok, [observation | observations]}}
        {:error, :invalid_observation} -> {:halt, {:error, :invalid_text_to_speech_usage}}
      end
    end)
    |> case do
      {:ok, observations} -> {:ok, Enum.reverse(observations)}
      {:error, :invalid_text_to_speech_usage} = error -> error
    end
  end

  defp observation(attempt, attribution, measurement, outcome, observed_at) do
    request = attempt.request

    Observation.new(
      id: observation_id(attempt.attempt_id, measurement.component),
      tenant_id: request.tenant_id,
      call_id: attempt.call_id,
      attempt_id: attempt.attempt_id,
      capability: :text_to_speech,
      provider: attempt.provider,
      attribution: attribution,
      measurement: measurement,
      outcome: outcome,
      observed_at: observed_at
    )
  end

  defp observation_id(attempt_id, component) do
    digest = :crypto.hash(:sha256, attempt_id <> ":" <> component)
    "uobs_" <> Base.url_encode64(digest, padding: false)
  end

  defp raw_audio_format(%{
         codec: :linear16,
         sample_rate: sample_rate,
         channels: channels,
         byte_order: byte_order
       })
       when is_integer(sample_rate) and sample_rate > 0 and is_integer(channels) and channels > 0 do
    %RawAudio{
      sample_format: sample_format(byte_order),
      sample_rate: sample_rate,
      channels: channels
    }
  end

  defp sample_format(:little), do: :s16le
  defp sample_format(:big), do: :s16be
end
