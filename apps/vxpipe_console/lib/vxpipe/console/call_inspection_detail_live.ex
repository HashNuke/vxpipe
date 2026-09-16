defmodule Vxpipe.Console.CallInspectionDetailLive do
  @moduledoc false

  use Phoenix.LiveView, layout: false

  alias Vxpipe.Calls.CallDetailPage

  alias Vxpipe.Console.{
    CallDetails,
    CallInspection,
    CallInspectionComponents,
    CallRecording,
    OperatorLiveAuthentication
  }

  @list_page_size 25
  @history_page_size 50
  @details_page_size 25
  @refresh_interval_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       loaded?: false,
       selected_id: nil,
       selected_event_id: nil,
       list_cursor: nil,
       history_cursor: nil,
       details_cursor: nil,
       refresh_token: nil,
       recordings: [],
       recordings_status: :unavailable,
       usage_report: nil,
       usage_status: :unavailable,
       call_details_page: nil,
       call_details_status: :unavailable
     )}
  end

  @impl true
  def handle_params(%{"call_id" => call_id} = params, _uri, socket) do
    if OperatorLiveAuthentication.tenant_path?(socket, params) do
      requested = requested_state(call_id, params)
      reload_call? = not socket.assigns.loaded? or socket.assigns.selected_id != call_id

      socket =
        socket
        |> maybe_cancel_refresh(reload_call?)
        |> maybe_load_list(requested, reload_call?)
        |> maybe_load_detail(requested, reload_call?)
        |> maybe_load_recordings(requested, reload_call?)
        |> maybe_load_usage(requested, reload_call?)
        |> maybe_load_call_details(requested, reload_call?)
        |> assign(
          loaded?: true,
          selected_id: requested.call_id,
          selected_event_id: requested.event,
          list_cursor: requested.list_cursor,
          history_cursor: requested.history_cursor,
          details_cursor: requested.details_cursor
        )
        |> reconcile_live_refresh()

      {:noreply, socket}
    else
      {:noreply, redirect(socket, to: "/operator/sign-in")}
    end
  end

  @impl true
  def render(assigns), do: CallInspectionComponents.index(assigns)

  @impl true
  def handle_info({:refresh_live_inspection, token}, %{assigns: %{refresh_token: token}} = socket) do
    socket = assign(socket, refresh_token: nil)

    case CallInspection.inspect_live_call(socket.assigns.principal, socket.assigns.selected_id) do
      {:ok, live} ->
        {:noreply,
         socket
         |> assign(detail_status: :live, live: live)
         |> reconcile_live_refresh()}

      {:error, _reason} ->
        status = persisted_status(socket.assigns.persisted)
        {:noreply, assign(socket, detail_status: status, live: nil)}
    end
  end

  def handle_info({:refresh_live_inspection, _stale_token}, socket), do: {:noreply, socket}

  defp requested_state(call_id, params) do
    %{
      call_id: call_id,
      event: query_value(params, "event"),
      list_cursor: query_value(params, "cursor"),
      history_cursor: query_value(params, "history_cursor"),
      details_cursor: query_value(params, "details_cursor")
    }
  end

  defp maybe_load_list(socket, requested, reload_call?) do
    if reload_call? or socket.assigns.list_cursor != requested.list_cursor do
      {status, page} = load_list(socket.assigns.principal, requested.list_cursor)
      assign(socket, status: status, page: page)
    else
      socket
    end
  end

  defp maybe_load_detail(socket, requested, reload_call?) do
    if reload_call? or socket.assigns.history_cursor != requested.history_cursor do
      {status, persisted, live} =
        load_detail(socket.assigns.principal, requested.call_id, requested.history_cursor)

      assign(socket, detail_status: status, persisted: persisted, live: live)
    else
      socket
    end
  end

  defp load_list(principal, cursor) do
    options = [limit: @list_page_size] ++ option(cursor, :cursor)

    case CallInspection.list_calls(principal, options) do
      {:ok, page} -> {:available, page}
      {:error, _reason} -> {:unavailable, nil}
    end
  end

  defp load_detail(principal, call_id, cursor) do
    options = [limit: @history_page_size] ++ option(cursor, :cursor)
    persisted_result = CallInspection.inspect_call(principal, call_id, options)
    live_result = load_live(principal, call_id, persisted_result)

    inspection_state(persisted_result, live_result)
  end

  defp maybe_load_recordings(socket, requested, true) do
    case CallRecording.list(socket.assigns.principal, requested.call_id) do
      {:ok, recordings} ->
        assign(socket, recordings: recordings, recordings_status: :available)

      {:error, _reason} ->
        assign(socket, recordings: [], recordings_status: :unavailable)
    end
  end

  defp maybe_load_recordings(socket, _requested, false), do: socket

  defp maybe_load_usage(socket, requested, true) do
    case CallInspection.usage_report(socket.assigns.principal, requested.call_id) do
      {:ok, report} -> assign(socket, usage_report: report, usage_status: :available)
      {:error, _reason} -> assign(socket, usage_report: nil, usage_status: :unavailable)
    end
  end

  defp maybe_load_usage(socket, _requested, false), do: socket

  defp maybe_load_call_details(socket, requested, reload_call?) do
    if reload_call? or socket.assigns.details_cursor != requested.details_cursor do
      options = [limit: @details_page_size] ++ option(requested.details_cursor, :cursor)

      case CallDetails.list(socket.assigns.principal, requested.call_id, options) do
        {:ok, page} ->
          assign(socket, call_details_page: page, call_details_status: :available)

        {:error, _reason} ->
          assign(socket, call_details_page: nil, call_details_status: :unavailable)
      end
    else
      socket
    end
  end

  defp load_live(principal, call_id, {:ok, %CallDetailPage{call: %{state: state}}})
       when state in [:admitting, :running] do
    CallInspection.inspect_live_call(principal, call_id)
  end

  defp load_live(_principal, _call_id, {:ok, %CallDetailPage{}}), do: :not_requested

  defp load_live(principal, call_id, {:error, _reason}) do
    CallInspection.inspect_live_call(principal, call_id)
  end

  defp inspection_state({:ok, persisted}, {:ok, live}), do: {:live, persisted, live}

  defp inspection_state({:ok, persisted}, _live_result),
    do: {persisted_status(persisted), persisted, nil}

  defp inspection_state({:error, _reason}, {:ok, live}), do: {:live_only, nil, live}

  defp inspection_state({:error, :call_not_found}, {:error, :call_not_live}),
    do: {:not_found, nil, nil}

  defp inspection_state({:error, _reason}, _live_result), do: {:unavailable, nil, nil}

  defp persisted_status(%CallDetailPage{call: %{state: state}})
       when state in [:admitting, :running],
       do: :runtime_unavailable

  defp persisted_status(%CallDetailPage{}), do: :persisted
  defp persisted_status(nil), do: :unavailable

  defp option(nil, _option), do: []
  defp option(value, option), do: [{option, value}]

  defp query_value(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and byte_size(value) > 0 -> value
      _missing -> nil
    end
  end

  defp maybe_cancel_refresh(socket, false), do: socket

  defp maybe_cancel_refresh(socket, true) do
    assign(socket, refresh_token: nil)
  end

  defp reconcile_live_refresh(socket) do
    if connected?(socket) and socket.assigns.detail_status == :live and
         is_nil(socket.assigns.refresh_token) do
      token = make_ref()
      _timer = Process.send_after(self(), {:refresh_live_inspection, token}, @refresh_interval_ms)
      assign(socket, refresh_token: token)
    else
      socket
    end
  end
end
