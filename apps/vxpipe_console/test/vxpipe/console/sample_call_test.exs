defmodule Vxpipe.Console.SampleCallTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.{SampleCall, TestSampleCallBackend}

  @initial_variables %{"order" => %{"id" => "private-order-sentinel"}}
  @definition %{
    "schema_version" => "20260910.01",
    "entry_caller" => "caller",
    "entry_receiver" => "assistant"
  }

  test "provisions once and prepares through its private API key" do
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
         tenant_name: "Vxpipe test sample"}
      )

    assert {:ok, token} = SampleCall.prepare(sample)
    assert token.tenant_key == TestSampleCallBackend.tenant_key()
    assert token.call_id == TestSampleCallBackend.call_id()
    assert token.participant_key == TestSampleCallBackend.participant_key()
    assert_receive {:sample_call_prepared, call_id}
    assert call_id == TestSampleCallBackend.call_id()

    assert [
             {:bootstrap, "Vxpipe test sample"},
             {:save_definition, tenant_key, @definition},
             {:publish_definition, tenant_key, _definition_id, 1},
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
             |> Enum.count(&match?({:bootstrap, _name}, &1))
  end

  test "reports a disabled sample without exiting the caller" do
    assert {:error, :disabled} = SampleCall.prepare(:sample_call_process_that_is_not_running)
  end

  test "contains a provisioning backend exception without crashing its process" do
    backend =
      start_supervised!(
        {TestSampleCallBackend,
         initial_variables: @initial_variables, observer: self(), bootstrap_exception?: true},
        id: :failing_sample_backend
      )

    child =
      Supervisor.child_spec(
        {SampleCall,
         name: :failing_sample_call,
         backend: TestSampleCallBackend.backend(backend),
         definition: @definition,
         initial_variables: @initial_variables,
         tenant_name: "Unavailable sample"},
        restart: :temporary
      )

    sample = start_supervised!(child)

    assert {:error, :unavailable} = SampleCall.prepare(sample)
    assert Process.alive?(sample)
  end
end
