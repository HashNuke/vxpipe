defmodule Vxpipe.Identity.PasswordHasher do
  @moduledoc "Port for Argon2id password hashing owned by the identity application."

  @callback hash(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback verify(String.t(), String.t()) :: boolean()
end
