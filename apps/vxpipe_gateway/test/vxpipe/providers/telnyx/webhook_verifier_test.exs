defmodule Vxpipe.Providers.Telnyx.WebhookVerifierTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telephony.Webhook
  alias Vxpipe.Providers.Telnyx.WebhookVerifier

  @received_at 1_789_056_000
  @body ~s({"data":{"event_type":"call.initiated"}})

  setup do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    %{options: [public_key: Base.encode64(public_key)], private_key: private_key}
  end

  test "authenticates the exact raw body at the configured freshness boundary", context do
    webhook = signed_webhook(@body, @received_at - 300, context.private_key)

    assert :ok = WebhookVerifier.verify(webhook, context.options)
  end

  test "rejects body tampering and malformed authentication inputs", context do
    valid = signed_webhook(@body, @received_at, context.private_key)

    invalid_webhooks = [
      %{valid | body: @body <> " "},
      put_in(valid.headers["telnyx-signature-ed25519"], "not-base64"),
      put_in(valid.headers["telnyx-timestamp"], "not-a-timestamp"),
      %{valid | headers: Map.delete(valid.headers, "telnyx-signature-ed25519")},
      %{valid | headers: Map.delete(valid.headers, "telnyx-timestamp")}
    ]

    Enum.each(invalid_webhooks, fn webhook ->
      assert {:error, :invalid_webhook_authentication} =
               WebhookVerifier.verify(webhook, context.options)
    end)
  end

  test "rejects timestamps outside the replay window in either direction", context do
    Enum.each([@received_at - 301, @received_at + 301], fn timestamp ->
      webhook = signed_webhook(@body, timestamp, context.private_key)

      assert {:error, :invalid_webhook_authentication} =
               WebhookVerifier.verify(webhook, context.options)
    end)
  end

  test "rejects missing or malformed verifier configuration", context do
    webhook = signed_webhook(@body, @received_at, context.private_key)

    invalid_options = [
      [],
      [public_key: "not-base64"],
      [public_key: Base.encode64(<<0::256>>), tolerance_seconds: -1]
    ]

    Enum.each(invalid_options, fn options ->
      assert {:error, :invalid_webhook_verifier_configuration} =
               WebhookVerifier.verify(webhook, options)
    end)
  end

  defp signed_webhook(body, timestamp, private_key) do
    timestamp = Integer.to_string(timestamp)
    signature = :crypto.sign(:eddsa, :none, timestamp <> "|" <> body, [private_key, :ed25519])

    %Webhook{
      body: body,
      headers: %{
        "telnyx-signature-ed25519" => Base.encode64(signature),
        "telnyx-timestamp" => timestamp
      },
      received_at: @received_at
    }
  end
end
