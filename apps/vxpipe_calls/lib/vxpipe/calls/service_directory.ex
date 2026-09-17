defmodule Vxpipe.Calls.ServiceDirectory do
  @moduledoc "Metadata-only provider credentials and telephony registrations for one tenant."

  alias Vxpipe.Calls.{ProviderCredential, TelephonyService, Tenant}

  @enforce_keys [:tenant, :credentials, :telephony_services, :truncated]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant: Tenant.t(),
          credentials: [ProviderCredential.t()],
          telephony_services: [TelephonyService.t()],
          truncated: boolean()
        }
end
