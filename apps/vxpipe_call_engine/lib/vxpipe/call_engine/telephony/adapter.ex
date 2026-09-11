defmodule Vxpipe.CallEngine.Telephony.Adapter do
  @moduledoc """
  Contract between provider-neutral phone-leg orchestration and a configured carrier adapter.

  Immediate command submissions deliberately distinguish provider acceptance from an unknown
  outcome. Callers must correlate later events and must never redial merely because the immediate
  outcome is unknown.
  """

  alias Vxpipe.CallEngine.Telephony.{
    Answer,
    Dial,
    EndLeg,
    Event,
    SendMedia,
    Submission,
    Webhook
  }

  @type config :: term()
  @type error_reason :: atom() | tuple()
  @type event_result :: {:ok, Event.t()} | :ignore | {:error, error_reason()}
  @type submission_result :: {:ok, Submission.t()} | {:error, error_reason()}

  @callback dial(config(), Dial.t()) :: submission_result()
  @callback answer(config(), Answer.t()) :: submission_result()
  @callback send_media(config(), SendMedia.t()) :: :ok | {:error, error_reason()}
  @callback end_leg(config(), EndLeg.t()) :: submission_result()
  @callback verify_webhook(config(), Webhook.t()) :: :ok | {:error, error_reason()}
  @callback decode_webhook(config(), Webhook.t()) :: event_result()
  @callback decode_media_message(config(), binary()) :: event_result()

  @spec dial(module(), config(), Dial.t()) ::
          submission_result() | {:error, :invalid_adapter_response}
  def dial(adapter, config, %Dial{} = request) when is_atom(adapter) do
    adapter.dial(config, request)
    |> validate_submission()
  end

  @spec answer(module(), config(), Answer.t()) ::
          submission_result() | {:error, :invalid_adapter_response}
  def answer(adapter, config, %Answer{} = request) when is_atom(adapter) do
    adapter.answer(config, request)
    |> validate_submission()
  end

  @spec send_media(module(), config(), SendMedia.t()) ::
          :ok | {:error, error_reason() | :invalid_adapter_response}
  def send_media(adapter, config, %SendMedia{} = request) when is_atom(adapter) do
    case adapter.send_media(config, request) do
      :ok -> :ok
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_adapter_response}
    end
  end

  @spec end_leg(module(), config(), EndLeg.t()) ::
          submission_result() | {:error, :invalid_adapter_response}
  def end_leg(adapter, config, %EndLeg{} = request) when is_atom(adapter) do
    adapter.end_leg(config, request)
    |> validate_submission()
  end

  @spec ingest_webhook(module(), config(), Webhook.t()) ::
          {:ok, Event.t()} | :ignore | {:error, error_reason() | :invalid_adapter_response}
  def ingest_webhook(adapter, config, %Webhook{} = webhook) when is_atom(adapter) do
    with :ok <- verify_webhook(adapter, config, webhook) do
      adapter.decode_webhook(config, webhook)
      |> validate_event()
    end
  end

  @spec decode_media_message(module(), config(), binary()) ::
          {:ok, Event.t()} | :ignore | {:error, error_reason() | :invalid_adapter_response}
  def decode_media_message(adapter, config, message)
      when is_atom(adapter) and is_binary(message) do
    adapter.decode_media_message(config, message)
    |> validate_event()
  end

  defp verify_webhook(adapter, config, webhook) do
    case adapter.verify_webhook(config, webhook) do
      :ok -> :ok
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_adapter_response}
    end
  end

  defp validate_submission({:ok, %Submission{} = submission} = result) do
    if Submission.valid?(submission), do: result, else: {:error, :invalid_adapter_response}
  end

  defp validate_submission({:error, _reason} = error), do: error
  defp validate_submission(_other), do: {:error, :invalid_adapter_response}

  defp validate_event({:ok, %Event{} = event} = result) do
    if Event.valid?(event), do: result, else: {:error, :invalid_adapter_response}
  end

  defp validate_event(:ignore), do: :ignore
  defp validate_event({:error, _reason} = error), do: error
  defp validate_event(_other), do: {:error, :invalid_adapter_response}
end
