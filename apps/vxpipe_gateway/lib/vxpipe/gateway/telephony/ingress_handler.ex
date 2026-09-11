defmodule Vxpipe.Gateway.Telephony.IngressHandler do
  @moduledoc "Boundary for handing authenticated provider-neutral events to call control."

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.IngressIdentity

  @type context :: term()
  @type error_reason :: term()

  @callback handle_event(context(), IngressIdentity.t(), Event.t()) ::
              :ok | {:ok, term()} | {:error, error_reason()}

  @spec dispatch({module(), context()}, IngressIdentity.t(), Event.t()) ::
          :ok | {:ok, term()} | {:error, error_reason() | :invalid_ingress_handler_response}
  def dispatch({module, context}, %IngressIdentity{} = identity, %Event{} = event)
      when is_atom(module) do
    case module.handle_event(context, identity, event) do
      :ok -> :ok
      {:ok, _result} = result -> result
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_ingress_handler_response}
    end
  end
end
