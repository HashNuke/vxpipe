defmodule Vxpipe.Console.Provider.CredentialValidation do
  @moduledoc "Builds the bounded authentication request owned by one provider integration."

  @callback request(String.t(), map()) ::
              {:ok, keyword()} | {:error, :provider_validation_unsupported}
end
