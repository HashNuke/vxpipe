defmodule Vxpipe.Providers.Credential do
  @moduledoc "Local shape validation for one provider's credential material."

  @callback validate(String.t(), map()) :: :ok | {:error, :invalid_provider_auth}
end
