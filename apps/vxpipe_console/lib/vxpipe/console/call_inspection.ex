defmodule Vxpipe.Console.CallInspection do
  @moduledoc "Loads validated call-inspection projections for Console pages."

  alias Vxpipe.Calls.{CallDetailPage, CallListPage, LiveCallInspection, Principal}

  @spec list_calls(Principal.t(), keyword()) ::
          {:ok, CallListPage.t()} | {:error, term()}
  def list_calls(%Principal{} = principal, options \\ []) when is_list(options) do
    {module, backend_options, request_options} = backend(options)

    module
    |> apply(:list_calls, [backend_options, principal, request_options])
    |> validate_response(CallListPage)
  end

  @spec inspect_call(Principal.t(), String.t(), keyword()) ::
          {:ok, CallDetailPage.t()} | {:error, term()}
  def inspect_call(%Principal{} = principal, call_id, options \\ [])
      when is_binary(call_id) and is_list(options) do
    {module, backend_options, request_options} = backend(options)

    module
    |> apply(:inspect_call, [backend_options, principal, call_id, request_options])
    |> validate_response(CallDetailPage)
  end

  @spec inspect_live_call(Principal.t(), String.t(), keyword()) ::
          {:ok, LiveCallInspection.t()} | {:error, term()}
  def inspect_live_call(%Principal{} = principal, call_id, options \\ [])
      when is_binary(call_id) and is_list(options) do
    {module, backend_options, request_options} = backend(options)

    module
    |> apply(:inspect_live_call, [backend_options, principal, call_id, request_options])
    |> validate_response(LiveCallInspection)
  end

  defp backend(options) do
    {backend, request_options} = Keyword.pop(options, :backend)

    {module, backend_options} =
      backend || Application.fetch_env!(:vxpipe_console, :call_inspection_backend)

    {module, backend_options, request_options}
  end

  defp validate_response({:ok, value}, expected_module) do
    if is_struct(value, expected_module),
      do: {:ok, value},
      else: {:error, :invalid_inspection_response}
  end

  defp validate_response({:error, _reason} = error, _expected_module), do: error
  defp validate_response(_value, _expected_module), do: {:error, :invalid_inspection_response}
end
