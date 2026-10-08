defmodule Vxpipe.Gateway.Telemetry.RoomOutputFailureTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  alias Vxpipe.Gateway.Telemetry

  test "output failure diagnostics exclude private error details" do
    handler = {__MODULE__, make_ref()}

    assert :ok =
             :telemetry.attach(
               handler,
               [:vxpipe, :gateway, :room_audio_output, :failed],
               &__MODULE__.observe/4,
               self()
             )

    on_exit(fn -> :telemetry.detach(handler) end)

    log =
      capture_log(fn ->
        Telemetry.room_output_failure(:take, {:failure, "private-sentinel"})
        Telemetry.room_output_failure(:push, :stale_policy_revision)
      end)

    assert_received {:failure, %{count: 1}, %{stage: :take, reason: :unclassified_error}}
    assert_received {:failure, %{count: 1}, %{stage: :push, reason: :stale_policy_revision}}
    refute log =~ "private-sentinel"
  end

  def observe(_event, measurements, metadata, observer) do
    if self() == observer, do: send(observer, {:failure, measurements, metadata})
  end
end
