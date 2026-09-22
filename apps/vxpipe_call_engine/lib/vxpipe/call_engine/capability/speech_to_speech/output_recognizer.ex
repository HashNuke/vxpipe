defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.OutputRecognizer do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.{Descriptor, Session}

  def start(%{output_stt_options: {nil, _scope, _private}} = state),
    do: {:ok, %{state | output_stt: nil}}

  def start(%{output_stt_options: {{module, opts}, scope, private}} = state)
      when not is_nil(scope) do
    with {:ok, descriptor} <- module.configure(opts),
         :ok <- Descriptor.validate(descriptor),
         true <- descriptor.kind == :stt and descriptor.finite_input?,
         true <- function_exported?(module, :finish_input, 1) do
      allocate(state, module, opts, scope, private)
    else
      _ -> {:error, :unsupported_finite_input}
    end
  end

  def start(state), do: {:ok, %{state | output_stt: nil}}

  def finish_input(%{output_stt: nil}), do: :ok
  def finish_input(%{active_output: %{stt_text: :failed}}), do: :ok

  def finish_input(%{
        output_stt: %{provider: {module, _}, session: session, ready?: true}
      }) do
    case Session.provider(session) do
      provider when is_pid(provider) ->
        try do
          apply(module, :finish_input, [provider])
        catch
          _, _ -> {:error, :unavailable}
        end

      _missing ->
        {:error, :unavailable}
    end
  end

  def finish_input(_state), do: :ok

  defp allocate(state, module, opts, scope, private) do
    session_options = [
      owner: self(),
      consumer: self(),
      provider: module,
      options: opts,
      private: private,
      usage: false
    ]

    case Session.start(scope, session_options) do
      {:ok, session, :starting} ->
        {:ok,
         %{
           state
           | output_stt: %{
               provider: {module, opts},
               session: session,
               descriptor: nil,
               ready?: false,
               pending_text: nil,
               pending_audio: [],
               fed_chunks: 0,
               dropped_chunks: 0,
               restarts: 0,
               restart_attempts: 0,
               retry_scheduled?: false,
               recovery_failed?: false
             }
         }}

      {:error, _reason} = error ->
        error
    end
  end
end
