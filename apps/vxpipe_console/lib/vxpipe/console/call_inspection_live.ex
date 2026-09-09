defmodule Vxpipe.Console.CallInspectionLive do
  @moduledoc false

  use Phoenix.LiveView, layout: false

  alias Vxpipe.Console.{CallInspection, CallInspectionComponents}

  @page_size 25

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, socket.assigns.principal, params)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        selected_id: nil,
        selected_event_id: nil,
        history_cursor: nil,
        persisted: nil,
        live: nil,
        detail_status: :none
      )

    CallInspectionComponents.index(assigns)
  end

  defp load_page(socket, principal, params) do
    options = [limit: @page_size] ++ cursor_option(params)

    case CallInspection.list_calls(principal, options) do
      {:ok, page} ->
        assign(socket,
          principal: principal,
          page: page,
          status: :available,
          list_cursor: query_value(params, "cursor")
        )

      {:error, _reason} ->
        assign(socket,
          principal: principal,
          page: nil,
          status: :unavailable,
          list_cursor: query_value(params, "cursor")
        )
    end
  end

  defp cursor_option(%{"cursor" => cursor}) when is_binary(cursor) and byte_size(cursor) > 0,
    do: [cursor: cursor]

  defp cursor_option(_params), do: []

  defp query_value(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and byte_size(value) > 0 -> value
      _missing -> nil
    end
  end
end
