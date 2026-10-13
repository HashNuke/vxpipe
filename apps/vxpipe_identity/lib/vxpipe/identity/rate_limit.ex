defmodule Vxpipe.Identity.RateLimit do
  @moduledoc """
  Bounded login/setup throttling policy. Pure window check over attempt
  timestamps; persistence adapter owns cluster-wide accounting and expiry.
  """

  @max_per_account 10
  @max_per_address 30
  @window_seconds 600

  @spec limits() :: %{max_per_account: pos_integer(), max_per_address: pos_integer(), window_seconds: pos_integer()}
  def limits do
    %{max_per_account: @max_per_account, max_per_address: @max_per_address, window_seconds: @window_seconds}
  end

  @spec window_seconds() :: pos_integer()
  def window_seconds, do: @window_seconds

  @spec allowed?([DateTime.t()], [DateTime.t()], DateTime.t()) :: :ok | {:error, :rate_limited}
  def allowed?(account_attempts, address_attempts, now) do
    window_start = DateTime.add(now, -@window_seconds, :second)

    recent_account = Enum.count(account_attempts, &(DateTime.compare(&1, window_start) == :gt))
    recent_address = Enum.count(address_attempts, &(DateTime.compare(&1, window_start) == :gt))

    if recent_account >= @max_per_account or recent_address >= @max_per_address do
      {:error, :rate_limited}
    else
      :ok
    end
  end
end
