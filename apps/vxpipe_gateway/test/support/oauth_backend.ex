defmodule Vxpipe.Gateway.Test.OAuthBackend do
  @moduledoc false

  def rate_limit(operation, address) do
    send(self(), {:oauth_rate_limit, operation, address})
    Process.get({__MODULE__, :rate_limit}, :ok)
  end

  def register_client(params) do
    send(self(), {:oauth_register, params})
    result({:ok, Map.put(params, "client_id", "11111111-1111-4111-8111-111111111111")})
  end

  def exchange(params, resource) do
    send(self(), {:oauth_exchange, params, resource})

    result(
      {:ok, %{"access_token" => "test-token", "token_type" => "Bearer", "expires_in" => 600}}
    )
  end

  def revoke(params, resource) do
    send(self(), {:oauth_revoke, params, resource})
    result(:ok)
  end

  defp result(default) do
    case Process.get({__MODULE__, :result}, default) do
      :raise -> raise "credential-sentinel"
      :exit -> exit("credential-sentinel")
      value -> value
    end
  end
end
