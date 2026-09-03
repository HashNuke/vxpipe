defmodule Vxpipe.Gateway.SessionSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.Gateway.{Id, Session}

  @max_id_attempts 3

  def start_link(_options) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  def issue(binding, ttl_ms) when is_list(binding) and is_integer(ttl_ms) and ttl_ms > 0 do
    issue(binding, ttl_ms, @max_id_attempts)
  end

  defp issue(_binding, _ttl_ms, 0), do: {:error, :session_start_failed}

  defp issue(binding, ttl_ms, attempts_remaining) do
    session_id = Id.generate(:session)
    options = [session_id: session_id, ttl_ms: ttl_ms] ++ binding

    case DynamicSupervisor.start_child(__MODULE__, {Session, options}) do
      {:ok, session} ->
        {:ok, Session.snapshot(session)}

      {:error, {:already_started, _pid}} ->
        issue(binding, ttl_ms, attempts_remaining - 1)

      {:error, _reason} ->
        {:error, :session_start_failed}
    end
  end
end
