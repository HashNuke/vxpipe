defmodule Vxpipe.Calls.OperatorLoginChallenges do
  @moduledoc "Issues and verifies durable installation-operator login challenges."

  alias Vxpipe.Calls.{
    IssuedOperatorLoginChallenge,
    OperatorLoginChallenge,
    Repositories
  }

  @code_space 100_000_000
  @code_limit div(4_294_967_296, @code_space) * @code_space
  @lifetime_seconds 600
  @minimum_secret_bytes 32
  @verifier_key_label "vxpipe.operator-login.verifier-key.v1"
  @code_verifier_label "vxpipe.operator-login.code-verifier.v1"

  @spec issue(binary(), keyword()) ::
          {:ok, IssuedOperatorLoginChallenge.t()} | {:error, term()}
  def issue(verifier_secret, options \\ []) do
    with :ok <- validate_secret(verifier_secret),
         {:ok, repository} <- Repositories.fetch(options, :operator_login_challenge_repository) do
      now = now(options)
      random_bytes = Keyword.get(options, :random_bytes, &:crypto.strong_rand_bytes/1)
      token = random_bytes.(32) |> Base.url_encode64(padding: false)
      code = secure_code(random_bytes)
      expires_at = DateTime.add(now, @lifetime_seconds, :second)

      stored = %OperatorLoginChallenge{
        token_digest: token_digest(token),
        code_verifier: code_verifier(verifier_secret, token, code),
        failed_attempts: 0,
        expires_at: expires_at,
        consumed_at: nil,
        issued_at: now
      }

      case Repositories.call(repository, :insert, [stored]) do
        {:ok, %OperatorLoginChallenge{}} ->
          {:ok, %IssuedOperatorLoginChallenge{token: token, code: code, expires_at: expires_at}}

        {:error, _reason} = error ->
          error
      end
    end
  end

  @spec consume(String.t(), String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def consume(token, code, verifier_secret, options \\ []) do
    with :ok <- validate_token(token),
         :ok <- validate_code(code),
         :ok <- validate_secret(verifier_secret),
         {:ok, repository} <- Repositories.fetch(options, :operator_login_challenge_repository) do
      Repositories.call(repository, :consume, [
        token_digest(token),
        code_verifier(verifier_secret, token, code)
      ])
    end
  end

  defp secure_code(random_bytes) do
    value = random_bytes.(4) |> :binary.decode_unsigned()

    if value < @code_limit do
      value
      |> rem(@code_space)
      |> Integer.to_string()
      |> String.pad_leading(8, "0")
    else
      secure_code(random_bytes)
    end
  end

  defp token_digest(token), do: :crypto.hash(:sha256, token)

  defp code_verifier(secret, token, code) do
    verifier_key = :crypto.mac(:hmac, :sha256, secret, @verifier_key_label)

    :crypto.mac(
      :hmac,
      :sha256,
      verifier_key,
      @code_verifier_label <> <<0>> <> token_digest(token) <> <<0>> <> code
    )
  end

  defp validate_secret(secret)
       when is_binary(secret) and byte_size(secret) >= @minimum_secret_bytes,
       do: :ok

  defp validate_secret(_secret), do: {:error, :invalid_operator_login_secret}

  defp validate_token(token) when is_binary(token) and byte_size(token) in 1..512, do: :ok
  defp validate_token(_token), do: {:error, :invalid_operator_login_challenge}

  defp validate_code(code) when is_binary(code) and byte_size(code) <= 128, do: :ok
  defp validate_code(_code), do: {:error, :invalid_operator_login_challenge}

  defp now(options), do: Keyword.get(options, :now, DateTime.utc_now())
end
