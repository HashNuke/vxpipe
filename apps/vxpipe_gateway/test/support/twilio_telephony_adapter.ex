defmodule Vxpipe.Gateway.TestTwilioTelephonyAdapter do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Telephony.Adapter

  alias Vxpipe.CallEngine.Telephony.{Submission, Webhook}
  alias Vxpipe.Providers.Twilio.Adapter, as: TwilioAdapter

  @call_sid "CA00000000000000000000000000000001"

  @impl true
  def dial(options, request) do
    send(observer(options), {:test_twilio_dial, request})

    if unknown?(options) do
      {:ok, %Submission{status: :unknown, provider_call_control_id: nil}}
    else
      {:ok,
       %Submission{
         status: :accepted,
         provider_call_control_id: @call_sid,
         provider_call_leg_id: @call_sid,
         provider_call_session_id: nil
       }}
    end
  end

  @impl true
  def answer(options, request) do
    send(observer(options), {:test_twilio_answer, request})
    TwilioAdapter.answer(options, request)
  end

  @impl true
  def send_media(_options, _request), do: {:error, :not_supported}

  @impl true
  def end_leg(options, request) do
    send(observer(options), {:test_twilio_end_leg, request})

    {:ok,
     %Submission{
       status: :accepted,
       provider_call_control_id: request.leg.provider_call_control_id
     }}
  end

  @impl true
  def verify_webhook(options, %Webhook{} = webhook),
    do: TwilioAdapter.verify_webhook(options, webhook)

  @impl true
  def decode_webhook(options, %Webhook{} = webhook),
    do: TwilioAdapter.decode_webhook(options, webhook)

  @impl true
  def decode_media_message(options, message),
    do: TwilioAdapter.decode_media_message(options, message)

  defp observer(options) do
    [_mode, encoded] = options |> Keyword.fetch!(:auth_token) |> String.split(":", parts: 2)
    encoded |> String.to_charlist() |> :erlang.list_to_pid()
  end

  defp unknown?(options),
    do: String.starts_with?(Keyword.fetch!(options, :auth_token), "unknown:")
end
