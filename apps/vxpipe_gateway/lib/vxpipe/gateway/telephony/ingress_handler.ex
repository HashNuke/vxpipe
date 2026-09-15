defmodule Vxpipe.Gateway.Telephony.IngressHandler do
  @moduledoc "Boundary for handing authenticated provider-neutral events to call control."

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.ConfiguredService

  @type context :: term()
  @type error_reason :: term()

  @callback handle_event(context(), ConfiguredService.t(), Event.t(), tuple() | nil) ::
              :ok | {:ok, term()} | {:error, error_reason()}

  @spec dispatch({module(), context()}, ConfiguredService.t(), Event.t(), tuple() | nil) ::
          :ok | {:ok, term()} | {:error, error_reason() | :invalid_ingress_handler_response}
  def dispatch({module, context}, %ConfiguredService{} = service, %Event{} = event, owner \\ nil)
      when is_atom(module) do
    case module.handle_event(context, service, event, owner) do
      :ok -> :ok
      {:ok, _result} = result -> result
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_ingress_handler_response}
    end
  end
end
