defmodule Vxpipe.Console.SampleCall do
  @moduledoc "Configuration gate for actor-authorized sample operations; owns no runtime state."

  alias Vxpipe.Calls

  def prepare(actor),
    do:
      configured(fn config, options ->
        Calls.prepare_configured_sample(actor, config, options)
      end)

  def prepare_transfer(actor, params) do
    configured(fn config, options ->
      Calls.prepare_sample_transfer(
        actor,
        config,
        params["tenant_key"],
        params["call_id"],
        options
      )
    end)
  end

  defp configured(operation) do
    settings = Application.fetch_env!(:vxpipe_console, :sample_call)

    if Keyword.get(settings, :enabled, false) do
      config =
        settings
        |> Keyword.take([:tenant_key, :call_spec, :initial_variables, :transfer_participant])
        |> Map.new()

      operation.(config, Keyword.get(settings, :calls_options, []))
    else
      {:error, :disabled}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end
end
