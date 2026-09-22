defmodule Vxpipe.CallEngine.Integration.DeepgramFluxCloseStreamProbeTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.TestFluxCloseProbe, as: Probe

  @moduletag :integration
  @moduletag :hosted
  @moduletag timeout: 60_000
  @moduletag skip: System.get_env("VXPIPE_RUN_FLUX_CLOSE_PROBE") != "1"

  test "authorized known speech observes tail then CloseStream peer terminal" do
    # No credential resolution occurs unless Probe.run's independent gate opens.
    result =
      Probe.run(
        [
          enabled: System.get_env("VXPIPE_RUN_FLUX_CLOSE_PROBE") == "1",
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
