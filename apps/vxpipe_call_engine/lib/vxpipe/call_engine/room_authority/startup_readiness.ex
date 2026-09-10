defmodule Vxpipe.CallEngine.RoomAuthority.StartupReadiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.{CallLifecycle, Error, ResolvedCallPlan}
  alias Vxpipe.CallEngine.RoomAuthority.FirstMessage

  def bind(%CreateRoom{}, _incarnation_id), do: {:ok, nil}

  def bind(%ResolvedCallPlan{}, incarnation_id) do
    case CallLifecycle.bind(incarnation_id, self()) do
      {:ok, lifecycle} -> {:ok, lifecycle}
      {:error, :unavailable} -> {:error, :call_lifecycle_unavailable}
    end
  end

  def connection_attached(command, state) do
    case state.speech_to_text_runtime do
      :application ->
        ready(state)

      runtimes when is_map(runtimes) ->
        if Map.get(runtimes, command.participant_id) == nil do
          ready(state)
        else
          {:ok, state}
        end
    end
  end

  def ready(%{startup_ready?: true} = state), do: FirstMessage.start(state)

  def ready(state) do
    case CallLifecycle.ready(state.call_lifecycle) do
      :ok -> FirstMessage.start(%{state | startup_ready?: true})
      {:error, :unavailable} -> {:error, lifecycle_unavailable()}
    end
  end

  defp lifecycle_unavailable do
    Error.new(
      :call_lifecycle_unavailable,
      "The call lifecycle could not be updated.",
      retryable: true
    )
  end
end
