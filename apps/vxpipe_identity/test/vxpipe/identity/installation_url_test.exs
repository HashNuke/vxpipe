defmodule Vxpipe.Identity.InstallationURLTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Identity.InstallationURL

  test "keeps only the canonical origin, including a non-default port" do
    assert {:ok, "https://calls.example.test"} = InstallationURL.normalize("HTTPS://CALLS.example.test/setup")
    assert {:ok, "https://calls.example.test:8443"} =
             InstallationURL.normalize(" https://CALLS.example.test:8443/admin?tab=url#setup ")

    assert {:ok, "https://calls.example.test"} =
             InstallationURL.normalize("https://calls.example.test:443/path/..")

    assert {:ok, "http://localhost:4000"} =
             InstallationURL.normalize("http://localhost:4000/setup")

    assert {:ok, "http://[::1]:4000"} = InstallationURL.normalize("http://[::1]:4000/setup")
  end

  test "rejects ambiguous, credential-bearing and insecure non-loopback origins" do
    for value <- [
          nil,
          12,
          "",
          "example.test",
          "http://example.test",
          "https://user:pass@example.test",
          "https://@example.test",
          "https://bad host.test",
          "https://host.test\\@other.test",
          "https://host.test:0",
          "https://host.test:65536",
          "https:///host.test",
          "https://host.test/" <> String.duplicate("a", 2048)
        ] do
      assert {:error, :invalid_public_url} = InstallationURL.normalize(value)
    end
  end
end
