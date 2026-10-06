defmodule Vxpipe.CallEngine.Speech.Input do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.{Allocation, CapabilityTree, Channel}

  def start_link(allocation),
    do: GenServer.start_link(__MODULE__, allocation, name: address(allocation))

  def address(allocation), do: CapabilityTree.address({allocation.generation, :input})

  def submit(allocation, command, audio),
    do: GenServer.cast(address(allocation), {:input, command, audio})

  @impl true
  def init(allocation), do: {:ok, allocation}

  @impl true
  def handle_cast({:input, command, audio}, allocation) do
    result = execute(allocation, command, audio)
    GenServer.cast(Channel.address(allocation), {:input_result, command.ref, self(), result})
    {:noreply, allocation}
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :speech_input)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp execute(allocation, command, audio) do
    remaining = command.deadline - System.monotonic_time(:millisecond)

    with true <- remaining > 0 and Allocation.valid?(allocation),
         {:ok, module, provider} <-
           GenServer.call(Channel.address(allocation), {:claim_input, command.ref}, remaining) do
      if command.deadline > System.monotonic_time(:millisecond) and Allocation.valid?(allocation),
        do: execute_provider(module, provider, command, audio),
        else: {:error, :session_failed}
    else
      _failure -> {:error, :session_failed}
    end
  rescue
    _error -> {:error, :session_failed}
  catch
    _kind, _reason -> {:error, :session_failed}
  end

  defp accepted(:ok), do: :ok
  defp accepted({:error, :busy}), do: {:error, :busy}
  defp accepted(_failure), do: {:error, :session_failed}

  defp execute_provider(module, provider, %{response_context: context} = command, payload) do
    operation =
      case Map.get(command, :operation) do
        {:push_text, reference, text} -> {:text, reference, text}
        {:begin_opening, reference, opening} -> {:opening, reference, opening}
        {:input_activity, boundary} -> {:activity, boundary}
        nil -> {:audio, payload}
      end

    case module.submit_input(provider, context, operation) do
      :ok -> :ok
      {:error, reason} when reason in [:busy, :unsupported_operation] -> {:error, reason}
      _failure -> {:error, :session_failed}
    end
  end

  defp execute_provider(
         module,
         provider,
         %{operation: {:begin_opening, reference, opening}},
         _payload
       ) do
    if function_exported?(module, :begin_opening, 3) do
      case module.begin_opening(provider, reference, opening) do
        :ok -> :ok
        {:error, reason} when reason in [:busy, :unsupported_operation] -> {:error, reason}
        _failure -> {:error, :session_failed}
      end
    else
      {:error, :unsupported_operation}
    end
  end

  defp execute_provider(module, provider, %{operation: {:push_text, reference, text}}, _payload) do
    case module.push_text(provider, reference, text) do
      :ok ->
        :ok

      {:error, reason} when reason in [:busy, :unsupported_operation] ->
        {:error, reason}

      _failure ->
        {:error, :session_failed}
    end
  end

  defp execute_provider(module, provider, %{operation: {:input_activity, boundary}}, _payload) do
    case module.input_activity(provider, boundary) do
      :ok ->
        :ok

      {:error, reason} when reason in [:busy, :unsupported_operation] ->
        {:error, reason}

      _failure ->
        {:error, :session_failed}
    end
  end

  defp execute_provider(module, provider, %{operation: {:speak, reference}}, text) do
    case module.speak(provider, reference, text) do
      :ok ->
        :ok

      {:error, reason}
      when reason in [
             :busy,
             :empty_text,
             :invalid_text,
             :input_too_large,
             :output_too_large,
             :unsupported_character
           ] ->
        {:error, reason}

      _failure ->
        {:error, :session_failed}
    end
  end

  defp execute_provider(module, provider, %{operation: {:cancel, reference}}, playback) do
    case module.cancel(provider, reference, playback) do
      :ok -> :ok
      _failure -> {:error, :session_failed}
    end
  end

  defp execute_provider(module, provider, _command, audio),
    do: accepted(module.push_audio(provider, audio))
end
