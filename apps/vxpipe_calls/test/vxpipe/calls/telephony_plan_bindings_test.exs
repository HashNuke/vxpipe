defmodule Vxpipe.Calls.TelephonyPlanBindingsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation}
  alias Vxpipe.Calls.{CallPlanCompiler, TestTelephonyServiceRepository}

  setup do
    tenant = String.duplicate("a", 16)
    {_module, bindings} = TestTelephonyServiceRepository.repository([%{key: tenant}])
    {:ok, snapshot} = TestTelephonyServiceRepository.resolve(bindings, tenant, "primary-phone")

    {:ok, invocation} =
      CallInvocation.new(
        %{
          call_definition: %{id: "definition-pinned", revision: 1},
          initial_variables: %{},
          transport: %{type: "web"}
        },
        tenant_id: tenant,
        actor_id: "actor-pinned",
        call_id: "call-pinned",
        room_id: "room-pinned"
      )

    options = [
      registries: %{host_tools: %{}},
      telephony_service_repository:
        {Vxpipe.Calls.TestObservedTelephonyServiceRepository, {bindings, self()}}
    ]

    [tenant: tenant, snapshot: snapshot, invocation: invocation, options: options]
  end

  test "host compilation pins one private-free service identity for a shared alias", data do
    assert {:ok, definition} = definition(source())
    assert {:ok, plan} = CallPlanCompiler.compile(definition, data.invocation, data.options)
    service = data.snapshot.service

    assert %{telephony_service: reference} = Map.fetch!(plan.participants, "phone")

    assert Map.from_struct(reference) == %{
             tenant_id: data.tenant,
             service_id: service.id,
             name: service.name,
             provider: service.provider,
             provider_connection_id: service.provider_connection_id,
             credential_id: service.credential_id
           }

    assert Map.fetch!(plan.participants, "backup").telephony_service == reference
    assert Map.fetch!(plan.participants, "caller").telephony_service == nil
    assert Map.fetch!(plan.participants, "assistant").telephony_service == nil
    refute :erlang.term_to_binary(plan) =~ "private-marker"
    assert_received {:service_resolution, tenant, "primary-phone"}
    assert tenant == data.tenant
    refute_received {:service_resolution, _, _}
  end

  test "host compilation cannot borrow a service from another tenant", data do
    assert {:ok, definition} = definition(source())
    invocation = %{data.invocation | tenant_id: String.duplicate("b", 16)}

    assert {:error, error} = CallPlanCompiler.compile(definition, invocation, data.options)
    assert error.code == :provider_credential_unavailable
    assert error.details["path"] == ["participants", "backup", "connection", "service"]
  end

  test "raw embedded compilation needs no host service repository and JSON cannot supply pins",
       data do
    assert {:ok, definition} = definition(source())

    assert {:ok, plan} =
             Vxpipe.CallEngine.compile_definition(definition, data.invocation, %{host_tools: %{}})

    assert Map.fetch!(plan.participants, "phone").telephony_service == nil
    refute_received {:service_resolution, _, _}

    input = put_in(source(), [:participants, "phone", :connection, :service_id], "forged-pin")
    assert {:error, %{code: :invalid_call_definition}} = definition(input)
  end

  defp definition(input),
    do: CallDefinition.new(input, resource_id: "definition-pinned", revision: 1)

  defp source do
    phone = %{
      type: "human",
      connection: %{service: "primary-phone", mode: "dial", number: "+15550001001"}
    }

    %{
      schema_version: "20260915.01",
      name: "Pinned services",
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
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: ["phone", "backup"]
        },
        "phone" => phone,
        "backup" => phone
      }
    }
  end
end
