defmodule Vxpipe.Gateway.Telemetry.WebhookFailureTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.Gateway.Telemetry

  test "structured errors expose only their bounded code and arbitrary terms expose no details" do
    event = [:vxpipe, :telephony, :webhook, :failed]
    handler = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(handler, event, &__MODULE__.observe/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    error =
      Error.new(:provider_credential_unavailable, "private-sentinel",
        details: %{"secret" => "private-sentinel"}
      )

    log =
      capture_log(fn ->
        Telemetry.webhook_failure(:telnyx, 503, error)
        Telemetry.webhook_failure(:twilio, 503, {:adapter_failure, "private-sentinel"})
      end)

    assert_received {:failure, %{count: 1, http_status: 503},
                     %{provider: :telnyx, reason: :provider_credential_unavailable}}

    assert_received {:failure, %{count: 1, http_status: 503},
                     %{provider: :twilio, reason: :unclassified_error}}

    refute log =~ "private-sentinel"
    assert log =~ "reason=unclassified_error"
  end

  def observe(_event, measurements, metadata, observer) do
    if self() == observer, do: send(observer, {:failure, measurements, metadata})
  end
end
