defmodule Vxpipe.Gateway.Telephony.SourceGateConformanceTest do
  use ExUnit.Case, async: true

  # Replays the Lean-generated slice-1 oracle against the Elixir SourceGate.
  # The oracle is the checked-in `verification/oracle/source_gate.txt`, produced
  # by `verification/Oracle.lean`. `bin/verify-lean` rebuilds the model, fails
  # on oracle drift, then runs this test. See docs/formal-verification.md.

  alias Vxpipe.Gateway.Telephony.SourceGate

  @oracle Path.expand("../../../../../../verification/oracle/source_gate.txt", __DIR__)

  setup_all do
    assert File.exists?(@oracle), "missing Lean oracle at #{@oracle}"
    :ok
  end

  test "every modelled SourceGate transition matches the Elixir implementation" do
    epochs = %{0 => make_ref(), 1 => make_ref(), 2 => make_ref()}

    decode_epoch = fn
      "nil" -> nil
      encoded -> Map.fetch!(epochs, String.to_integer(encoded))
    end

    decode_gate = fn
      "open" -> SourceGate.new()
      "held:nil" -> {:held, nil}
      "held:" <> n -> {:held, Map.fetch!(epochs, String.to_integer(n))}
      "active:" <> n -> {:active, Map.fetch!(epochs, String.to_integer(n))}
    end

    epoch_index = fn ref ->
      Enum.find_value(epochs, fn {index, value} -> value == ref && index end)
    end

    encode_gate = fn
      nil -> "open"
      {:held, nil} -> "held:nil"
      {:held, ref} -> "held:#{epoch_index.(ref)}"
      {:active, ref} -> "active:#{epoch_index.(ref)}"
    end

    replayed =
      @oracle
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.reduce(0, fn line, acc ->
        [from, op, arg, result] = String.split(line, "|")
        gate = decode_gate.(from)

        case op do
          "admitted" ->
            assert SourceGate.admitted?(gate, decode_epoch.(arg)) == (result == "true"),
                   "admitted #{from} #{arg}"

          "hold" ->
            assert encode_gate.(SourceGate.hold(gate)) == result, "hold #{from}"

          "arm" ->
            epoch = Map.fetch!(epochs, String.to_integer(arg))
            assert encode_gate.(SourceGate.arm(gate, epoch)) == result, "arm #{from} #{arg}"
        end

        acc + 1
      end)

    assert replayed == 64
  end
end
