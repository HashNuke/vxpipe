defmodule Vxpipe.Calls.PublishRecordingWarningTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Calls.{Administration, CallSpecs}
  alias Vxpipe.Calls.TestMemoryRepository

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: TestMemoryRepository.credential_repository(repository),
      call_spec_repository: TestMemoryRepository.call_spec_repository(repository),
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, _} = Administration.bootstrap_tenant("Example", [:admin], options)

    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        Vxpipe.Calls.TestTelephonyServiceRepository.repository([tenant])
      )

    [tenant: tenant, options: options]
  end

  test "publish recalculates storage warning with current capability, not frozen draft", %{
    tenant: tenant,
    options: options
  } do
    source = Map.put(call_spec_input(), :media_policy, %{record_audio: true})

    # Draft saved when storage available: silent.
    assert {:ok, draft} = CallSpecs.save(tenant.key, source, options)
    assert draft.validation_warnings == []

    # Storage goes away before publish: publish must warn.
    unavailable = Keyword.put(options, :recording_available, false)
    assert {:ok, published} = CallSpecs.publish(tenant.key, draft.call_spec_id, 1, unavailable)

    assert [%{"code" => "recording_unavailable"}] = published.validation_warnings

    # Re-publish after storage returns: warning clears.
    assert {:ok, republished} = CallSpecs.publish(tenant.key, draft.call_spec_id, 1, options)
    assert republished.validation_warnings == []
  end

  test "runtime application setting supplies capability when option is omitted", %{
    tenant: tenant,
    options: options
  } do
    source = Map.put(call_spec_input(), :media_policy, %{record_audio: true})
    previous = Application.fetch_env(:vxpipe_calls, :recording_available)

    try do
      Application.put_env(:vxpipe_calls, :recording_available, false)

      assert {:ok, draft} =
               CallSpecs.save(tenant.key, source, Keyword.delete(options, :recording_available))

      assert [%{"code" => "recording_unavailable"}] = draft.validation_warnings

      Application.put_env(:vxpipe_calls, :recording_available, true)

      assert {:ok, published} =
               CallSpecs.publish(
                 tenant.key,
                 draft.call_spec_id,
                 1,
                 Keyword.delete(options, :recording_available)
               )

      assert published.validation_warnings == []
    after
      case previous do
        {:ok, value} -> Application.put_env(:vxpipe_calls, :recording_available, value)
        :error -> Application.delete_env(:vxpipe_calls, :recording_available)
      end
    end
  end

  defp call_spec_input do
    %{
      schema_version: "20260915.01",
      name: "Example",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
