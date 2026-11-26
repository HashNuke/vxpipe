defmodule Vxpipe.Console.RecordingAdmissionTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Artifacts.TestObjectStore

  alias Vxpipe.CallEngine.{
    CallInvocation,
    CallSpec,
    CallSpecCompiler,
    RoomRecording,
    TestCallStartup
  }

  alias Vxpipe.Console.RecordingConfiguration

  test "production storage starts real writers only for calls whose admitted revision opts in" do
    settings = production_settings()
    assert {:ok, settings} = RecordingConfiguration.build(settings)

    recording =
      Keyword.update!(settings, :writer, fn {module, options} ->
        {module,
         options
         |> Keyword.delete(:metadata)
         |> Keyword.merge(
           object_store: TestObjectStore,
           object_store_options: [observer: self()]
         )}
      end)

    for {policy, enabled?} <- [
          {%{}, false},
          {%{media_policy: %{record_audio: false}}, false},
          {%{media_policy: %{record_audio: true}}, true}
        ] do
      plan = plan(policy)
      assert {:ok, room} = TestCallStartup.start_call(plan, recording: recording)
      assert room.recording_configured
      assert room.record_audio_requested == enabled?
      recorder = GenServer.whereis(RoomRecording.ref(room.incarnation_id))

      if enabled? do
        assert is_pid(recorder)
        assert_receive {:test_object_store_opened, _, %{kind: :room_track, call_id: id}}, 2_000
        assert id == plan.call_id
      else
        assert recorder == nil
        refute_received {:test_object_store_opened, _, _}
      end
    end
  end

  defp production_settings do
    variables = %{
      "STORAGE_BUCKET" => "call-recordings",
      "VXPIPE_DB_URL" => "postgres://localhost/recording_admission",
      "SECRET_KEY_BASE" => String.duplicate("recording-admission-test-", 4),
      "APP_HOST" => "console.example.test"
    }

    previous = Map.new(variables, fn {key, _} -> {key, System.get_env(key)} end)
    System.put_env(variables)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    Path.expand("../../../../../config/runtime.exs", __DIR__)
    |> Config.Reader.read!(env: :prod)
    |> Keyword.fetch!(:vxpipe_console)
    |> Keyword.fetch!(:recording)
  end

  defp plan(policy) do
    human = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"}
    }

    input =
      Map.merge(
        %{
          schema_version: "20260915.01",
          entry_caller: "caller",
          entry_receiver: "receiver",
          wait_sounds: nil,
          participants: %{"caller" => human, "receiver" => human}
        },
        policy
      )

    assert {:ok, spec} = CallSpec.new(input, resource_id: "support", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "support", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant",
               actor_id: "actor"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end
end
