defmodule Vxpipe.Console.OperatorLoginConfigurationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.OperatorLoginConfiguration

  @secret String.duplicate("deployment-secret-", 4)

  test "accepts explicit HTTPS and normalizes its origin" do
    assert {:ok, configuration} =
             OperatorLoginConfiguration.build(
               [scheme: "https", host: "Console.Example.COM.", port: 8443],
               @secret
             )

    assert configuration.origin == "https://console.example.com:8443"
    assert byte_size(configuration.verifier_secret) == 32
    refute configuration.verifier_secret == @secret
    refute inspect(configuration) =~ configuration.verifier_secret
  end

  test "accepts a syntactically valid IPv6 HTTPS host" do
    assert {:ok, configuration} =
             OperatorLoginConfiguration.build(
               [scheme: "https", host: "2001:db8::1", port: 8443],
               @secret
             )

    assert configuration.origin == "https://[2001:db8::1]:8443"
  end

  test "allows explicit HTTP only for syntactic loopback hosts" do
    for {host, expected} <- [
          {"localhost", "http://localhost:4000"},
          {"127.0.0.1", "http://127.0.0.1:4000"},
          {"::1", "http://[::1]:4000"}
        ] do
      assert {:ok, configuration} =
               OperatorLoginConfiguration.build(
                 [scheme: "http", host: host, port: 4000],
                 @secret
               )

      assert configuration.origin == expected
    end
  end

  test "rejects insecure non-loopback and implicit or malformed origins" do
    for url <- [
          [scheme: "http", host: "vxpipe.example.com", port: 4000],
          [host: "localhost", port: 4000],
          [scheme: "ftp", host: "localhost", port: 4000],
          [scheme: "https", host: "", port: 443],
          [scheme: "https", host: "vxpipe.example.com", port: 70_000],
          [scheme: "https", host: "vxpipe.example.com:443"],
          [scheme: "https", host: "vxpipe\\example.com"],
          [scheme: "https", host: "-invalid.example.com"],
          [scheme: "https", host: "vxpipe.example.com", path: "/console"],
          [scheme: "https", host: "vxpipe.example.com", userinfo: "operator:secret"],
          [scheme: "https", host: "vxpipe.example.com", query: "token=secret"],
          [scheme: "https", host: "vxpipe.example.com", fragment: "secret"]
        ] do
      assert {:error, :invalid_operator_login_origin} =
               OperatorLoginConfiguration.build(url, @secret)
    end
  end

  test "rejects an absent or short deployment secret" do
    url = [scheme: "https", host: "vxpipe.example.com"]

    for secret <- [nil, "", "short", String.duplicate("x", 63)] do
      assert {:error, :invalid_operator_login_secret} =
               OperatorLoginConfiguration.build(url, secret)
    end
  end
end
