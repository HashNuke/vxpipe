defmodule Vxpipe.Persistence.TelephonyAdmissionCredentialsTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  import Vxpipe.Persistence.TestTelephonyAdmissionFixture
  alias Vxpipe.Calls
  alias Vxpipe.Persistence.CallStore
  alias Vxpipe.Persistence.Schema.{Call, ProviderCredential, TelephonyLeg, TelephonyService}

  setup do
    Vxpipe.Persistence.TestTelephonyAdmissionFixture.new()
  end

  test "rebinding after compilation prevents both incoming call and leg insertion", data do
    publish(data, source())
    {:ok, replacement} = provision(data.tenant.key, "telnyx", "replacement", data.options)
    original = Repo.get_by!(TelephonyService, public_id: data.service.id)

    for {field, value} <- [
          provider_connection_id: "different-connection",
          public_id: Ecto.UUID.generate(),
          credential_id: replacement.id
        ] do
      options =
        before_claim(data, fn ->
          Repo.update_all(from(s in TelephonyService, where: s.id == ^original.id),
            set: [{field, value}]
          )
        end)

      assert {:error, error} = incoming(data, options)
      assert error.code == :provider_credential_unavailable
      assert error.details["path"] == ["participants", "caller", "connection", "service"]
      assert row_counts() == [0, 0]

      Repo.update_all(from(s in TelephonyService, where: s.id == ^original.id),
        set: [
          provider_connection_id: original.provider_connection_id,
          public_id: original.public_id,
          credential_id: original.credential_id
        ]
      )
    end
  end

  test "a credential revoked or corrupted after compilation cannot authorize admission", data do
    publish(data, source())
    original = Repo.get_by!(ProviderCredential, public_id: data.credential.id)

    corrupt = :binary.copy(<<0>>, byte_size(original.encrypted_payload))

    for changes <- [[status: "revoked"], [encrypted_payload: corrupt]] do
      options =
        before_claim(data, fn ->
          Repo.update_all(from(c in ProviderCredential, where: c.id == ^original.id),
            set: changes
          )
        end)

      assert {:error, %{code: :provider_credential_unavailable}} = incoming(data, options)
      assert row_counts() == [0, 0]

      Repo.update_all(from(c in ProviderCredential, where: c.id == ^original.id),
        set: [status: original.status, encrypted_payload: original.encrypted_payload]
      )
    end
  end

  test "the final incoming write also rechecks model credentials", data do
    {:ok, model} = provision(data.tenant.key, "google", "model", data.options)

    input =
      put_in(source(), [:defaults, :capabilities, :model_inference], %{
        provider: "google",
        model: "gemini-2.5-flash",
        credential_name: "model"
      })

    publish(data, input)

    options =
      before_claim(data, fn ->
        Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^model.id),
          set: [status: "revoked"]
        )
      end)

    assert {:error, %{code: :provider_credential_unavailable}} = incoming(data, options)
    assert row_counts() == [0, 0]
  end

  test "valid credentials preserve admission, duplicate and call conflict outcomes", data do
    publish(data, source())
    assert {:ok, claim} = incoming(data, data.options)
    assert {:duplicate, duplicate} = incoming(data, data.options)
    assert duplicate.call.id == claim.call.id

    assert {:duplicate, ^duplicate} =
             CallStore.claim_incoming_telephony(Repo, claim, fn ->
               flunk("an existing duplicate must not authorize a new write")
             end)

    assert row_counts() == [1, 1]
    refute :erlang.term_to_binary(claim) =~ "incoming-private-marker"

    options = Keyword.put(data.options, :call_id_generator, fn -> claim.call.id end)
    event = %{event() | provider_event_id: "event-2", provider_call_leg_id: "leg-2"}

    assert {:error, :call_id_conflict} =
             Calls.claim_incoming_telephony({:tenant, data.tenant.key}, "support", event, options)

    assert row_counts() == [1, 1]
  end

  defp before_claim(data, operation),
    do:
      Keyword.put(
        data.options,
        :call_repository,
        {Vxpipe.Persistence.TestChangingTelephonyCallRepository, {Repo, operation}}
      )

  defp row_counts, do: Enum.map([Call, TelephonyLeg], &Repo.aggregate(&1, :count))
end
