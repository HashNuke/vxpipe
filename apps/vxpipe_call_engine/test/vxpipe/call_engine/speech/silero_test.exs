defmodule Vxpipe.CallEngine.Speech.SileroTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Speech.{ActivityBoundary, ActivityRuntime, ActivitySupervisor, Silero}
  alias Vxpipe.Providers.Deepgram.LiveFixture

  test "packaged CPU inference preserves speech results across PCM chunk boundaries and reset" do
    assert {:ok, model} = Silero.load()
    audio = File.read!(LiveFixture.pcm_path())
    assert {:ok, whole, probabilities} = classify(model, Silero.new(), audio, 32_000)
    assert length(probabilities) == div(byte_size(audio), 1_024)
    assert Enum.count(probabilities, &(&1 >= 0.5)) == 52

    reference =
      Path.expand("../../../fixtures/speech/silero_v6.2.3.f32", __DIR__)
      |> File.read!()

    expected = for <<probability::float-little-32 <- reference>>, do: probability
    assert length(expected) == length(probabilities)

    assert Enum.all?(Enum.zip(probabilities, expected), fn {actual, expected} ->
             abs(actual - expected) <= 1.0e-6
           end)

    assert {:ok, split, split_probabilities} = classify(model, Silero.new(), audio, 638)
    assert split_probabilities == probabilities
    assert Silero.pending_bytes(split) == Silero.pending_bytes(whole)

    assert {:ok, _state, reset_probabilities} = classify(model, Silero.reset(split), audio, 638)
    assert reset_probabilities == probabilities
    refute inspect(split) =~ "Nx.Tensor"
    refute inspect(model) =~ "Ortex.Model"
  end

  test "incomplete PCM is retained without fabricating classified silence" do
    assert {:ok, model} = Silero.load()
    assert {:ok, state, []} = Silero.push(Silero.new(), model, <<1, 0>>)
    assert state.samples == 0
    assert Silero.pending_bytes(state) == 2
    assert {:error, :invalid_audio} = Silero.push(state, model, <<1>>)
    assert {:error, :invalid_audio} = Silero.push(state, model, :binary.copy(<<0>>, 32_002))
    assert Silero.pending_bytes(Silero.reset(state)) == 0

    assert {:ok, other, probabilities} =
             Silero.push(Silero.new(), model, :binary.copy(<<0>>, 1_024))

    assert other.samples == 512
    assert Enum.all?(probabilities, &(&1 < 0.35))
  end

  test "bounded tone and seeded noise controls do not establish speech activity" do
    assert {:ok, model} = Silero.load()

    tone =
      for index <- 0..15_999, into: "" do
        sample = round(3_276 * :math.sin(2 * :math.pi() * 440 * index / 16_000))
        <<sample::signed-little-16>>
      end

    {noise, _random} =
      Enum.reduce(1..16_000, {[], :rand.seed_s(:exsss, {11, 23, 37})}, fn _, {samples, random} ->
        {value, random} = :rand.uniform_s(6_553, random)
        {[<<value - 3_277::signed-little-16>> | samples], random}
      end)

    for audio <- [tone, IO.iodata_to_binary(noise)] do
      assert {:ok, _state, probabilities} = classify(model, Silero.new(), audio, 638)
      assert Enum.all?(probabilities, &(&1 < 0.5))
    end
  end

  test "supervised inference supplies actual acoustic evidence from accepted PCM" do
    start_supervised!(
      {ActivitySupervisor,
       name: __MODULE__.Supervisor, tasks: __MODULE__.Tasks, runtime: __MODULE__.Runtime}
    )

    audio = File.read!(LiveFixture.pcm_path())
    {stream, boundary, events} = classified_activity(Silero.new(), ActivityBoundary.new(), audio)
    assert stream.samples == div(byte_size(audio), 2)
    assert boundary.samples == stream.samples
    assert [{:speech_started, onset}, {:speech_ended, endpoint}] = events
    assert onset >= 0 and endpoint > onset and endpoint < stream.samples
  end

  defp classified_activity(stream, boundary, ""), do: {stream, boundary, []}

  defp classified_activity(stream, boundary, audio) do
    size = min(byte_size(audio), 3_200)
    <<chunk::binary-size(size), rest::binary>> = audio
    assert {:ok, reference} = ActivityRuntime.submit(stream, chunk, __MODULE__.Runtime)
    assert_receive {:vxpipe_speech_activity, ^reference, {:ok, stream, probabilities}}, 15_000

    {boundary, events} =
      Enum.reduce(probabilities, {boundary, []}, fn probability, {state, events} ->
        assert {:ok, state, next} = ActivityBoundary.push(state, probability)
        {state, events ++ next}
      end)

    {stream, boundary, later} = classified_activity(stream, boundary, rest)
    {stream, boundary, events ++ later}
  end

  defp classify(_model, state, "", _size), do: {:ok, state, []}

  defp classify(model, state, audio, size) do
    length = min(byte_size(audio), size)
    <<chunk::binary-size(length), rest::binary>> = audio
    assert {:ok, state, probabilities} = Silero.push(state, model, chunk)
    {:ok, state, later} = classify(model, state, rest, size)
    {:ok, state, probabilities ++ later}
  end
end
