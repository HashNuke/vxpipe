defmodule Vxpipe.Gateway.HTTP.Mount do
  @moduledoc """
  Composes the gateway's HTTP routes into another Plug pipeline.

  The mount claims the gateway health route, API namespace and scoped Telnyx webhooks,
  then delegates to `Vxpipe.Gateway.HTTP.Endpoint`. Other paths continue through the
  host pipeline.
  """

  @behaviour Plug

  alias Plug.Conn
  alias Vxpipe.Gateway.HTTP.Endpoint

  @impl true
  def init(options) do
    options =
      Keyword.validate!(options,
        path_prefix: "/",
        operator_api: [],
        call_spec_authoring: [],
        call_admission: [],
        cors: [],
        room_creation: [],
        telephony: [],
        webrtc: []
      )

    %{
      endpoint:
        Endpoint.init(
          call_spec_authoring: Keyword.fetch!(options, :call_spec_authoring),
          operator_api: Keyword.fetch!(options, :operator_api),
          cors: Keyword.fetch!(options, :cors),
          call_admission: Keyword.fetch!(options, :call_admission),
          room_creation: Keyword.fetch!(options, :room_creation),
          telephony: Keyword.fetch!(options, :telephony),
          webrtc: Keyword.fetch!(options, :webrtc)
        ),
      path_prefix: prefix_segments(Keyword.fetch!(options, :path_prefix))
    }
  end

  @impl true
  def call(%Conn{} = conn, %{endpoint: endpoint, path_prefix: path_prefix}) do
    with {:ok, gateway_path} <- strip_prefix(conn.path_info, path_prefix),
         true <- gateway_path?(gateway_path) do
      %Conn{
        conn
        | path_info: gateway_path,
          script_name: conn.script_name ++ path_prefix
      }
      |> Endpoint.call(endpoint)
      |> Conn.halt()
    else
      _not_gateway_route -> conn
    end
  end

  defp prefix_segments("/"), do: []

  defp prefix_segments("/" <> path) do
    segments = String.split(path, "/")

    if Enum.all?(segments, &valid_segment?/1) do
      segments
    else
      raise ArgumentError, "path_prefix must be / or a slash-prefixed path without empty segments"
    end
  end

  defp prefix_segments(_path) do
    raise ArgumentError, "path_prefix must be / or a slash-prefixed path without empty segments"
  end

  defp valid_segment?(segment), do: segment not in ["", ".", ".."]

  defp strip_prefix(path, []), do: {:ok, path}

  defp strip_prefix(path, prefix) do
    prefix_length = length(prefix)

    if Enum.take(path, prefix_length) == prefix do
      {:ok, Enum.drop(path, prefix_length)}
    else
      :not_mounted
    end
  end

  defp gateway_path?(["healthz"]), do: true
  defp gateway_path?(["api" | _rest]), do: true
  defp gateway_path?(["webhooks", "platform", "telnyx"]), do: true
  defp gateway_path?(["webhooks", "tenants", _tenant, "telnyx"]), do: true
  defp gateway_path?(_path), do: false
end
