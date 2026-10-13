defmodule Vxpipe.Identity.PasswordPolicyTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.Password

  test "accepts 15..128 chars with spaces preserved" do
    assert :ok = Password.validate("correct horse 15!")
    assert :ok = Password.validate(String.duplicate("a", 128))
  end

  test "rejects short, long, and overlong-bytes passwords" do
    assert {:error, :too_short} = Password.validate("short-13-chars")
    assert {:error, :too_long} = Password.validate(String.duplicate("a", 129))
  end

  test "never trims input" do
    assert :ok = Password.validate("  padded password!!")
  end
end
