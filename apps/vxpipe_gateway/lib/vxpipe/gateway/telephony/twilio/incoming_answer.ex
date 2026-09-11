defmodule Vxpipe.Gateway.Telephony.Twilio.IncomingAnswer do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Answer, Submission}
  alias Vxpipe.Gateway.Telephony.Twilio.{CommandCredentials, Identifier}

  @spec prepare(keyword(), Answer.t()) :: {:ok, Submission.t()} | {:error, term()}
  def prepare(options, %Answer{} = request) do
    call_sid = request.leg.provider_call_control_id

    with {:ok, _credentials} <- CommandCredentials.fetch(options),
         true <- Identifier.call_sid?(call_sid),
         :ok <- secure_media_url(request.media_url) do
      {:ok,
       %Submission{
         status: :accepted,
         provider_call_control_id: call_sid,
         provider_call_leg_id: call_sid,
         provider_call_session_id: nil
       }}
    else
      _invalid -> {:error, :invalid_twilio_answer}
    end
  end

  defp secure_media_url(url) do
    case URI.parse(url) do
      %URI{scheme: "wss", host: host} when is_binary(host) and host != "" -> :ok
      _invalid -> :error
    end
  end
end
