defmodule Vxpipe.Console.Integration.LiveDiagnosticsBrowserTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.Test.LiveDiagnosticsBrowserScenario

  @moduletag :live_providers
  @moduletag :live_elevenlabs
  @moduletag :live_diagnostics_browser
  @moduletag :capture_log
  @moduletag timeout: 300_000

  for operational_vad <- [false, true] do
    @operational_vad operational_vad
    @tag diagnostics_vad: operational_vad
    test "real Scribe/browser diagnostics with operational VAD #{operational_vad}" do
      # The existing runner supplies only this child process's credential. Never
      # open the runner's environment file or include credentials in evidence.
      key = System.fetch_env!("ELEVENLABS_API_KEY")
      evidence = LiveDiagnosticsBrowserScenario.run!(@operational_vad, key)
      assert evidence.scribe_provider == "elevenlabs"

      assert evidence.inference_source ==
               if(@operational_vad, do: "operational_reuse", else: "benchmark_only")

      assert evidence.canonical_turns == 5
      assert evidence.endpoint_measurements >= 1
      assert evidence.pause_resume
      assert evidence.barge_in_count >= 1
      assert evidence.tool_only
      assert evidence.hung_up
      assert evidence.persisted_after_hangup
      assert evidence.secret_free
    end
  end
end
