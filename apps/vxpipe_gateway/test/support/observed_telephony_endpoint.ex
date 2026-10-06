defmodule Vxpipe.Gateway.TestObservedTelephonyEndpoint do
  @moduledoc false
  @behaviour Plug

  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.Telephony.MediaAdmission
  alias Vxpipe.CallEngine.Telephony.Webhook
  alias Vxpipe.Providers.Twilio.{PublicEndpoint, WebhookVerifier}

  @impl true
  def init(options) do
    endpoint =
      Keyword.get_lazy(options, :endpoint, fn ->
        Endpoint.init(Keyword.fetch!(options, :endpoint_options))
      end)

    %{endpoint: endpoint, observer: Keyword.fetch!(options, :observer)}
  end

  @impl true
  def call(
        %Plug.Conn{
          method: "GET",
          path_info: ["api", "telephony", "twilio", ingress, "media", token]
        } = conn,
        options
      ) do
    diagnostic = signature_diagnostic(conn, options, ingress, token)
    send(options.observer, {:test_media_signature, diagnostic})
    Endpoint.call(conn, options.endpoint)
  end

  def call(conn, options), do: Endpoint.call(conn, options.endpoint)

  defp signature_diagnostic(conn, options, ingress, token) do
    admission = options.endpoint.router.twilio_media.media_admission

    case MediaAdmission.lookup_service(admission, ingress, token) do
      {:ok, service} ->
        url = PublicEndpoint.media_url(service, token)
        https = url |> URI.parse() |> Map.put(:scheme, "https") |> URI.to_string()
        signature = Plug.Conn.get_req_header(conn, "x-twilio-signature") |> List.first("")

        Map.new(
          [
            exact_wss: url,
            trailing_wss: url <> "/",
            exact_https: https,
            trailing_https: https <> "/"
          ],
          fn {name, candidate} ->
            webhook = %Webhook{
              body: "",
              headers: %{"x-twilio-signature" => signature},
              url: candidate,
              received_at: System.system_time(:second)
            }

            {name, WebhookVerifier.verify(webhook, service.verifier_options) == :ok}
          end
        )

      _unavailable ->
        :service_unavailable
    end
  rescue
    _error -> :probe_unavailable
  catch
    :exit, _reason -> :probe_unavailable
  end
end
