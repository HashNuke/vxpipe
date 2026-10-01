defmodule Vxpipe.Providers.ElevenLabs.ScribeInputTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Providers.ElevenLabs.ScribeInput

  test "confirmed acoustic onset retains its PCM and silence ends the same opaque turn" do
    voice = :binary.copy(<<1, 0>>, 2_048)
    silence = :binary.copy(<<0, 0>>, 8_192)

    assert {:ok, input, [{:speech_started, ref}, {:audio, ref, ^voice}]} =
             ScribeInput.push(ScribeInput.new(), voice, [0.8, 0.8, 0.8, 0.8])

    assert is_reference(ref)
    assert {:ok, _input, actions} = ScribeInput.push(input, silence, List.duplicate(0.1, 16))
    assert List.last(actions) == {:endpoint, ref, 128}

    assert actions
           |> Enum.filter(&match?({:audio, _, _}, &1))
           |> Enum.map(&elem(&1, 2))
           |> IO.iodata_to_binary() == silence
  end

  test "chunk fragments cannot invent silence, and fresh acoustic activity gets a fresh reference" do
    input = ScribeInput.new()
    assert {:ok, input, []} = ScribeInput.push(input, <<1, 0>>, [])
    assert {:error, :invalid_classification} = ScribeInput.push(input, <<1, 0>>, [0.8])
    voice = :binary.copy(<<1, 0>>, 2_048)
    <<_sample::binary-size(2), rest::binary>> = voice

    assert {:ok, input, [{:speech_started, first}, {:audio, first, ^voice}]} =
             ScribeInput.push(input, rest, List.duplicate(0.8, 4))

    assert {:ok, input, _actions} =
             ScribeInput.push(input, :binary.copy(<<0, 0>>, 8_192), List.duplicate(0.1, 16))

    assert {:ok, _input, [{:speech_started, second}, {:audio, second, ^voice}]} =
             ScribeInput.push(input, voice, List.duplicate(0.8, 4))

    refute first == second
  end
end
