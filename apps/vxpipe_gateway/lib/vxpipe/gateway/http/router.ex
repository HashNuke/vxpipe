defmodule Vxpipe.Gateway.HTTP.Router do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias Vxpipe.Gateway.HTTP.{
    CallAdmissions,
    RTVI,
    Rooms,
    TelephonyIngressConfig,
    TelnyxEvents,
    TelnyxMedia,
    TwilioEvents,
    TwilioMedia
  }

  alias Vxpipe.Gateway.CallAdmission

  @impl true
  def init(options) do
    telephony = options |> Keyword.get(:telephony, []) |> telephony_options!()
    telephony_events = telephony |> event_options() |> TelephonyIngressConfig.init()

    call_admission =
      options
      |> Keyword.get(:call_admission, [])
      |> configure_call_admission(telephony_events)

    media_options =
      telephony
      |> Keyword.take([
        :media_admission,
        :maximum_media_message_bytes,
        :media_socket,
        :media_socket_timeout_ms,
        :twilio_media_socket
      ])
      |> Keyword.merge(registry: telephony_events.registry, clock: telephony_events.clock)

    %{
      call_spec_authoring:
        options
        |> Keyword.get(:call_spec_authoring, [])
        |> Vxpipe.Gateway.HTTP.CallSpecWrites.init(),
      operator_api:
        options |> Keyword.get(:operator_api, []) |> Vxpipe.Gateway.HTTP.OperatorAPI.init(),
      call_admission: CallAdmissions.init(call_admission),
      rooms: options |> Keyword.get(:room_creation, []) |> Rooms.init(),
      telephony: telephony_events,
      telnyx_media: TelnyxMedia.init(media_options),
      twilio_media: TwilioMedia.init(media_options),
      rtvi: options |> Keyword.get(:webrtc, []) |> RTVI.init()
    }
  end

  @impl true
  def call(%Plug.Conn{method: "GET", path_info: ["healthz"]} = conn, _options) do
    send_resp(conn, 200, "ok")
  end

  def call(
        %Plug.Conn{path_info: ["api", "platform", "tenants", tenant, "call-specs" | segments]} =
          conn,
        options
      ) do
    Vxpipe.Gateway.HTTP.CallSpecWrites.route(
      conn,
      options.call_spec_authoring,
      :operator,
      tenant,
      segments
    )
  end

  def call(
        %Plug.Conn{path_info: ["api", "tenants", tenant, "call-specs" | segments]} = conn,
        options
      ) do
    Vxpipe.Gateway.HTTP.CallSpecWrites.route(
      conn,
      options.call_spec_authoring,
      :tenant,
      tenant,
      segments
    )
  end

  def call(%Plug.Conn{method: "GET", path_info: ["api", "platform", "status"]} = conn, options) do
    Vxpipe.Gateway.HTTP.OperatorAPI.status(conn, options.operator_api)
  end

  def call(%Plug.Conn{method: "POST", path_info: ["api", "rooms"]} = conn, options) do
    Rooms.create(conn, options.rooms)
  end

  def call(
        %Plug.Conn{
          method: "POST",
          path_info: ["api", "telephony", "telnyx", ingress_key, "events"]
        } = conn,
        options
      ) do
    TelnyxEvents.handle(conn, options.telephony, ingress_key)
  end

  def call(
        %Plug.Conn{
          method: "POST",
          path_info: ["api", "telephony", "twilio", ingress_key, "voice"]
        } = conn,
        options
      ) do
    TwilioEvents.handle_voice(conn, options.telephony, ingress_key)
  end

  def call(
        %Plug.Conn{
          method: "POST",
          path_info: ["api", "telephony", "twilio", ingress_key, "events", leg_id]
        } = conn,
        options
      ) do
    TwilioEvents.handle_callback(conn, options.telephony, ingress_key, leg_id)
  end

  def call(
        %Plug.Conn{
          method: "GET",
          path_info: ["api", "telephony", "telnyx", ingress_key, "media", token]
        } = conn,
        options
      ) do
    TelnyxMedia.upgrade(conn, options.telnyx_media, ingress_key, token)
  end

  def call(
        %Plug.Conn{
          method: "GET",
          path_info: ["api", "telephony", "twilio", ingress_key, "media", token]
        } = conn,
        options
      ) do
    TwilioMedia.upgrade(conn, options.twilio_media, ingress_key, token)
  end

  def call(
        %Plug.Conn{
          method: "POST",
          path_info: ["api", "tenants", tenant_key, "participants", participant_key, "calls"]
        } = conn,
        options
      ) do
    CallAdmissions.prepare(
      conn,
      options.call_admission,
      tenant_key,
      participant_key
    )
  end

  def call(
        %Plug.Conn{
          method: "POST",
          path_info: [
            "api",
            "tenants",
            tenant_key,
            "calls",
            call_id,
            "participants",
            participant_key,
            "sessions"
          ]
        } = conn,
        options
      ) do
    CallAdmissions.create_session(
      conn,
      options.call_admission,
      tenant_key,
      call_id,
      participant_key
    )
  end

  def call(
        %Plug.Conn{
          method: "POST",
          path_info: [
            "api",
            "tenants",
            tenant_key,
            "calls",
            call_id,
            "participants",
            participant_key,
            "join-tokens"
          ]
        } = conn,
        options
      ) do
    CallAdmissions.issue_token(
      conn,
      options.call_admission,
      tenant_key,
      call_id,
      participant_key
    )
  end

  def call(
        %Plug.Conn{method: "POST", path_info: ["api", "rooms", room_id, "sessions"]} = conn,
        options
      ) do
    Rooms.create_session(conn, options.rooms, room_id)
  end

  def call(%Plug.Conn{method: "POST", path_info: ["api", "rtvi", "offer"]} = conn, options) do
    RTVI.offer(conn, options.rtvi)
  end

  def call(%Plug.Conn{method: "PATCH", path_info: ["api", "rtvi", "offer"]} = conn, options) do
    RTVI.add_ice_candidates(conn, options.rtvi)
  end

  def call(conn, _options), do: send_resp(conn, 404, "not found")

  defp telephony_options!(options) do
    validate_options!(options, [
      :enabled,
      :public_base_url,
      :telephony_service_repository,
      :adapters,
      :handler,
      :clock,
      :maximum_body_bytes,
      :media_admission,
      :maximum_media_message_bytes,
      :media_socket,
      :media_socket_timeout_ms,
      :twilio_media_socket
    ])
  end

  defp event_options(telephony) do
    Keyword.take(telephony, [
      :enabled,
      :public_base_url,
      :telephony_service_repository,
      :adapters,
      :handler,
      :media_admission,
      :clock,
      :maximum_body_bytes
    ])
  end

  defp configure_call_admission(options, telephony) do
    {backend, options} = Keyword.pop(options, :backend, {CallAdmission, []})

    backend =
      case backend do
        {CallAdmission, backend_options} ->
          {CallAdmission,
           CallAdmission.configure_telephony(
             backend_options,
             telephony.registry,
             telephony.media_admission
           )}

        custom_backend ->
          custom_backend
      end

    Keyword.put(options, :backend, backend)
  end

  defp validate_options!(options, allowed) do
    case Keyword.validate(options, allowed) do
      {:ok, options} -> options
      {:error, _keys} -> raise ArgumentError, "invalid telephony configuration"
    end
  end
end
