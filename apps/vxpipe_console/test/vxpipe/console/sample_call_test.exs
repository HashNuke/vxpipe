defmodule Vxpipe.Console.SampleCallTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.{SampleCall, TestSampleCallBackend}

  @initial_variables %{"order" => %{"id" => "private-order-sentinel"}}
  @definition %{
    "schema_version" => "20260915.01",
    "entry_caller" => "caller",
    "entry_receiver" => "assistant"
  }

  test "uses the selected provisioned tenant and prepares through its private API key" do
    backend =
      start_supervised!(
        {TestSampleCallBackend, initial_variables: @initial_variables, observer: self()}
      )

    sample =
      start_supervised!(
        {SampleCall,
         name: :sample_call_contract_test,
         backend: TestSampleCallBackend.backend(backend),
         definition: @definition,
         initial_variables: @initial_variables,
         tenant_key: TestSampleCallBackend.tenant_key()}
      )

    assert {:ok, token} = SampleCall.prepare(sample)
    assert token.tenant_key == TestSampleCallBackend.tenant_key()
    assert token.call_id == TestSampleCallBackend.call_id()
    assert token.participant_key == TestSampleCallBackend.participant_key()
    assert_receive {:sample_call_prepared, call_id}
    assert call_id == TestSampleCallBackend.call_id()

    assert [
             {:save_definition, tenant_key, @definition},
             {:publish_definition, tenant_key, _definition_id, 1},
             {:issue_api_key, tenant_key},
             {:authenticate, tenant_key, api_key},
             {:prepare_call, tenant_key, participant_key, @initial_variables}
           ] = TestSampleCallBackend.operations(backend)

    assert tenant_key == TestSampleCallBackend.tenant_key()
    assert participant_key == TestSampleCallBackend.participant_key()
    assert api_key == TestSampleCallBackend.api_key()

    status = sample |> :sys.get_state() |> inspect()
    refute status =~ TestSampleCallBackend.api_key()
    refute status =~ "private-order-sentinel"

    assert {:ok, _second_token} = SampleCall.prepare(sample)

    assert 1 ==
             backend
             |> TestSampleCallBackend.operations()
             |> Enum.count(&match?({:issue_api_key, _tenant}, &1))
  end

  test "issues a transfer-destination token only after a sample call is prepared" do
    backend =
      start_supervised!(
        {TestSampleCallBackend, initial_variables: @initial_variables, observer: self()},
        id: :sample_transfer_backend
      )

    sample =
      start_supervised!(
        {SampleCall,
         name: :sample_transfer_call,
         backend: TestSampleCallBackend.backend(backend),
         definition: @definition,
         initial_variables: @initial_variables,
         tenant_key: TestSampleCallBackend.tenant_key(),
         transfer_participant: "human-support"}
      )

    assert {:error, :call_not_prepared} = SampleCall.prepare_transfer(sample)
    assert {:ok, caller_token} = SampleCall.prepare(sample)
    assert {:ok, transfer_token} = SampleCall.prepare_transfer(sample)

    assert transfer_token.call_id == caller_token.call_id
    assert transfer_token.participant_ref == "human-support"
    assert transfer_token.participant_key == TestSampleCallBackend.transfer_participant_key()

    assert 1 ==
             backend
             |> TestSampleCallBackend.operations()
             |> Enum.count(&match?({:issue_api_key, _tenant}, &1))
  end

  test "reports a disabled sample without exiting the caller" do
    assert {:error, :disabled} = SampleCall.prepare(:sample_call_process_that_is_not_running)
  end

  test "contains a provisioning backend exception without crashing its process" do
    backend =
      start_supervised!(
        {TestSampleCallBackend,
         initial_variables: @initial_variables, observer: self(), authorization_exception?: true},
        id: :failing_sample_backend
      )

    child =
      Supervisor.child_spec(
        {SampleCall,
         name: :failing_sample_call,
         backend: TestSampleCallBackend.backend(backend),
         definition: @definition,
         initial_variables: @initial_variables,
         tenant_key: TestSampleCallBackend.tenant_key()},
        restart: :temporary
      )

    sample = start_supervised!(child)

    assert {:error, :unavailable} = SampleCall.prepare(sample)
    assert %{status: {:failed, :backend_unavailable}} = :sys.get_state(sample)
  end

  test "restart keeps the selected tenant and never creates a replacement tenant" do
    backend =
      start_supervised!(
        {TestSampleCallBackend, initial_variables: @initial_variables, observer: self()}
      )

    options = [
      name: nil,
      backend: TestSampleCallBackend.backend(backend),
      definition: @definition,
      initial_variables: @initial_variables,
      tenant_key: TestSampleCallBackend.tenant_key()
    ]

    first = start_supervised!({SampleCall, options}, id: :first_sample)
    assert {:ok, first_token} = SampleCall.prepare(first)
    stop_supervised!(:first_sample)
    second = start_supervised!({SampleCall, options}, id: :second_sample)
    assert {:ok, second_token} = SampleCall.prepare(second)
    assert second_token.tenant_key == first_token.tenant_key
    refute Enum.any?(TestSampleCallBackend.operations(backend), &match?({:bootstrap, _}, &1))
  end

  test "a failed definition save does not issue a call key or create another tenant" do
    backend =
      start_supervised!(
        {TestSampleCallBackend,
         initial_variables: @initial_variables, observer: self(), save_error?: true}
      )

    sample =
      start_supervised!(
        {SampleCall,
         name: nil,
         backend: TestSampleCallBackend.backend(backend),
         definition: @definition,
         initial_variables: @initial_variables,
         tenant_key: TestSampleCallBackend.tenant_key()}
      )

    assert {:error, :unavailable} = SampleCall.prepare(sample)
    assert {:error, :unavailable} = SampleCall.prepare(sample)

    assert Enum.all?(
             TestSampleCallBackend.operations(backend),
             &match?({:save_definition, _, _}, &1)
           )
  end
end
