defmodule Vxpipe.Providers.Credential do
  @moduledoc "Local shape validation for one provider's credential material."

  @callback auth_kind() :: String.t()
  @type preview_field :: %{
          field: String.t(),
          label: String.t(),
          display: :last_four | :masked
        }
  @callback preview_fields() :: [preview_field()]
  @callback validate(String.t(), map()) :: :ok | {:error, :invalid_provider_auth}
end
