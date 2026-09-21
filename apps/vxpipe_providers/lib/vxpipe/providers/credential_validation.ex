defmodule Vxpipe.Providers.CredentialValidation do
  @moduledoc "Describes one bounded provider authentication request without performing I/O."

  @callback request(String.t(), map()) ::
              {:ok, keyword()} | {:error, :provider_validation_unsupported}
end
