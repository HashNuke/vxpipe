defmodule Vxpipe.CallEngine.Diagnostics.SettingsReader do
  @moduledoc "One supervised settings IO slot; a stalled read cannot accumulate more work."
  use GenServer

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :reader))

  @impl true
  def init(options), do: {:ok, %{loader: Keyword.fetch!(options, :loader)}}

  @impl true
  def handle_info({:read_settings, owner, reference}, state)
      when is_pid(owner) and is_reference(reference) do
    result = read(state.loader)
    send(owner, {:settings_result, reference, result})
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status),
    do:
      status
      |> Map.put(:state, :redacted)
      |> Map.put(:message, :redacted)
      |> Map.put(:reason, :redacted)
      |> Map.put(:log, [])

  defp read(loader) do
    case loader.() do
      {:ok, %{enabled: enabled, revision: revision} = value}
      when is_boolean(enabled) and is_integer(revision) and map_size(value) == 2 ->
        {:ok, value}

      _ ->
        {:error, :settings_unavailable}
    end
  rescue
    _ -> {:error, :settings_unavailable}
  catch
    _, _ -> {:error, :settings_unavailable}
  end
end
