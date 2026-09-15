defmodule Vxpipe.Persistence.TestControlledCredentialSource do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.CredentialSource

  @impl true
  def resolve({options, observer, paused_name}, tenant_id, provider, name) do
    if name == paused_name do
      send(observer, {:tenant_credential_pending, self(), provider, name})

      receive do
        :resolve ->
          Vxpipe.Calls.ProviderCredentialSource.resolve(options, tenant_id, provider, name)
      after
        5_000 -> {:error, :test_resolution_timeout}
      end
    else
      Vxpipe.Calls.ProviderCredentialSource.resolve(options, tenant_id, provider, name)
    end
  end
end
