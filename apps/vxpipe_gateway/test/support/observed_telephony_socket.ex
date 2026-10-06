defmodule Vxpipe.Gateway.TestObservedTelephonySocket do
  @moduledoc false
  @behaviour WebSock
  @derive {Inspect, only: [:module]}
  defstruct [:module, :inner]

  @impl true
  def init(options) do
    module =
      case options.binding.provider do
        :twilio -> Vxpipe.Providers.Twilio.TelephonyMediaSocket
        :telnyx -> Vxpipe.Providers.Telnyx.TelephonyMediaSocket
      end

    with {:ok, inner} <- module.init(options),
         do: {:ok, %__MODULE__{module: module, inner: inner}}
  end

  @impl true
  def handle_in({message, _metadata} = frame, state) do
    decoded =
      case JSON.decode(message) do
        {:ok, map} when is_map(map) -> map
        _invalid -> %{}
      end

    event = event(Map.get(decoded, "event"))
    format = decoded |> Map.get("start", %{}) |> format() |> Map.merge(dtmf_shape(decoded))
    result = state.module.handle_in(frame, state.inner)
    observe(state, event, result, format)
    wrap(result, state)
  end

  @impl true
  def handle_info(message, state) do
    result = state.module.handle_info(message, state.inner)
    if elem(result, 0) in [:push, :stop], do: observe(state, :server, result, %{})
    wrap(result, state)
  end

  defp wrap({:ok, inner}, state), do: {:ok, %{state | inner: inner}}
  defp wrap({:push, frames, inner}, state), do: {:push, frames, %{state | inner: inner}}

  defp wrap({:stop, reason, close, inner}, state),
    do: {:stop, reason, close, %{state | inner: inner}}

  defp wrap({:stop, reason, inner}, state), do: {:stop, reason, %{state | inner: inner}}

  defp observe(state, event, result, format) do
    close =
      case result do
        {:stop, _, {code, _}, _} when is_integer(code) and code in 1000..4999 -> code
        _other -> nil
      end

    metadata =
      Map.merge(format, %{
        provider: state.inner.binding.provider,
        event: event,
        result: elem(result, 0),
        close_code: close
      })

    :telemetry.execute([:vxpipe, :test, :telephony, :socket], %{count: 1}, metadata)
  end

  defp format(start) when is_map(start) do
    format = Map.get(start, "mediaFormat", Map.get(start, "media_format", %{}))

    if is_map(format) and map_size(format) > 0 do
      encoding =
        case Map.get(format, "encoding") do
          "audio/x-mulaw" -> :mulaw
          "OPUS" -> :opus
          _other -> :unknown
        end

      %{
        encoding: encoding,
        sample_rate:
          bounded(Map.get(format, "sampleRate", Map.get(format, "sample_rate")), 192_000),
        channels: bounded(Map.get(format, "channels"), 8)
      }
    else
      %{}
    end
  end

  defp format(_other), do: %{}

  defp dtmf_shape(%{"event" => "dtmf", "dtmf" => dtmf}) when is_map(dtmf) do
    track =
      case Map.get(dtmf, "track") do
        "inbound_track" -> :inbound_track
        "inbound" -> :inbound
        _other -> :other
      end

    %{dtmf_track: track, dtmf_press_one?: Map.get(dtmf, "digit") == "1"}
  end

  defp dtmf_shape(_other), do: %{}

  defp bounded(value, maximum) when is_integer(value) and value > 0 and value <= maximum,
    do: value

  defp bounded(_value, _maximum), do: nil

  defp event("connected"), do: :connected
  defp event("start"), do: :start
  defp event("media"), do: :media
  defp event("mark"), do: :mark
  defp event("dtmf"), do: :dtmf
  defp event("stop"), do: :stop
  defp event(_other), do: :unknown
end
