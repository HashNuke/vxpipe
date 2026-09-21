defmodule Vxpipe.Calls.ProviderCredentialValidator do
  @moduledoc "Validates submitted provider authentication without persisting or returning secrets."

  @callback validate(term(), String.t(), String.t(), map()) ::
              :ok
              | {:error,
                 :provider_credential_rejected
                 | :provider_validation_unavailable
                 | :provider_validation_unsupported}
end
