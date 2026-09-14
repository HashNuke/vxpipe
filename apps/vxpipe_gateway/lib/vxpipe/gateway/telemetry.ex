defmodule Vxpipe.Gateway.Telemetry do
  @moduledoc """
  Emits bounded operational events owned by the gateway.

  Durations use the Erlang `:native` time unit from a monotonic clock. Request
  metadata deliberately excludes paths, query strings, headers, bodies, and
  correlation identifiers.
  """

  @request_stop_event [:vxpipe, :gateway, :http, :request, :stop]
  @output_drop_event [:vxpipe, :gateway, :audio_output, :drop]

  @doc "Counts rejected or discarded output frame submissions without their content."
  def output_drop(source, reason) when source in [:room, :direct] do
    category =
      case reason do
        :busy ->
          :busy

        :held ->
          :held

        :interrupted ->
          :cleared

        value when value in [:clearing, :draining] ->
          :clearing

        value when value in [:stale_room_binding, :stale_output_generation] ->
          :stale

        value
        when value in [:wrong_recipient, :wrong_connection, :invalid_frame, :unsupported_audio] ->
          :invalid

        _other ->
          :unavailable
      end

    :telemetry.execute(@output_drop_event, %{count: 1}, %{source: source, reason: category})
  end

  @doc "Returns the event emitted when a gateway HTTP request stops."
  @spec request_stop_event() :: nonempty_list(atom())
  def request_stop_event, do: @request_stop_event

  @doc false
  @spec observe_request(Plug.Conn.t(), (-> Plug.Conn.t())) :: Plug.Conn.t()
  def observe_request(conn, callback) when is_function(callback, 0) do
    started_at = System.monotonic_time()
    operation = operation(conn)

    try do
      result = callback.()
      emit_request_stop(started_at, operation, outcome(result.status), result.status)
      result
    catch
      kind, reason ->
        emit_request_stop(started_at, operation, :exception, nil)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp emit_request_stop(started_at, operation, outcome, status) do
    :telemetry.execute(
      @request_stop_event,
      %{duration: System.monotonic_time() - started_at},
      %{operation: operation, outcome: outcome, status: status}
    )
  end

  defp operation(%Plug.Conn{method: "OPTIONS"}), do: :cors_preflight
  defp operation(%Plug.Conn{method: "GET", path_info: ["healthz"]}), do: :health_check
  defp operation(%Plug.Conn{method: "POST", path_info: ["api", "rooms"]}), do: :room_create

  defp operation(%Plug.Conn{
         method: "POST",
         path_info: ["api", "telephony", "telnyx", _ingress_key, "events"]
       }),
       do: :telephony_webhook

  defp operation(%Plug.Conn{
         method: "GET",
         path_info: ["api", "telephony", "telnyx", _ingress_key, "media", _token]
       }),
       do: :telephony_media_upgrade

  defp operation(%Plug.Conn{
         method: "POST",
         path_info: ["api", "tenants", _tenant, "participants", _participant, "calls"]
       }),
       do: :call_prepare

  defp operation(%Plug.Conn{
         method: "POST",
         path_info: [
           "api",
           "tenants",
           _tenant,
           "calls",
           _call,
           "participants",
           _participant,
           "sessions"
         ]
       }),
       do: :call_session_create

  defp operation(%Plug.Conn{
         method: "POST",
         path_info: [
           "api",
           "tenants",
           _tenant,
           "calls",
           _call,
           "participants",
           _participant,
           "join-tokens"
         ]
       }),
       do: :call_join_token_issue

  defp operation(%Plug.Conn{
         method: "POST",
         path_info: ["api", "rooms", _room_id, "sessions"]
       }),
       do: :session_create

  defp operation(%Plug.Conn{method: "POST", path_info: ["api", "rtvi", "offer"]}),
    do: :rtvi_offer

  defp operation(%Plug.Conn{method: "PATCH", path_info: ["api", "rtvi", "offer"]}),
    do: :rtvi_candidates

  defp operation(_conn), do: :unknown

  defp outcome(status) when status >= 200 and status < 400, do: :ok
  defp outcome(status) when status >= 400 and status < 500, do: :client_error
  defp outcome(status) when status >= 500 and status < 600, do: :server_error
  defp outcome(_status), do: :unknown
end
