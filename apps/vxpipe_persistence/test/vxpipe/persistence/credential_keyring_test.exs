defmodule Vxpipe.Persistence.CredentialKeyringTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Persistence.CredentialKeyring

  test "loads an explicitly versioned keyring without exposing keys through Inspect" do
    key = :crypto.strong_rand_bytes(32)
    encoded = JSON.encode!(%{"v1" => Base.encode64(key)})
    assert {:ok, keyring} = CredentialKeyring.from_config("v1", encoded)
    assert {:ok, "v1", ^key} = CredentialKeyring.current(keyring)
    refute inspect(keyring) =~ Base.encode64(key)
    refute inspect(keyring) =~ inspect(key)
    assert {:ok, nil} = CredentialKeyring.from_config(nil, nil)
  end

  test "partial, malformed or invalid keys fail with safe errors and no default key" do
    for {id, encoded} <- [
          {"v1", nil},
          {nil, "{}"},
          {"v1", "sensitive-invalid-json"},
          {"v1", "[]"},
          {"v1", "{}"},
          {"v1", ~s({"v2":"not-base64"})},
          {"v1", JSON.encode!(%{"v1" => Base.encode64("short")})},
          {"v1", JSON.encode!(%{"v1" => 42})}
        ] do
      assert {:error, :invalid_credential_keyring} = CredentialKeyring.from_config(id, encoded)
    end
  end
end
