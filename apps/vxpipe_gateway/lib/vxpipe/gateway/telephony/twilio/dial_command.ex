defmodule Vxpipe.Gateway.Telephony.Twilio.DialCommand do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Dial, Submission}

  alias Vxpipe.Gateway.Telephony.Twilio.{
    CommandCredentials,
    Identifier,
    TwiML,
    VoiceClient
  }

  @spec submit(keyword(), Dial.t()) :: {:ok, Submission.t()} | {:error, term()}
  def submit(options, %Dial{} = request) do
    with {:ok, credentials} <- CommandCredentials.fetch(options),
         {:ok, twiml} <- TwiML.connect_stream(request.media_url) do
      options
      |> VoiceClient.dial(
        credentials.account_sid,
        credentials.auth_token,
        form(request, twiml)
      )
      |> submission()
    end
  end

  defp form(request, twiml) do
    [
      {"To", request.to},
      {"From", request.from},
      {"Twiml", twiml},
      {"StatusCallback", request.callback_url},
      {"StatusCallbackMethod", "POST"},
      {"StatusCallbackEvent", "initiated"},
      {"StatusCallbackEvent", "ringing"},
      {"StatusCallbackEvent", "answered"},
      {"StatusCallbackEvent", "completed"}
    ]
    |> put_answering_machine_detection(request)
  end

  defp put_answering_machine_detection(form, %Dial{
         answering_machine_detection: :detect,
         callback_url: callback_url
       }) do
    form ++
      [
        {"MachineDetection", "Enable"},
        {"AsyncAmd", "true"},
        {"AsyncAmdStatusCallback", callback_url},
        {"AsyncAmdStatusCallbackMethod", "POST"}
      ]
  end

  defp put_answering_machine_detection(form, %Dial{answering_machine_detection: :disabled}),
    do: form

  defp submission({:accepted, %{"sid" => call_sid}}) do
    if Identifier.call_sid?(call_sid) do
      {:ok,
       %Submission{
         status: :accepted,
         provider_call_control_id: call_sid,
         provider_call_leg_id: call_sid,
         provider_call_session_id: nil
       }}
    else
      {:error, :invalid_twilio_command_response}
    end
  end

  defp submission({:accepted, _invalid}), do: {:error, :invalid_twilio_command_response}

  defp submission({:rejected, status}),
    do: {:error, {:twilio_command_rejected, status}}

  defp submission(:unknown),
    do: {:ok, %Submission{status: :unknown, provider_call_control_id: nil}}
end
