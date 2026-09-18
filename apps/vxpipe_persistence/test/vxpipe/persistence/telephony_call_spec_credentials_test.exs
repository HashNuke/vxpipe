defmodule Vxpipe.Persistence.TelephonyCallSpecCredentialsTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, ProviderCredentials, TelephonyServices}
  alias Vxpipe.Persistence.{CallStore, CredentialKeyring, CredentialStore, CallSpecStore}
  alias Vxpipe.Persistence.{ProviderCredentialStore, TelephonyServiceStore}
  alias Vxpipe.Persistence.Schema.{Call, CallSpecRevision, ParticipantRoute, ProviderCredential}

  setup do
    {:ok, keyring} = CredentialKeyring.new("v1", %{"v1" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, issued} =
      Administration.bootstrap_tenant("Phone call_specs", [:calls], options)

    {:ok, principal} = Administration.authenticate(tenant.key, issued.secret, :calls, options)
    {:ok, other, _} = Administration.bootstrap_tenant("Other phone tenant", [:calls], options)
    [tenant: tenant, other: other, principal: principal, options: options, context: context]
  end

  test "a missing later phone destination is a hard save failure with no revision or route",
       data do
    assert {:error, error} = Calls.save_call_spec(data.tenant.key, source(), data.options)
    assert error.code == :provider_credential_unavailable
    assert error.details["path"] == ["participants", "phone", "connection", "service"]
    assert row_counts() == [0, 0, 0]
  end

  test "a same-name service in another tenant cannot authorize a save", data do
    register(data.other.key, data.options)

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.save_call_spec(data.tenant.key, source(), data.options)

    assert row_counts() == [0, 0, 0]
  end

  test "saved and prepared phone intent requires the current active credential without persisting it",
       data do
    {credential, _service} = register(data.tenant.key, data.options)
    assert {:ok, draft} = Calls.save_call_spec(data.tenant.key, source(), data.options)
    assert draft.validation_errors == []

    assert {:ok, published} =
             Calls.publish_call_spec(data.tenant.key, draft.call_spec_id, 1, data.options)

    assert [route] = published.routes
    assert {:ok, call, _token} = Calls.prepare_call(data.principal, route.key, %{}, data.options)
    refute :erlang.term_to_binary({draft, call}) =~ "private-marker"

    assert {:error, :call_id_conflict} =
             Calls.prepare_call(
               data.principal,
               route.key,
               %{},
               Keyword.put(data.options, :call_id_generator, fn -> call.id end)
             )

    revoke(credential.id)
    before = row_counts()

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.publish_call_spec(data.tenant.key, draft.call_spec_id, 1, data.options)

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.prepare_call(data.principal, route.key, %{}, data.options)

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.save_call_spec(data.tenant.key, source(), data.options)

    assert row_counts() == before
  end

  test "revocation after preflight prevents the final revision or prepared-call write", data do
    register(data.tenant.key, data.options)
    assert {:ok, draft} = Calls.save_call_spec(data.tenant.key, source(), data.options)

    assert {:ok, published} =
             Calls.publish_call_spec(data.tenant.key, draft.call_spec_id, 1, data.options)

    assert [route] = published.routes

    for operation <- [:save, :prepare] do
      Repo.update_all(ProviderCredential, set: [status: "active"])
      switch = start_supervised!({Agent, fn -> true end}, id: operation)

      options =
        Keyword.put(data.options, :telephony_service_repository, {
          Vxpipe.Persistence.TestRevokingTelephonyServiceRepository,
          Keyword.put(data.context, :revocation_switch, switch)
        })

      before = row_counts()

      result =
        case operation do
          :save -> Calls.save_call_spec(data.tenant.key, source(), options)
          :prepare -> Calls.prepare_call(data.principal, route.key, %{}, options)
        end

      assert {:error, %{code: :provider_credential_unavailable}} = result
      assert row_counts() == before
    end
  end

  test "prepared service identity survives storage and participates in the immutable digest",
       data do
    {credential, service} = register(data.tenant.key, data.options)
    {published, route} = publish(data, source())
    assert {:ok, call, _token} = Calls.prepare_call(data.principal, route.key, %{}, data.options)
    assert {:ok, stored} = Calls.fetch_call(data.tenant.key, call.id, data.options)
    reference = Map.fetch!(stored.plan.participants, "phone").telephony_service
    assert reference.service_id == service.id
    assert reference.credential_id == credential.id
    assert reference.tenant_id == data.tenant.key
    assert stored.plan == call.plan
    assert stored.call_spec_revision == published.revision

    assert stored.plan_digest ==
             :crypto.hash(:sha256, :erlang.term_to_binary(stored.plan, [:deterministic]))

    refute :erlang.term_to_binary(stored.plan) =~ "private-marker"
  end

  test "rebinding the account, service or credential after compile prevents the final write",
       data do
    {_credential, service} = register(data.tenant.key, data.options)
    {_published, route} = publish(data, source())

    {:ok, replacement} =
      ProviderCredentials.provision(
        data.tenant.key,
        "telnyx",
        "replacement",
        "api_key",
        %{"api_key" => "replacement-private-marker"},
        data.options
      )

    schema = Vxpipe.Persistence.Schema.TelephonyService
    original = Repo.get_by!(schema, public_id: service.id)

    for {field, value} <- [
          provider_connection_id: "different-account",
          public_id: Vxpipe.Calls.PublicId.uuid(),
          credential_id: replacement.id
        ] do
      options =
        Keyword.put(data.options, :join_token_generator, fn ->
          Repo.update_all(from(s in schema, where: s.id == ^original.id), set: [{field, value}])
          "vxj_test-only-service-binding-race"
        end)

      before = row_counts()

      assert {:error, %{code: :provider_credential_unavailable}} =
               Calls.prepare_call(data.principal, route.key, %{}, options)

      assert row_counts() == before

      Repo.update_all(from(s in schema, where: s.id == ^original.id),
        set: [
          provider_connection_id: original.provider_connection_id,
          public_id: original.public_id,
          credential_id: original.credential_id
        ]
      )
    end
  end

  test "every shared-alias participant is checked and historical plans are never repinned",
       data do
    register(data.tenant.key, data.options)
    input = source()
    input = put_in(input, [:participants, "backup"], input.participants["phone"])
    {published, route} = publish(data, input)
    assert {:ok, call, _token} = Calls.prepare_call(data.principal, route.key, %{}, data.options)
    phone = Map.fetch!(call.plan.participants, "phone")
    reference = phone.telephony_service

    for bad_reference <- [
          %{reference | tenant_id: data.other.key},
          %{reference | service_id: Vxpipe.Calls.PublicId.uuid()},
          %{reference | name: "another-alias"},
          %{reference | provider: "another-provider"},
          %{reference | provider_connection_id: "another-account"},
          %{reference | credential_id: Vxpipe.Calls.PublicId.uuid()},
          nil
        ] do
      bad_phone = %{phone | telephony_service: bad_reference}
      plan = %{call.plan | participants: Map.put(call.plan.participants, "phone", bad_phone)}
      assert_rejected_plan(published, plan, data.options)
    end

    legacy_phone = Map.delete(phone, :telephony_service)
    legacy = %{call.plan | participants: Map.put(call.plan.participants, "phone", legacy_phone)}
    encoded = :erlang.term_to_binary(legacy, [:deterministic])
    assert {:ok, ^legacy} = Vxpipe.Persistence.ResolvedPlanCodec.decode(encoded)
    assert_rejected_plan(published, legacy, data.options)
  end

  test "service lookup and encryption failures authorize no write or callback", data do
    register(data.tenant.key, data.options)

    {:ok, wrong_keyring} = CredentialKeyring.new("v1", %{"v1" => :crypto.strong_rand_bytes(32)})

    for keyring <- [nil, wrong_keyring] do
      context = Keyword.put(data.context, :keyring, keyring)

      options =
        Keyword.put(data.options, :telephony_service_repository, {TelephonyServiceStore, context})

      assert {:error, %{code: :provider_credential_unavailable}} =
               Calls.save_call_spec(data.tenant.key, source(), options)

      assert {:error, _reason} =
               TelephonyServices.with_active(
                 data.tenant.key,
                 [%{name: "support", path: ["service"]}],
                 options,
                 fn -> send(self(), :unauthorized_callback) end
               )

      refute_received :unauthorized_callback
    end

    assert row_counts() == [0, 0, 0]
  end

  test "the service guard and authorized write share a transaction and roll back together",
       data do
    register(data.tenant.key, data.options)
    before = Repo.aggregate(Vxpipe.Persistence.Schema.Tenant, :count)

    assert {:error, :controlled_write_failure} =
             TelephonyServices.with_active(
               data.tenant.key,
               [%{name: "support", path: ["service"]}],
               data.options,
               fn ->
                 assert Repo.in_transaction?()

                 {:ok, _, _} =
                   Administration.bootstrap_tenant("Rolled back", [:calls], data.options)

                 {:error, :controlled_write_failure}
               end
             )

    assert Repo.aggregate(Vxpipe.Persistence.Schema.Tenant, :count) == before
  end

  @tag :tmp_dir
  test "a fresh VM decodes a pinned plan while unknown stored atoms remain rejected", data do
    on_exit(fn -> File.rm_rf!(data.tmp_dir) end)
    register(data.tenant.key, data.options)

    input =
      Map.merge(source(), %{
        tool_visibility: "full",
        call_variables: %{
          sections: %{
            "order" => %{
              schema: %{
                "type" => "object",
                "properties" => %{"id" => %{"type" => "string", "minLength" => 1}},
                "required" => ["id"],
                "additionalProperties" => false
              }
            }
          }
        }
      })

    input =
      put_in(input, [:participants, "assistant", :variable_permissions], %{"order" => ["read"]})

    {_published, route} = publish(data, input)

    assert {:ok, call, _token} =
             Calls.prepare_call(
               data.principal,
               route.key,
               %{"order" => %{"id" => "fixture"}},
               data.options
             )

    path = Path.join(data.tmp_dir, "plan.etf")
    File.write!(path, :erlang.term_to_binary(call.plan, [:deterministic]))
    unknown_name = "untrusted_atom_" <> Vxpipe.Calls.PublicId.uuid()
    File.write!(path <> ".unknown", <<131, 119, byte_size(unknown_name), unknown_name::binary>>)

    script = """
    [path, unknown_name] = System.argv()
    Application.load(:vxpipe_call_engine)
    case Vxpipe.Persistence.ResolvedPlanCodec.decode(File.read!(path)) do
      {:ok, _plan} ->
        {:error, :invalid_stored_call_plan} =
          Vxpipe.Persistence.ResolvedPlanCodec.decode(File.read!(path <> ".unknown"))
        try do
          String.to_existing_atom(unknown_name)
          IO.puts("unknown atom was interned")
        rescue
          ArgumentError -> IO.puts("decoded; unknown atom rejected")
        end
      {:error, :invalid_stored_call_plan} -> IO.puts("unreadable")
    end
    """

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])
    arguments = ["--erl", "+S 2:2"] ++ paths ++ ["-e", script, "--", path, unknown_name]

    assert {"decoded; unknown atom rejected\n", 0} =
             System.cmd("elixir", arguments, stderr_to_stdout: true)
  end

  defp assert_rejected_plan(revision, plan, options) do
    assert {:error, %{code: :provider_credential_unavailable}} =
             Vxpipe.Calls.CallSpecCredentials.with_active(revision, plan, options, fn ->
               send(self(), :unexpected_plan_write)
               :ok
             end)

    refute_received :unexpected_plan_write
  end

  defp publish(data, input) do
    {:ok, draft} = Calls.save_call_spec(data.tenant.key, input, data.options)

    {:ok, published} =
      Calls.publish_call_spec(data.tenant.key, draft.call_spec_id, 1, data.options)

    [route] = published.routes
    {published, route}
  end

  defp register(tenant, options) do
    {:ok, credential} =
      ProviderCredentials.provision(
        tenant,
        "telnyx",
        "phone",
        "api_key",
        %{"api_key" => "#{tenant}-private-marker"},
        options
      )

    {:ok, service} =
      TelephonyServices.register(
        tenant,
        %{
          "name" => "support",
          "ingress_key" => "phone-#{tenant}",
          "provider" => "telnyx",
          "provider_connection_id" => "connection-1",
          "credential_id" => credential.id,
          "public_key" => Base.encode64(:binary.copy(<<1>>, 32))
        },
        options
      )

    {credential, service}
  end

  defp revoke(id),
    do:
      Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^id),
        set: [status: "revoked"]
      )

  defp row_counts,
    do: Enum.map([CallSpecRevision, ParticipantRoute, Call], &Repo.aggregate(&1, :count))

  defp source do
    %{
      schema_version: "20260915.01",
      name: "Phone destination",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "local"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          tools: %{},
          transfers: ["phone"],
          first_message: %{mode: "wait_for_input"}
        },
        "phone" => %{
          type: "human",
          connection: %{service: "support", mode: "dial", number: "+15550001001"}
        }
      }
    }
  end
end
