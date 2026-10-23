defmodule Vxpipe.Persistence.OAuth.RateLimit do
  @moduledoc "Durable, bounded OAuth request budgets shared across application instances."

  alias Vxpipe.Persistence.OAuth.Transaction
  alias Vxpipe.Persistence.Repo

  @limits %{register: {10, 200}, authorize: {60, 600}, token: {120, 2_000}, revoke: {60, 600}}

  def check(operation, client_address), do: check(operation, client_address, [])

  @doc false
  def check(operation, client_address, options) do
    with {:ok, {per_address, global}} <- Map.fetch(@limits, operation),
         true <- canonical_address?(client_address),
         {:ok, now, per_address, global} <- settings(options, per_address, global) do
      operation = Atom.to_string(operation)
      window = div(now, 60) * 60
      digest = Transaction.digest(client_address)

      Transaction.run(fn ->
        cleanup(operation, window)

        if increment(operation, "global", <<>>, window, global) <= global and
             increment(operation, "address", digest, window, per_address) <= per_address,
           do: :ok,
           else: {:commit_error, :rate_limited}
      end)
    else
      _invalid -> {:error, :unavailable}
    end
  end

  defp settings(options, per_address, global) when is_list(options) do
    now = Keyword.get(options, :now, System.system_time(:second))
    address_limit = Keyword.get(options, :per_address, per_address)
    global_limit = Keyword.get(options, :global, global)

    if is_integer(now) and now >= 0 and
         is_integer(address_limit) and address_limit in 1..per_address and
         is_integer(global_limit) and global_limit in 1..global,
       do: {:ok, now, address_limit, global_limit},
       else: :error
  end

  defp settings(_options, _per_address, _global), do: :error

  defp canonical_address?(address) when is_binary(address) and byte_size(address) in 1..45 do
    with true <- String.valid?(address),
         {:ok, parsed} <- :inet.parse_strict_address(String.to_charlist(address)) do
      to_string(:inet.ntoa(parsed)) == address
    else
      _invalid -> false
    end
  end

  defp canonical_address?(_address), do: false

  defp cleanup(operation, window) do
    Repo.query!(
      "DELETE FROM oauth_rate_limits WHERE operation = $1 AND window_start < $2",
      [operation, window - 120],
      Transaction.options()
    )
  end

  defp increment(operation, bucket, digest, window, limit) do
    # The global upsert holds its row lock until transaction completion. It
    # serializes admission and caps how many address rows can exist per window.
    %{rows: [[attempts]]} =
      Repo.query!(
        """
        INSERT INTO oauth_rate_limits (operation, bucket, identity_digest, window_start, attempts)
        VALUES ($1, $2, $3, $4, 1)
        ON CONFLICT (operation, bucket, identity_digest, window_start)
        DO UPDATE SET attempts = LEAST(oauth_rate_limits.attempts + 1, $5)
        RETURNING attempts
        """,
        [operation, bucket, digest, window, limit + 1],
        Transaction.options()
      )

    attempts
  end
end
