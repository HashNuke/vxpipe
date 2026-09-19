defmodule Vxpipe.Persistence.CredentialCipher do
  @moduledoc false

  alias Vxpipe.Persistence.CredentialKeyring
  alias Vxpipe.Calls.ProviderCredential

  def encrypt(keyring, identity, payload) do
    with {:ok, key_id, key} <- CredentialKeyring.current(keyring) do
      nonce = :crypto.strong_rand_bytes(12)
      envelope_version = if ProviderCredential.owner(identity) == :platform, do: 2, else: 1

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          key,
          nonce,
          JSON.encode!(payload),
          associated_data(identity, key_id, envelope_version),
          16,
          true
        )

      {:ok, key_id,
       <<envelope_version, nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>>}
    end
  end

  def decrypt(
        keyring,
        identity,
        key_id,
        <<version, nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>>
      )
      when version in [1, 2] do
    with true <- valid_owner?(identity, version),
         {:ok, key} <- CredentialKeyring.fetch(keyring, key_id),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             nonce,
             ciphertext,
             associated_data(identity, key_id, version),
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

  defp valid_owner?(identity, 1), do: match?({:tenant, _}, ProviderCredential.owner(identity))
  defp valid_owner?(identity, 2), do: ProviderCredential.owner(identity) == :platform

  defp associated_data(identity, key_id, version) do
    owner = if version == 1, do: identity.tenant_key, else: ["platform"]

    JSON.encode!([
      "vxpipe/provider-credential/aes-256-gcm/v#{version}",
      owner,
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
