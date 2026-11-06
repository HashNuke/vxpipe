defmodule Vxpipe.Persistence.MCP.SecretCipher do
  @moduledoc """
  MCP secret envelopes using the installation credential keyring.

  Authenticated identity separates tenant connections, configuration generations,
  authentication methods and secret purposes. A grant cannot be replayed as
  static credentials or moved to another tenant. Re-encryption changes the key
  and nonce, not the identity or configuration generation.
  """

  alias Vxpipe.Persistence.CredentialKeyring

  @max_bytes 65_536
  @methods ~w(none bearer headers basic oauth)
  @purposes ~w(connection registration grant attempt)

  def encrypt(keyring, identity, payload) when is_map(payload) and not is_struct(payload) do
    with {:ok, binding} <- secret_identity(identity),
         plaintext = JSON.encode!(payload),
         true <- byte_size(plaintext) <= @max_bytes,
         {:ok, key_id, key} <- CredentialKeyring.current(keyring) do
      nonce = :crypto.strong_rand_bytes(12)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          key,
          nonce,
          plaintext,
          associated_data(binding, key_id),
          16,
          true
        )

      {:ok, key_id, <<1, nonce::binary, tag::binary, ciphertext::binary>>}
    else
      {:error, :credential_key_unavailable} = error -> error
      _invalid -> {:error, :invalid_mcp_secret}
    end
  rescue
    _error -> {:error, :invalid_mcp_secret}
  end

  def encrypt(_keyring, _identity, _payload), do: {:error, :invalid_mcp_secret}

  def decrypt(
        keyring,
        identity,
        key_id,
        <<1, nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>>
      )
      when byte_size(ciphertext) <= @max_bytes do
    with {:ok, binding} <- secret_identity(identity),
         {:ok, key} <- CredentialKeyring.fetch(keyring, key_id),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             nonce,
             ciphertext,
             associated_data(binding, key_id),
             tag,
             false
           ),
         {:ok, payload} when is_map(payload) <- JSON.decode(plaintext) do
      {:ok, payload}
    else
      {:error, :credential_key_unavailable} = error -> error
      _invalid -> {:error, :mcp_secret_unreadable}
    end
  rescue
    _error -> {:error, :mcp_secret_unreadable}
  end

  def decrypt(_keyring, _identity, _key_id, _envelope), do: {:error, :mcp_secret_unreadable}

  defp secret_identity(%{
         tenant_key: tenant,
         connection_id: connection,
         generation: generation,
         auth_method: method,
         purpose: purpose
       })
       when is_binary(tenant) and byte_size(tenant) in 1..128 and
              is_binary(connection) and byte_size(connection) in 1..128 and
              is_integer(generation) and generation > 0 and method in @methods and
              purpose in @purposes do
    {:ok, [tenant, connection, generation, method, purpose]}
  end

  defp secret_identity(_identity), do: {:error, :invalid_mcp_secret}

  defp associated_data(binding, key_id),
    do: JSON.encode!(["vxpipe/mcp-secret/aes-256-gcm/v1", key_id | binding])
end
