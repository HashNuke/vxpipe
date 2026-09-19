defmodule Vxpipe.Gateway.TelnyxFixture do
  @moduledoc false

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.Telephony.Telnyx.MediaSocket

  @fixture_root Path.expand("../fixtures/telnyx", __DIR__)

  def body(name, replacements \\ %{}) when is_binary(name) and is_map(replacements) do
    name
    |> fixture_path()
    |> File.read!()
    |> replace(replacements)
  end

  def signature(body, private_key, timestamp)
      when is_binary(body) and is_binary(timestamp) do
    :crypto.sign(:eddsa, :none, timestamp <> "|" <> body, [private_key, :ed25519])
    |> Base.encode64()
  end

  def post_event(endpoint, private_key, tenant_key, name, replacements, received_at) do
    body = body(name, replacements)
    timestamp = Integer.to_string(received_at)

    :post
    |> conn("/webhooks/tenants/#{tenant_key}/telnyx", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("telnyx-timestamp", timestamp)
    |> put_req_header("telnyx-signature-ed25519", signature(body, private_key, timestamp))
    |> Endpoint.call(endpoint)
  end

  def open_media(endpoint, media_url, replacements) do
    upgraded =
      :get
      |> conn(URI.parse(media_url).path)
      |> websocket_headers()
      |> Endpoint.call(endpoint)

    with 101 <- upgraded.status,
         [
           {:websocket,
            {MediaSocket, %{binding: binding},
             [timeout: 30_000, max_frame_size: 131_072, early_validate_upgrade: false]}}
         ] <- sent_upgrades(upgraded),
         {:ok, socket} <- MediaSocket.init(%{binding: binding}),
         {:ok, socket} <-
           MediaSocket.handle_in({body("media-start", replacements), opcode: :text}, socket),
         {:ok, socket} <- Vxpipe.Gateway.TestSocketDispatch.await(socket) do
      {:ok, binding, socket}
    else
      _invalid -> {:error, :media_harness_failed}
    end
  end

  defp fixture_path(name), do: Path.join(@fixture_root, name <> ".json")

  defp websocket_headers(conn) do
    conn = %{conn | host: "voice.example.test", req_headers: [{"host", "voice.example.test"}]}

    conn
    |> put_req_header("connection", "upgrade")
    |> put_req_header("upgrade", "websocket")
    |> put_req_header("sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16)))
    |> put_req_header("sec-websocket-version", "13")
  end

  defp replace(body, replacements) do
    rendered =
      Enum.reduce(replacements, body, fn {key, value}, rendered ->
        String.replace(rendered, "{{#{key}}}", to_string(value))
      end)

    if String.contains?(rendered, "{{") do
      raise ArgumentError, "Telnyx fixture contains unresolved placeholders"
    end

    rendered
  end
end
