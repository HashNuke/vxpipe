defmodule Vxpipe.Console.CallDetails do
  @moduledoc "Loads validated call-details publications for Console operators."

  alias Vxpipe.Calls.{
    CallDetailsDocument,
    CallReadAccess,
    CallDetailsRevision,
    CallDetailsRevisionPage
  }

  @spec list(CallReadAccess.authority(), String.t(), keyword()) ::
          {:ok, CallDetailsRevisionPage.t()} | {:error, term()}
  def list(authority, call_id, options \\ [])
      when is_binary(call_id) and is_list(options) do
    {module, backend_options, request_options} = backend(options)

    module
    |> apply(:list, [backend_options, authority, call_id, request_options])
    |> validate_page()
  end

  @spec fetch(CallReadAccess.authority(), String.t(), String.t(), keyword()) ::
          {:ok, CallDetailsDocument.t()} | {:error, term()}
  def fetch(authority, call_id, publication_id, options \\ [])
      when is_binary(call_id) and is_binary(publication_id) and is_list(options) do
    {module, backend_options, request_options} = backend(options)

    module
    |> apply(:fetch, [backend_options, authority, call_id, publication_id, request_options])
    |> validate_document()
  end

  defp backend(options) do
    {backend, request_options} = Keyword.pop(options, :backend)

    {module, backend_options} =
      backend || Application.fetch_env!(:vxpipe_console, :call_details_backend)

    {module, backend_options, request_options}
  end

  defp validate_page({:ok, %CallDetailsRevisionPage{revisions: revisions}} = result)
       when is_list(revisions) do
    if Enum.all?(revisions, &is_struct(&1, CallDetailsRevision)),
      do: result,
      else: {:error, :invalid_call_details_response}
  end

  defp validate_page({:error, _reason} = error), do: error
  defp validate_page(_response), do: {:error, :invalid_call_details_response}

  defp validate_document({:ok, %CallDetailsDocument{}} = result), do: result
  defp validate_document({:error, _reason} = error), do: error
  defp validate_document(_response), do: {:error, :invalid_call_details_response}
end
