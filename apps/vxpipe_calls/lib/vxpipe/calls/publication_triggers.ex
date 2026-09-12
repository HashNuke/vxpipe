defmodule Vxpipe.Calls.PublicationTriggers do
  @moduledoc "Requests best-effort call-details finalization after authoritative commits."

  alias Vxpipe.Calls.{PublicationFinalizerStarter, PublicationFinalizers}

  @default_starter PublicationFinalizers

  @spec request(String.t(), String.t(), keyword()) ::
          :disabled | {:ok, pid(), :started | :existing} | {:error, term()}
  def request(tenant_key, call_id, options)
      when is_binary(tenant_key) and tenant_key != "" and is_binary(call_id) and call_id != "" and
             is_list(options) do
    if enabled?(options) do
      with {:ok, starter} <- starter(options) do
        safely_start(starter, tenant_key, call_id, options)
      end
    else
      :disabled
    end
  end

  def request(_tenant_key, _call_id, _options), do: {:error, :invalid_publication_trigger}

  defp enabled?(options) do
    {configured, publication} = configured_settings()

    Keyword.get(
      options,
      :publication_enabled,
      Keyword.get(publication, :enabled, Keyword.get(configured, :publication_enabled, false))
    ) == true
  end

  defp starter(options) do
    {configured, publication} = configured_settings()

    starter =
      Keyword.get(
        options,
        :publication_finalizer_starter,
        Keyword.get(
          publication,
          :publication_finalizer_starter,
          Keyword.get(configured, :publication_finalizer_starter, @default_starter)
        )
      )

    if PublicationFinalizerStarter.valid?(starter),
      do: {:ok, starter},
      else: {:error, :publication_finalizer_starter_unavailable}
  end

  defp configured_settings do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])
    {configured, Keyword.get(configured, :call_details_publication, [])}
  end

  defp safely_start(starter, tenant_key, call_id, options) do
    starter.start(tenant_key, call_id, options)
  rescue
    exception -> {:error, {:publication_trigger_exception, exception.__struct__}}
  catch
    kind, reason -> {:error, {:publication_trigger_failure, kind, reason}}
  end
end
