defmodule Vxpipe.Calls.OperatorLoginChallengesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.OperatorLoginChallenges

  @now ~U[2026-09-17 07:30:00.000000Z]
  @secret :binary.copy(<<42>>, 32)
  @verifier_key_label "vxpipe.operator-login.verifier-key.v1"
  @code_verifier_label "vxpipe.operator-login.code-verifier.v1"

  test "issues a redacted ten-minute challenge and persists only verifiers" do
    options = [
      operator_login_challenge_repository:
        {Vxpipe.Calls.Test.OperatorLoginChallengeRepository, self()},
      random_bytes: fn
        32 -> :binary.copy(<<1>>, 32)
        4 -> <<0, 0, 0, 7>>
      end,
      now: @now
    ]

    assert {:ok, issued} = OperatorLoginChallenges.issue(@secret, options)
    assert issued.code == "00000007"
    assert {:ok, token_bytes} = Base.url_decode64(issued.token, padding: false)
    assert byte_size(token_bytes) == 32
    assert issued.expires_at == DateTime.add(@now, 600, :second)

    assert_received {:insert_operator_login_challenge, stored}
    assert stored.token_digest == :crypto.hash(:sha256, issued.token)

    assert stored.code_verifier == code_verifier(issued.token, issued.code)

    assert stored.failed_attempts == 0
    assert stored.consumed_at == nil
    refute inspect(issued) =~ issued.token
    refute inspect(issued) =~ issued.code
    refute Map.has_key?(Map.from_struct(stored), :token)
    refute Map.has_key?(Map.from_struct(stored), :code)
  end

  test "consumption sends only token and code verifiers to the repository" do
    repository = {Vxpipe.Calls.Test.OperatorLoginChallengeRepository, self()}

    assert :ok =
             OperatorLoginChallenges.consume("url-token", "01234567", @secret,
               operator_login_challenge_repository: repository
             )

    assert_received {:consume_operator_login_challenge, token_digest, code_verifier}
    assert token_digest == :crypto.hash(:sha256, "url-token")

    assert code_verifier == code_verifier("url-token", "01234567")
  end

  test "rejects malformed secrets and token values before repository access" do
    repository = {Vxpipe.Calls.Test.OperatorLoginChallengeRepository, self()}
    options = [operator_login_challenge_repository: repository, now: @now]

    assert {:error, :invalid_operator_login_secret} =
             OperatorLoginChallenges.issue("short", options)

    assert {:error, :invalid_operator_login_challenge} =
             OperatorLoginChallenges.consume("", "01234567", @secret, options)

    refute_received _message
  end

  test "passes a malformed code to persistence so a valid token spends an attempt" do
    repository = {Vxpipe.Calls.Test.OperatorLoginChallengeRepository, self()}

    assert :ok =
             OperatorLoginChallenges.consume("token", "123", @secret,
               operator_login_challenge_repository: repository
             )

    assert_received {:consume_operator_login_challenge, _token_digest, code_verifier}
    assert code_verifier == code_verifier("token", "123")
  end

  defp code_verifier(token, code) do
    verifier_key = :crypto.mac(:hmac, :sha256, @secret, @verifier_key_label)
    token_digest = :crypto.hash(:sha256, token)

    :crypto.mac(
      :hmac,
      :sha256,
      verifier_key,
      @code_verifier_label <> <<0>> <> token_digest <> <<0>> <> code
    )
  end
end
