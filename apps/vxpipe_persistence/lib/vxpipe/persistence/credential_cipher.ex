defmodule Vxpipe.Persistence.CredentialCipher do
  @moduledoc false

  alias Vxpipe.Persistence.CredentialKeyring

  def encrypt(keyring, identity, payload) do
    with {:ok, key_id, key} <- CredentialKeyring.current(keyring) do
      nonce = :crypto.strong_rand_bytes(12)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          key,
          nonce,
          JSON.encode!(payload),
          associated_data(identity, key_id),
          16,
          true
        )

      {:ok, key_id, <<1, nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>>}
    end
  end

  def decrypt(
        keyring,
        identity,
        key_id,
        <<1, nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>>
      ) do
    with {:ok, key} <- CredentialKeyring.fetch(keyring, key_id),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             nonce,
             ciphertext,
             associated_data(identity, key_id),
             tag,
             false
           ),
         {:ok, payload} <- JSON.decode(plaintext) do
      {:ok, payload}
    else
      {:error, :credential_key_unavailable} = error -> error
      _invalid -> {:error, :provider_credential_unreadable}
    end
  end

  def decrypt(_keyring, _identity, _key_id, _ciphertext),
    do: {:error, :provider_credential_unreadable}

  defp associated_data(identity, key_id) do
    JSON.encode!([
      "vxpipe/provider-credential/aes-256-gcm/v1",
      identity.tenant_key,
      identity.id,
      identity.provider,
      identity.name,
      identity.auth_kind,
      identity.version,
      identity.payload_schema_version,
      key_id
    ])
  end
end
