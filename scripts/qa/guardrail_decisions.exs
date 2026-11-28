# bin/livetests decisions starts an isolated Mix VM with the installation's
# normal credential source. Start only the database client and the call engine.
ExUnit.start(autorun: false)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Vxpipe.Persistence.Repo.start_link()
{:ok, _} = Application.ensure_all_started(:vxpipe_call_engine)

support = Path.expand("../../apps/vxpipe_call_engine/test/support", __DIR__)

for fixture <- ~w(agent_runtime_model_provider audio_output_sink blocking_tool call_startup
                  collecting_archive_writer transfer_connection guardrail_decisions_scenario) do
  Code.require_file(fixture <> ".ex", support)
end

defmodule Vxpipe.QA.ConfiguredDecisionsTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.TestGuardrailDecisionsScenario
  alias Vxpipe.Calls.CallSpecCredentials

  @tag timeout: 90_000
  test "the saved Decisions connection gates conversational and native calls" do
    [provider, tenant, connection] = System.argv()
    models = %{"openai" => "gpt-6-luna", "google" => "gemini-decision-1", "jev" => "jev-1.14.0"}

    selection = %{
      provider: provider,
      model: Map.fetch!(models, provider),
      credential_name: connection
    }

    samples =
      TestGuardrailDecisionsScenario.run(tenant, selection,
        prepare_plan: fn spec, plan ->
          case CallSpecCredentials.pin(spec, plan, []) do
            {:ok, pinned} ->
              pinned

            {:error, _} ->
              flunk(
                "Cannot resolve #{provider}/#{connection} for tenant #{tenant}. Check the saved connection in Integrations."
              )
          end
        end
      )

    for {event, rows} <- Enum.group_by(samples, &Map.fetch!(&1, "event")) do
      times = Enum.sort(Enum.map(rows, & &1["duration_ms"]))
      percentile = fn fraction -> Enum.at(times, ceil(length(times) * fraction) - 1) end

      summary = %{
        event: event,
        selected_provider: provider,
        selected_model: selection.model,
        n: length(rows),
        p50_ms: percentile.(0.50),
        p95_ms: percentile.(0.95),
        samples: rows
      }

      IO.puts("Decisions hosted measurements " <> JSON.encode!(summary))
    end
  end
end

%{failures: failures, total: 1} = ExUnit.run()
System.halt(if failures == 0, do: 0, else: 1)
