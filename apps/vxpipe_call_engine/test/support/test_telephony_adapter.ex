defmodule Vxpipe.CallEngine.TestTelephonyAdapter do
  @behaviour Vxpipe.CallEngine.Telephony.Adapter

  alias Vxpipe.CallEngine.Telephony.{Event, Submission}

  @impl true
  def dial(config, request), do: command(config, :dial, request)

  @impl true
  def answer(config, request), do: command(config, :answer, request)

  @impl true
  def send_media(config, request), do: command(config, :send_media, request)

  @impl true
  def end_leg(config, request), do: command(config, :end_leg, request)

  @impl true
  def verify_webhook(config, webhook) do
    send(config.observer, {:fake_telephony, :verify_webhook, webhook})

    if webhook.headers["fake-signature"] == config.signature,
      do: :ok,
      else: {:error, :invalid_signature}
  end

  @impl true
  def decode_webhook(config, webhook) do
    send(config.observer, {:fake_telephony, :decode_webhook, webhook})
    decode_event(webhook.body)
  end

  @impl true
  def decode_media_message(config, message) do
    send(config.observer, {:fake_telephony, :decode_media_message, message})
    decode_event(message)
  end

  defp command(config, operation, request) do
    send(config.observer, {:fake_telephony, operation, request})

    case Map.get(config, :outcomes, %{}) |> Map.get(operation, :accepted) do
      :accepted ->
        {:ok,
         %Submission{
           status: :accepted,
           provider_call_control_id: "provider-call-control"
         }}

      :unknown ->
        {:ok, %Submission{status: :unknown, provider_call_control_id: nil}}

      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_event(body) do
    case :erlang.binary_to_term(body, [:safe]) do
      %Event{} = event -> {:ok, event}
      _other -> {:error, :invalid_event}
    end
  rescue
    ArgumentError -> {:error, :invalid_event}
  end
end
