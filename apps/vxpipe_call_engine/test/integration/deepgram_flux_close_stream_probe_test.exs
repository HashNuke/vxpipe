defmodule Vxpipe.CallEngine.Integration.DeepgramFluxCloseStreamProbeTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.TestFluxCloseProbe, as: Probe

  @moduletag :live_providers
  @moduletag :live_deepgram
  @moduletag timeout: 60_000

  test "authorized known speech observes tail then CloseStream peer terminal" do
    # Mix selects this test before the probe resolves its fixture or credentials.
    result =
      Probe.run(
        [
          enabled: true,
          fixture_path: System.get_env("VXPIPE_FLUX_PROBE_PCM"),
          expected_tail: System.get_env("VXPIPE_FLUX_PROBE_EXPECTED_TAIL")
        ],
        %{
          credential: fn -> System.get_env("DEEPGRAM_API_KEY") end,
          connect: fn options, callback ->
            Probe.start_socket(options, callback, &start_supervised/1)
          end,
          stop: fn _socket -> stop_supervised(Probe) end
        }
      )

    # This is the entire retained observation. Never print raw upstream data.
    IO.puts("Flux CloseStream probe: " <> inspect(result))

    assert result.passed?,
           "Flux CloseStream observation failed/inconclusive; see sanitized report"
  end
end
