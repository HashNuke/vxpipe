defmodule Vxpipe.Console.CallRecording do
  @moduledoc "Lists and opens tenant-authorized recordings for private playback."

  alias Vxpipe.Calls.Principal
  alias Vxpipe.Console.CallRecording.{Source, Summary}

  @spec list(Principal.t(), String.t(), keyword()) ::
          {:ok, [Summary.t()]} | {:error, term()}
  def list(principal, call_id, options \\ [])

  def list(%Principal{} = principal, call_id, options)
      when is_binary(call_id) and call_id != "" and is_list(options) do
    {backend, backend_options} = backend(options)

    backend
    |> apply(:list, [backend_options, principal, call_id])
    |> validate_list_response()
  end

  def list(_principal, _call_id, _options), do: {:error, :invalid_recording_request}

  @spec open(Principal.t(), String.t(), String.t(), keyword()) ::
          {:ok, Source.t()} | {:error, term()}
  def open(principal, call_id, artifact_id, options \\ [])

  def open(%Principal{} = principal, call_id, artifact_id, options)
      when is_binary(call_id) and call_id != "" and is_binary(artifact_id) and artifact_id != "" and
             is_list(options) do
    {backend, backend_options} = backend(options)

    backend
    |> apply(:open, [backend_options, principal, call_id, artifact_id])
    |> validate_response()
  end

  def open(_principal, _call_id, _artifact_id, _options),
    do: {:error, :invalid_recording_request}

  defp backend(options) do
    Keyword.get_lazy(options, :backend, fn ->
      Application.fetch_env!(:vxpipe_console, :call_recording_backend)
    end)
  end

  defp validate_list_response({:ok, summaries}) when is_list(summaries) do
    if Enum.all?(summaries, &match?(%Summary{}, &1)),
      do: {:ok, summaries},
      else: {:error, :invalid_recording_response}
  end

  defp validate_list_response({:error, _reason} = error), do: error
  defp validate_list_response(_response), do: {:error, :invalid_recording_response}

  defp validate_response({:ok, %Source{} = source}), do: {:ok, source}
  defp validate_response({:error, _reason} = error), do: error
  defp validate_response(_response), do: {:error, :invalid_recording_response}
end
