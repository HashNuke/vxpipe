defmodule Vxpipe.Gateway.TelnyxCallScenario do
  @moduledoc false

  alias Vxpipe.Gateway.TelephonyCallScenario

  def build(observer, public_key, media_admission, inbound_leg_id, outbound_leg_id, options \\ []) do
    TelephonyCallScenario.build(
      :telnyx,
      observer,
      public_key,
      media_admission,
      inbound_leg_id,
      outbound_leg_id,
      options
    )
  end
end
