defmodule Vxpipe.CallEngine.CallSpec.DirectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, Error}

  test "compiled plans retain the direction, deadline and outgoing opening default" do
    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "direction", revision: 1},
                 transport: %{type: "web"},
                 initial_variables: %{}
               },
               tenant_id: "tenant",
               actor_id: "actor"
             )

    for {source, direction, timeout} <- [
          {incoming(), :incoming, nil},
          {outgoing(), :outgoing, 30_000}
        ] do
      source =
        Map.put(source, :defaults, %{
          capabilities: %{model_inference: %{provider: "fixture", model: "local"}}
        })

      assert {:ok, spec} = parse(source)
      assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
      assert plan.direction == direction
      assert plan.ring_timeout_ms == timeout

      assert Map.fetch!(plan.participants, plan.entry_caller).connection ==
               Map.fetch!(spec.participants, spec.entry_caller).connection

      assert Map.fetch!(plan.participants, plan.entry_receiver).first_message ==
               Map.fetch!(spec.participants, spec.entry_receiver).first_message
    end
  end

  test "accepts incoming atom and JSON shapes with the existing silent default" do
    for input <- [incoming(), incoming() |> JSON.encode!() |> JSON.decode!()] do
      assert {:ok, spec} = parse(input)
      assert spec.direction == :incoming
      assert spec.entry_caller == "customer"
      assert spec.entry_receiver == "assistant"
      assert spec.ring_timeout_ms == nil
      assert Map.fetch!(spec.participants, "assistant").first_message == :wait_for_input
    end
  end

  test "requires exactly one direction and rejects legacy entries in the new version" do
    invalid(Map.delete(incoming(), :incoming_call), [])
    invalid(Map.put(incoming(), :outgoing_call, outgoing().outgoing_call), [])
    invalid(Map.put(incoming(), :entry_caller, "customer"), ["entry_caller"])
    invalid(Map.put(incoming(), :entry_receiver, "assistant"), ["entry_receiver"])
    invalid(%{incoming() | incoming_call: nil}, ["incoming_call"])

    invalid(put_in(incoming(), [:incoming_call, :unexpected], true), [
      "incoming_call",
      "unexpected"
    ])
  end

  test "validates direction participant references and connection intent" do
    for {input, path} <- [
          {put_in(incoming(), [:incoming_call, :caller], "missing"), ["incoming_call", "caller"]},
          {put_in(incoming(), [:incoming_call, :handled_by], "missing"),
           ["incoming_call", "handled_by"]},
          {put_in(incoming(), [:incoming_call, :handled_by], "customer"),
           ["incoming_call", "handled_by"]},
          {put_in(incoming(), [:incoming_call], %{caller: "assistant", handled_by: "customer"}),
           ["incoming_call", "caller"]},
          {put_in(incoming(), [:participants, "customer", :connection, :admission], "transfer"),
           ["incoming_call", "caller"]},
          {Map.put(outgoing(), :incoming_call, incoming().incoming_call)
           |> Map.delete(:outgoing_call), ["incoming_call", "caller"]},
          {put_in(outgoing(), [:outgoing_call], %{callee: "assistant", handled_by: "customer"}),
           ["outgoing_call", "callee"]},
          {put_in(outgoing(), [:outgoing_call, :handled_by], "missing"),
           ["outgoing_call", "handled_by"]},
          {put_in(outgoing(), [:outgoing_call, :handled_by], "customer"),
           ["outgoing_call", "handled_by"]},
          {put_in(
             outgoing(),
             [:participants, "customer", :connection],
             incoming().participants["customer"].connection
           ), ["outgoing_call", "callee"]},
          {put_in(outgoing(), [:participants, "customer", :connection, :admission], "transfer"),
           ["participants", "customer", "connection", "admission"]},
          {put_in(outgoing(), [:participants, "customer", :connection, :service], "web"),
           ["participants", "customer", "connection", "mode"]}
        ] do
      invalid(input, path)
    end
  end

  test "outgoing callee implies start-call admission and handler defaults to generated" do
    for input <- [
          outgoing(),
          outgoing() |> JSON.encode!() |> JSON.decode!(),
          put_in(outgoing(), [:participants, "customer", :connection, :admission], "start_call")
        ] do
      assert {:ok, spec} = parse(input)
      assert spec.direction == :outgoing
      assert spec.ring_timeout_ms == 30_000
      assert Map.fetch!(spec.participants, "customer").connection.admission == :start_call
      assert Map.fetch!(spec.participants, "assistant").first_message == :generated
    end

    for opening <- [%{mode: "wait_for_input"}, %{mode: "fixed", text: "Hello"}] do
      assert {:ok, spec} =
               parse(put_in(outgoing(), [:participants, "assistant", :first_message], opening))

      assert Atom.to_string(Map.fetch!(spec.participants, "assistant").first_message) ==
               opening.mode
    end
  end

  test "ring deadline is an integer between five and sixty seconds and outgoing only" do
    for timeout <- [5_000, 60_000] do
      assert {:ok, spec} = parse(put_in(outgoing(), [:outgoing_call, :ring_timeout_ms], timeout))
      assert spec.ring_timeout_ms == timeout
    end

    for timeout <- [4_999, 60_001, 5_000.0, "5000", nil] do
      invalid(put_in(outgoing(), [:outgoing_call, :ring_timeout_ms], timeout), [
        "outgoing_call",
        "ring_timeout_ms"
      ])
    end

    invalid(put_in(incoming(), [:incoming_call, :ring_timeout_ms], 5_000), [
      "incoming_call",
      "ring_timeout_ms"
    ])
  end

  test "start-call dialing is exclusive to the outgoing callee; transfers retain their default" do
    transfer = %{
      type: "human",
      connection: %{service: "phone", mode: "dial", number: "+15550001001"}
    }

    input = put_in(outgoing(), [:participants, "transfer"], transfer)
    assert {:ok, spec} = parse(input)
    assert Map.fetch!(spec.participants, "transfer").connection.admission == :transfer

    invalid(put_in(input, [:participants, "transfer", :connection, :admission], "start_call"), [
      "participants",
      "transfer",
      "connection",
      "admission"
    ])
  end

  test "legacy specs retain their entry fields and defaults and reject direction blocks" do
    input =
      incoming()
      |> Map.delete(:incoming_call)
      |> Map.merge(%{
        schema_version: "20260915.01",
        entry_caller: "customer",
        entry_receiver: "assistant"
      })

    assert {:ok, spec} = parse(input)
    assert spec.schema_version == "20260915.01"
    assert spec.direction == :incoming
    assert spec.entry_caller == "customer"
    assert Map.fetch!(spec.participants, "assistant").first_message == :wait_for_input
    invalid(Map.put(input, :outgoing_call, outgoing().outgoing_call), ["outgoing_call"])
  end

  defp parse(input), do: CallSpec.new(input, resource_id: "direction", revision: 1)

  defp invalid(input, path) do
    assert {:error, %Error{code: :invalid_call_spec, details: details}} = parse(input)
    assert details["path"] == path
  end

  defp incoming do
    %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "customer", handled_by: "assistant"},
      participants: %{
        "customer" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{type: "agent", prompt: "Introduce yourself."}
      }
    }
  end

  test "an outgoing callee takes a fixed number or the request's to, never a variable" do
    without_number =
      update_in(outgoing(), [:participants, "customer", :connection], &Map.delete(&1, :number))

    assert {:ok, spec} = parse(without_number)
    assert Map.fetch!(spec.participants, "customer").connection.number == nil

    from_variable =
      put_in(without_number, [:participants, "customer", :connection, :number_from_variable], %{
        section: "customer",
        variable: "phone"
      })

    invalid(from_variable, ["participants", "customer", "connection", "number_from_variable"])
  end

  defp outgoing do
    incoming()
    |> Map.delete(:incoming_call)
    |> Map.put(:outgoing_call, %{callee: "customer", handled_by: "assistant"})
    |> put_in([:participants, "customer", :connection], %{
      service: "phone",
      mode: "dial",
      number: "+15550001000"
    })
  end
end
