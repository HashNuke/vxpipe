defmodule Vxpipe.Identity.EmailTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.Email

  test "normalizes surrounding whitespace and case" do
    assert Email.normalize("  Admin@Example.COM \n") == {:ok, "admin@example.com"}
  end

  test "rejects empty and malformed addresses" do
    assert {:error, :invalid_email} = Email.normalize("   ")
    assert {:error, :invalid_email} = Email.normalize("not-an-email")
    assert {:error, :invalid_email} = Email.normalize("a@b")
  end

  test "rejects overlong addresses" do
    long = String.duplicate("a", 310) <> "@example.com"
    assert {:error, :invalid_email} = Email.normalize(long)
  end
end
