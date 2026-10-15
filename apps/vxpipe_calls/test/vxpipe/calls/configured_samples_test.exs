defmodule Vxpipe.Calls.ConfiguredSamplesTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.ConfiguredSamples
  alias Vxpipe.Identity.Principal

  test "rejects unknown or call-denied actors before accessing storage" do
    config = %{
      tenant_key: "AAAAAAAAAAAAAAAA",
      call_spec: %{name: "Sample"},
      initial_variables: %{},
      transfer_participant: "support"
    }

    options = [
      call_spec_repository: {MissingRepository, nil},
      call_repository: {MissingRepository, nil}
    ]

    denied = %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new()
    }

    for actor <- [nil, denied, Vxpipe.Calls.InstallationOperator.authority()] do
      assert {:error, :forbidden} = ConfiguredSamples.prepare(actor, config, options)

      assert {:error, :forbidden} =
               ConfiguredSamples.transfer(actor, config, config.tenant_key, "call", options)
    end
  end
end
