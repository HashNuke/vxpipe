defmodule Vxpipe.Providers.ElevenLabs.AgentLeaseRequest do
  @moduledoc false

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: 65_000
    }
  end

  def start_link(options), do: Task.start_link(fn -> run(options) end)

  defp run(options) do
    Process.flag(:trap_exit, true)
    lease = Keyword.fetch!(options, :lease)
    supervisor = Keyword.fetch!(options, :supervisor)
    monitor = Process.monitor(lease)
    api = Keyword.fetch!(options, :api_module)
    lifetime_ms = Keyword.fetch!(options, :lifetime_ms)

    result =
      try do
        api.with_agent(
          Keyword.fetch!(options, :client),
          Keyword.fetch!(options, :definition),
          fn connection ->
            send(lease, {:elevenlabs_agent_prepared, self(), connection})
            await_release(lease, monitor, supervisor, lifetime_ms)
          end
        )
      rescue
        _exception -> {:error, :preparation_failed}
      catch
        _kind, _reason -> {:error, :preparation_failed}
      end

    outcome = public_outcome(result)

    :telemetry.execute(
      [:vxpipe, :providers, :elevenlabs, :agent_lease, :finished],
      %{count: 1},
      %{lease: lease, outcome: outcome}
    )

    Process.demonitor(monitor, [:flush])
    send(lease, {:elevenlabs_agent_request_finished, self(), outcome})
  end

  defp public_outcome({:ok, reason}) when reason in [:released, :owner_lost, :lease_expired],
    do: reason

  defp public_outcome({:error, :cleanup_failed}), do: :cleanup_failed
  defp public_outcome(_failure), do: :preparation_failed

  defp await_release(lease, monitor, supervisor, lifetime_ms) do
    receive do
      {:elevenlabs_agent_release, ^lease, reason} when reason in [:released, :owner_lost] ->
        reason

      {:DOWN, ^monitor, :process, ^lease, _reason} ->
        :owner_lost

      {:EXIT, ^supervisor, _reason} ->
        :owner_lost
    after
      lifetime_ms -> :lease_expired
    end
  end
end
