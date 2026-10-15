defmodule Vxpipe.Calls.CallCreationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    InstallationOperator,
    TestMemoryRepository,
    TestTelephonyServiceRepository
  }

  alias Vxpipe.Identity.Principal, as: UserPrincipal

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: {TestMemoryRepository, repository},
      call_spec_repository: {TestMemoryRepository, repository},
      call_repository: {TestMemoryRepository, repository},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("Call creation", [:calls], options)
    {:ok, actor} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        TestTelephonyServiceRepository.repository([tenant])
      )

    published = publish(tenant.key, source(), options)

    %{
      tenant: tenant.key,
      actor: actor,
      options: options,
      published: published,
      repository: repository
    }
  end

  test "web spec claims pin nested variables without issuing a token or starting the call", c do
    variables = %{"order" => %{"id" => "ORDER-1", "nested" => %{"count" => 2}}}

    options =
      Keyword.put(c.options, :join_token_generator, fn ->
        flunk("creation must not mint a token")
      end)

    assert {:ok, call} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               c.published.call_spec_id,
               variables,
               nil,
               nil,
               options
             )

    assert call.state == :prepared
    assert call.plan.direction == :incoming
    assert call.started_at == nil
    assert call.initial_variables == variables
    assert call.plan.call_variables.sections["order"].value == variables["order"]
    assert {:ok, ^call} = Calls.fetch_call(c.tenant, call.id, c.options)

    assert {:ok, omitted} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               c.published.call_spec_id,
               %{},
               nil,
               nil,
               c.options
             )

    assert omitted.plan.call_variables.sections["order"].value == nil
    refute omitted.id == call.id

    for variables <- [%{"order" => %{"id" => 2}}, %{"unknown" => %{}}] do
      assert {:error, %{code: :call_spec_resolution_failed}} =
               Calls.claim_call(
                 c.actor,
                 c.tenant,
                 c.published.call_spec_id,
                 variables,
                 nil,
                 nil,
                 c.options
               )
    end
  end

  test "shared authorization uses actual machine and browser actors before storage", c do
    platform = %InstallationOperator{
      grant: :installation_operator,
      credential_kind: :platform_api_key,
      api_key_id: "platform"
    }

    browser = %UserPrincipal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(["calls.write"]),
      assigned_tenants: %{c.tenant => :read_write},
      all_tenant_actions: MapSet.new()
    }

    for actor <- [platform, browser] do
      assert {:ok, _call} =
               Calls.claim_call(
                 actor,
                 c.tenant,
                 c.published.call_spec_id,
                 %{},
                 nil,
                 nil,
                 c.options
               )
    end

    assert :ok = Calls.authorize_call_management(c.actor)
    assert :ok = Calls.authorize_call_management(platform)

    for {actor, tenant} <- [
          {%{c.actor | scopes: MapSet.new([:admin])}, c.tenant},
          {c.actor, "BBBBBBBBBBBBBBBB"},
          {%{browser | grants: MapSet.new(["calls.read"])}, c.tenant},
          {InstallationOperator.authority(), c.tenant},
          {nil, c.tenant}
        ] do
      assert {:error, _reason} =
               Calls.claim_call(actor, tenant, c.published.call_spec_id, %{}, nil, nil,
                 call_repository: {__MODULE__, :must_not_call}
               )
    end
  end

  test "idempotency replays before publication reads and shares the outgoing namespace", c do
    assert {:ok, call} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               c.published.call_spec_id,
               %{},
               nil,
               "retry",
               c.options
             )

    no_publication_reads =
      Keyword.put(c.options, :call_spec_repository, {__MODULE__, :must_not_read})

    assert {:duplicate, ^call} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               c.published.call_spec_id,
               %{},
               nil,
               "retry",
               no_publication_reads
             )

    assert {:error, :idempotency_conflict} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               c.published.call_spec_id,
               %{"order" => %{"id" => "changed"}},
               nil,
               "retry",
               c.options
             )

    outgoing = publish(c.tenant, outgoing_source(), c.options)

    assert {:error, :idempotency_conflict} =
             Calls.claim_outgoing_call(c.actor, outgoing.call_spec_id, %{}, "retry", c.options)

    assert {:ok, dial} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               outgoing.call_spec_id,
               %{},
               nil,
               "dial",
               c.options
             )

    assert dial.state == :admitting

    assert {:duplicate, ^dial} =
             Calls.claim_outgoing_call(c.actor, outgoing.call_spec_id, %{}, "dial", c.options)

    assert {:ok, failed} = Calls.mark_outgoing_call_failed(dial, :startup_unknown, c.options)

    assert {:duplicate, ^failed} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               outgoing.call_spec_id,
               %{},
               nil,
               "dial",
               no_publication_reads
             )
  end

  test "concurrent web claims have one winner and no extra call", c do
    results =
      1..8
      |> Task.async_stream(
        fn _ ->
          Calls.claim_call(
            c.actor,
            c.tenant,
            c.published.call_spec_id,
            %{},
            nil,
            "concurrent",
            c.options
          )
        end,
        max_concurrency: 8,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert [{:ok, call}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert Enum.count(results, &(&1 == {:duplicate, call})) == 7
  end

  test "selects publication once and retains its eligible token route after republication", c do
    {:ok, newer} =
      Calls.save_call_spec(
        c.tenant,
        source(),
        Keyword.put(c.options, :call_spec_id, c.published.call_spec_id)
      )

    options =
      Keyword.put(
        c.options,
        :call_spec_repository,
        {__MODULE__,
         {c.repository,
          fn ->
            Calls.publish_call_spec(c.tenant, newer.call_spec_id, newer.revision, c.options)
          end}}
      )

    assert {:ok, call} =
             Calls.claim_call(c.actor, c.tenant, c.published.call_spec_id, %{}, nil, nil, options)

    assert call.call_spec_revision == 1
    assert {:ok, token} = Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, c.options)
    assert call.participant_routes[token.participant_key] == call.entry_caller
    assert token.participant_key in Enum.map(c.published.routes, & &1.key)
    scope = %{tenant_key: c.tenant, call_id: call.id, participant_key: token.participant_key}
    assert {:ok, claim} = Calls.claim_join_token(token.secret, scope, c.options)
    assert claim.call.call_spec_revision == 1

    assert {:error, :token_already_claimed} =
             Calls.claim_join_token(token.secret, scope, c.options)

    assert {:ok, _failed} = Calls.mark_call_failed(claim, :room_start_failed, c.options)

    assert {:error, :call_unavailable} =
             Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, c.options)
  end

  test "rejects unsupported entries, invalid destinations and missing or foreign specs", c do
    carrier =
      source()
      |> put_in([:participants, "caller", :connection], %{
        service: "primary-phone",
        mode: "receive",
        admission: "start_call",
        number: "+15550001000"
      })

    incoming = publish(c.tenant, carrier, c.options)

    assert {:error, :unsupported_call_entry} =
             Calls.claim_call(c.actor, c.tenant, incoming.call_spec_id, %{}, nil, nil, c.options)

    assert {:error, :to_not_allowed} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               c.published.call_spec_id,
               %{},
               "+15550001000",
               nil,
               c.options
             )

    assert {:error, :not_found} =
             Calls.claim_call(c.actor, c.tenant, "999999", %{}, nil, nil, c.options)

    {:ok, draft} = Calls.save_call_spec(c.tenant, source(), c.options)

    assert {:error, :call_spec_not_published} =
             Calls.claim_call(c.actor, c.tenant, draft.call_spec_id, %{}, nil, nil, c.options)

    dynamic =
      outgoing_source()
      |> update_in([:participants, "caller", :connection], &Map.delete(&1, :number))
      |> then(&publish(c.tenant, &1, c.options))

    assert {:error, :to_required} =
             Calls.claim_call(c.actor, c.tenant, dynamic.call_spec_id, %{}, nil, nil, c.options)

    assert {:error, :invalid_to} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               dynamic.call_spec_id,
               %{},
               "invalid",
               nil,
               c.options
             )

    assert {:ok, dial} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               dynamic.call_spec_id,
               %{},
               "+15550001009",
               nil,
               c.options
             )

    assert dial.to_number == "+15550001009"
  end

  test "token selection checks pinned web eligibility and bounded lifetime", c do
    assert {:ok, call} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               c.published.call_spec_id,
               %{},
               nil,
               nil,
               c.options
             )

    for ttl <- [300, 86_400] do
      assert {:ok, token} =
               Calls.issue_call_join_token(
                 c.actor,
                 c.tenant,
                 call.id,
                 nil,
                 Keyword.put(c.options, :join_token_ttl_seconds, ttl)
               )

      assert DateTime.diff(token.expires_at, token.issued_at) == ttl
    end

    for ttl <- [299, 86_401, "300"] do
      assert {:error, :invalid_join_token_configuration} =
               Calls.issue_call_join_token(
                 c.actor,
                 c.tenant,
                 call.id,
                 nil,
                 Keyword.put(c.options, :join_token_ttl_seconds, ttl)
               )
    end

    assert {:error, :participant_not_found} =
             Calls.issue_call_join_token(c.actor, c.tenant, call.id, "missing", c.options)

    assert {:error, :not_found} =
             Calls.issue_call_join_token(c.actor, c.tenant, "missing", nil, c.options)

    ref = call.entry_caller
    participant = Map.fetch!(call.plan.participants, ref)

    plan = %{
      call.plan
      | participants:
          Map.put(call.plan.participants, ref, %{
            participant
            | connection: %{participant.connection | service: "phone"}
          })
    }

    forged = %{call | plan: plan}
    options = Keyword.put(c.options, :call_repository, {__MODULE__, forged})

    assert {:error, :participant_required} =
             Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, options)

    key = call.participant_routes |> Map.keys() |> hd()

    assert {:error, :participant_not_found} =
             Calls.issue_call_join_token(c.actor, c.tenant, call.id, key, options)

    refute_received :token_stored
  end

  def fetch_published_revision({repository, after_read}, tenant, id) do
    result = TestMemoryRepository.fetch_published_revision(repository, tenant, id)
    after_read.()
    result
  end

  def fetch_call(call, _tenant, _id), do: {:ok, call}

  def issue_join_token(_call, _tenant, _id, _participant, token) do
    send(self(), :token_stored)
    {:ok, token}
  end

  defp publish(tenant, source, options) do
    {:ok, draft} = Calls.save_call_spec(tenant, source, options)

    {:ok, published} =
      Calls.publish_call_spec(tenant, draft.call_spec_id, draft.revision, options)

    published
  end

  defp outgoing_source do
    source()
    |> Map.delete(:incoming_call)
    |> Map.put(:outgoing_call, %{
      callee: "caller",
      handled_by: "assistant",
      ring_timeout_ms: 5_000
    })
    |> put_in([:participants, "caller", :connection], %{
      service: "primary-phone",
      mode: "dial",
      number: "+15550001000"
    })
  end

  defp source do
    %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      call_variables: %{
        sections: %{
          "order" => %{
            schema: %{
              type: "object",
              properties: %{
                "id" => %{type: "string"},
                "nested" => %{type: "object", properties: %{"count" => %{type: "integer"}}}
              },
              required: ["id"]
            }
          }
        }
      },
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{type: "agent", prompt: "Help."}
      }
    }
  end
end
