defmodule Vxpipe.CallEngine.Speech.CallLoadTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.CallLoad.Runner

  @moduletag :integration
  @moduletag timeout: 120_000

  for mode <- [:llm_tts, :sts_provider, :sts_output_stt] do
    @tag mode: mode
    test "bounded pinned room calls: #{mode}" do
      profile = System.get_env("VXPIPE_CALL_LOAD_PROFILE", "smoke")
      calls = if profile == "measured", do: 10, else: 2
      scope = make_ref()

      name = fn role ->
        {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, scope, role}}}
      end

      supervisor =
        start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: name.(:connections)})

      tasks = start_supervised!({Task.Supervisor, name: name.(:tasks)})
      observer = start_supervised!(Vxpipe.CallEngine.CallLoad.IngressObserver)

      fixture =
        start_supervised!({Vxpipe.CallEngine.Diagnostics.ModelFixture, response: "RECEIVED HI"})

      original = Runner.configure(fixture, observer)
      on_exit(fn -> Runner.restore(original) end)
      report = Runner.run(unquote(mode), calls, supervisor, tasks, observer)
      IO.puts("CALL_LOAD_JSON " <> JSON.encode!(Map.put(report, :profile, profile)))
      assert report.errors == []
      assert report.ready_calls == calls
      assert report.cleaned_calls == calls
      assert report.completed_turns >= calls * 2
      assert report.interruptions == calls
      assert report.surviving_calls == calls - 1

      assert Enum.all?(report.calls, fn call ->
               call.sink.rejected_chunks == 0 and call.sink.cleared_chunks == 0 and
                 call.sink.incorrect_replies == 0 and
                 call.sink.decoded_replies >= call.completed and call.input_drops.rejected == 0 and
                 call.input_drops.ingress_dropped == 0 and call.caller_transcripts >= 3 and
                 call.agent_transcripts >= call.completed
             end)

      assert Enum.all?(report.milliseconds, fn {_name, stats} -> stats.count > 0 end)

      if unquote(mode) == :llm_tts do
        assert Enum.all?(report.calls, &(&1.input_drops.delivered == &1.input_frames))
      end
    end
  end
end
