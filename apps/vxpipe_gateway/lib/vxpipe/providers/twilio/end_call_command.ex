defmodule Vxpipe.Providers.Twilio.EndCallCommand do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{EndLeg, Submission}

  alias Vxpipe.Providers.Twilio.{
    CommandCredentials,
    Identifier,
    VoiceClient
  }

  @spec submit(keyword(), EndLeg.t()) :: {:ok, Submission.t()} | {:error, term()}
  def submit(options, %EndLeg{} = request) do
    call_sid = request.leg.provider_call_control_id

    with {:ok, credentials} <- CommandCredentials.fetch(options),
         true <- Identifier.call_sid?(call_sid) do
      options
      |> VoiceClient.end_call(credentials.account_sid, credentials.auth_token, call_sid)
      |> submission(call_sid)
    else
      false -> {:error, :invalid_twilio_call_sid}
      {:error, _reason} = error -> error
    end
  end

  defp submission({:accepted, %{"sid" => call_sid}}, call_sid) do
    {:ok, %Submission{status: :accepted, provider_call_control_id: call_sid}}
  end

  defp submission({:accepted, _invalid}, _call_sid),
    do: {:error, :invalid_twilio_command_response}

  defp submission({:rejected, status}, _call_sid),
    do: {:error, {:twilio_command_rejected, status}}

  defp submission(:unknown, call_sid),
    do: {:ok, %Submission{status: :unknown, provider_call_control_id: call_sid}}
end
