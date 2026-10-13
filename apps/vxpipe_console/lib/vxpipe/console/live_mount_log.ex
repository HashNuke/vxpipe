defmodule Vxpipe.Console.LiveMountLog do
  @moduledoc "Redacts browser sessions in Phoenix LiveView mount logs."

  @event [:phoenix, :live_view, :mount, :start]
  @phoenix_handler {Phoenix.LiveView.Logger, @event}
  @handler {__MODULE__, @event}

  @spec install() :: :ok | {:error, term()}
  def install do
    _ = :telemetry.detach(@phoenix_handler)
    _ = :telemetry.detach(@handler)
    :telemetry.attach(@handler, @event, &__MODULE__.handle_event/4, %{})
  end

  @doc false
  def handle_event(event, measurements, metadata, config) do
    redacted = Map.put(metadata, :session, "[REDACTED]")
    Phoenix.LiveView.Logger.lv_mount_start(event, measurements, redacted, config)
  end
end
