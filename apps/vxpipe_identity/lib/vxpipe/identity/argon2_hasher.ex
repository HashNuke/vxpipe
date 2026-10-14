defmodule Vxpipe.Identity.Argon2Hasher do
  @moduledoc "Maintained Argon2id library adapter. No custom password cryptography."
  @behaviour Vxpipe.Identity.PasswordHasher

  @impl true
  def hash(password) when is_binary(password) do
    {:ok, Argon2.hash_pwd_salt(password)}
  rescue
    error -> {:error, error}
  end

  @impl true
  def verify(password, hash) when is_binary(password) and is_binary(hash) do
    Argon2.verify_pass(password, hash)
  rescue
    _ -> false
  end

  def verify(_password, _hash), do: false
end
