defmodule Vxpipe.Gateway.TwilioCallScenario do
  @moduledoc false

  alias Vxpipe.Gateway.TelephonyCallScenario

  def build(observer, media_admission, inbound_leg_id, outbound_leg_id, options \\ []) do
    auth_token = "observer:#{:erlang.pid_to_list(observer)}"

    :twilio
    |> TelephonyCallScenario.build(
      observer,
      auth_token,
      media_admission,
      inbound_leg_id,
      outbound_leg_id,
      options
    )
    |> Map.put(:auth_token, auth_token)
  end
end
