defmodule Vxpipe.Persistence.TestChangingTelephonyCallRepository do
  @moduledoc false

  alias Vxpipe.Persistence.CallStore

  def claim_incoming_telephony({repo, before_claim}, claim, authorize) do
    before_claim.()
    CallStore.claim_incoming_telephony(repo, claim, authorize)
  end
end
