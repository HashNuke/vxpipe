defmodule Vxpipe.Gateway.CallSpecAuthoring do
  @moduledoc false
  alias Vxpipe.Calls

  def authenticate(options, :operator, _tenant, secret),
    do: Calls.authenticate_operator(secret, options)

  def authenticate(options, :tenant, tenant, secret),
    do: Calls.authenticate(tenant, secret, :admin, options)

  def providers(options, author, tenant, capability),
    do: Calls.list_providers(author, tenant, capability, options)

  def models(options, author, tenant, provider, capability),
    do: Calls.list_provider_models(author, tenant, provider, capability, options)

  def save(options, author, tenant, source, id) do
    options =
      if id,
        do: Keyword.put(options, :call_spec_id, id),
        else: Keyword.delete(options, :call_spec_id)

    Calls.save_authorized_call_spec(author, tenant, source, options)
  end

  def publish(options, author, tenant, id, revision),
    do: Calls.publish_authorized_call_spec(author, tenant, id, revision, options)
end
