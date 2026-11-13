defmodule Vxpipe.Persistence.Integration.SharedTelnyxConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    InstallationOperator,
    ProviderCredentials,
    TelephonyServices
  }

  alias Vxpipe.Persistence.{
    CallSpecStore,
    CallStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo,
    TelephonyServiceStore
  }

  alias Vxpipe.Persistence.Schema.{ProviderCredential, TelnyxSettings, Tenant}
  @moduletag :integration

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    original_setting = Repo.get!(TelnyxSettings, 1)

    original_credential =
      Repo.one(
        from(c in ProviderCredential,
          where: c.scope == "platform" and c.provider == "telnyx" and c.name == "telnyx"
        )
      )

    {:ok, keyring} = CredentialKeyring.new("race", %{"race" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}}
    ]

    {:ok, first, _} = Administration.bootstrap_tenant("Shared race first", [:admin], options)
    {:ok, second, _} = Administration.bootstrap_tenant("Shared race second", [:admin], options)
    {:ok, _} = credential(:platform, 1, options)
    :ok = TelephonyServices.configure_platform_application("race-shared", options)

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      keys = [first.key, second.key]
      Repo.delete_all(from(t in Tenant, where: t.key in ^keys))

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(TelnyxSettings, 1),
          application_id: original_setting.application_id
        )
      )

      current =
        Repo.one!(
          from(c in ProviderCredential,
            where: c.scope == "platform" and c.provider == "telnyx" and c.name == "telnyx"
          )
        )

      if original_credential do
        Repo.update!(
          Ecto.Changeset.change(
            current,
            Map.drop(Map.from_struct(original_credential), [:__meta__, :tenant, :id])
          )
        )
      else
        Repo.delete!(current)
      end

      Sandbox.checkin(Repo)
    end)

    %{first: first, second: second, options: options, context: context}
  end

  test "concurrent publication admits only one shared-number owner", data do
    drafts =
      for tenant <- [data.first, data.second] do
        {:ok, _} =
          TelephonyServices.register(
            tenant.key,
            Map.put(application(tenant.key), "provider_connection_id", nil),
            data.options
          )

        {:ok, draft} =
          Calls.save_authorized_call_spec(
            InstallationOperator.authority(),
            tenant.key,
            source(),
            data.options
          )

        draft
      end

    results = race(Enum.map(drafts, fn draft -> fn -> publish(data, draft) end end))
    assert length(Enum.filter(results, &match?({:ok, _}, &1))) == 1
    assert [{:error, :phone_number_in_use}] = Enum.filter(results, &match?({:error, _}, &1))
  end

  test "publication and resetting another tenant's application cannot create an ambiguous route",
       data do
    {:ok, _} =
      TelephonyServices.register(
        data.first.key,
        Map.put(application(data.first.key), "provider_connection_id", nil),
        data.options
      )

    {:ok, own} =
      TelephonyServices.register(data.second.key, application(data.second.key), data.options)

    {:ok, first} =
      Calls.save_authorized_call_spec(
        InstallationOperator.authority(),
        data.first.key,
        source(),
        data.options
      )

    {:ok, second} =
      Calls.save_authorized_call_spec(
        InstallationOperator.authority(),
        data.second.key,
        source(),
        data.options
      )

    {:ok, _} = publish(data, second)

    results =
      race([
        fn -> publish(data, first) end,
        fn ->
          TelephonyServiceStore.update_application(data.context, data.second.key, own.id, %{
            "provider_connection_id" => nil
          })
        end
      ])

    assert length(Enum.filter(results, &match?({:ok, _}, &1))) == 1
    assert [{:error, :phone_number_in_use}] = Enum.filter(results, &match?({:error, _}, &1))
  end

  test "concurrent duplicate admissions persist one call and one provider leg", data do
    {:ok, _} =
      TelephonyServices.register(
        data.first.key,
        Map.put(application(data.first.key), "provider_connection_id", nil),
        data.options
      )

    {:ok, draft} =
      Calls.save_authorized_call_spec(
        InstallationOperator.authority(),
        data.first.key,
        source(),
        data.options
      )

    {:ok, _} = publish(data, draft)

    event = %Vxpipe.CallEngine.Telephony.Event{
      kind: :incoming,
      provider: :telnyx,
      provider_event_id: "race-event",
      provider_connection_id: "race-shared",
      provider_call_control_id: "race-control",
      provider_call_leg_id: "race-leg",
      provider_call_session_id: "race-session",
      occurred_at: DateTime.utc_now(),
      from: "+15550002000",
      to: "+15550001000"
    }

    claim = fn ->
      Calls.claim_incoming_telephony({:tenant, data.first.key}, "support", event, data.options)
    end

    results = race([claim, claim])
    assert [{:ok, admitted}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert [{:duplicate, duplicate}] = Enum.filter(results, &match?({:duplicate, _}, &1))
    assert admitted.call.id == duplicate.call.id
  end

  test "a waiting publication reloads the current spec after acquiring its tenant lock", data do
    input =
      put_in(source(), [:participants, "caller", :connection], %{
        service: "web",
        mode: "receive",
        admission: "start_call"
      })

    {:ok, first} =
      Calls.save_authorized_call_spec(
        InstallationOperator.authority(),
        data.first.key,
        input,
        data.options
      )

    {:ok, _} = publish(data, first)

    {:ok, second} =
      Calls.save_authorized_call_spec(
        InstallationOperator.authority(),
        data.first.key,
        input,
        Keyword.put(data.options, :call_spec_id, first.call_spec_id)
      )

    observer = self()

    {:ok, {worker, monitor}} =
      Repo.transaction(fn ->
        Repo.one!(from(t in Tenant, where: t.key == ^data.first.key, lock: "FOR UPDATE"))

        worker =
          start_supervised!(
            {Task,
             fn ->
               :ok = Sandbox.checkout(Repo, sandbox: false)
               %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
               send(observer, {:waiting_publisher, self(), connection})

               receive do
                 :publish -> send(observer, {:published, self(), publish(data, first)})
               after
                 5_000 -> send(observer, {:published, self(), :timeout})
               end

               Sandbox.checkin(Repo)
             end}
          )

        monitor = Process.monitor(worker)
        assert_receive {:waiting_publisher, ^worker, connection}, 5_000
        send(worker, :publish)

        assert Enum.any?(1..1_000, fn _ ->
                 %{rows: [[waiting]]} =
                   Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [connection])

                 waiting
               end)

        assert {:ok, _} = publish(data, second)
        {worker, monitor}
      end)

    assert_receive {:published, ^worker, {:ok, _}}, 5_000
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 5_000

    assert {:ok, final} =
             CallSpecStore.fetch_published_revision(Repo, data.first.key, first.call_spec_id)

    assert final.revision == first.revision
  end

  defp publish(data, draft),
    do:
      Calls.publish_authorized_call_spec(
        InstallationOperator.authority(),
        draft.tenant_key,
        draft.call_spec_id,
        draft.revision,
        data.options
      )

  defp credential(owner, marker, options),
    do:
      ProviderCredentials.provision(
        owner,
        "telnyx",
        "telnyx",
        "api_key",
        %{"api_key" => "synthetic-scoped-key", "public_key" => public_key(marker)},
        options
      )

  defp public_key(marker), do: Base.encode64(:binary.copy(<<marker>>, 32))

  defp application(tenant),
    do: %{
      "name" => "support",
      "ingress_key" => "phone-#{tenant}",
      "provider" => "telnyx",
      "provider_connection_id" => "application-#{tenant}",
      "credential_name" => "telnyx"
    }

  defp source do
    %{
      schema_version: "20260915.01",
      name: "Scoped phone caller",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "local"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{
            service: "support",
            mode: "receive",
            number: "+15550001000",
            admission: "start_call"
          }
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          tools: %{},
          first_message: %{mode: "wait_for_input"}
        }
      }
    }
  end

  defp race(operations) do
    observer = self()

    workers =
      operations
      |> Enum.with_index()
      |> Enum.map(fn {operation, index} ->
        pid =
          start_supervised!(
            {Task,
             fn ->
               :ok = Sandbox.checkout(Repo, sandbox: false)
               %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
               send(observer, {:ready, self(), connection})

               receive do
                 :run -> send(observer, {:result, self(), operation.()})
               after
                 5_000 -> send(observer, {:result, self(), {:error, :test_timeout}})
               end

               Sandbox.checkin(Repo)
             end},
            id: {:connection_racer, index}
          )

        {pid, Process.monitor(pid)}
      end)

    connections =
      Enum.map(workers, fn {pid, _} ->
        assert_receive {:ready, ^pid, connection}, 5_000
        connection
      end)

    assert length(Enum.uniq(connections)) == length(workers)
    Enum.each(workers, fn {pid, _} -> send(pid, :run) end)

    Enum.map(workers, fn {pid, monitor} ->
      assert_receive {:result, ^pid, result}, 5_000
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
      result
    end)
  end
end
