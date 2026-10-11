defmodule Vxpipe.Console.Test.STTRestartProbe do
  alias Vxpipe.CallEngine.{PlanStartup, ResolvedCallPlan, TestTenantCredentialSource}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, ConversationalSTT, Event, Session}
  alias Vxpipe.Console.Test.ScribeTransport
  alias Vxpipe.Persistence.ResolvedPlanCodec
  alias Vxpipe.Providers.ElevenLabs.STTSession

  def run(path) do
    ResolvedCallPlan.ensure_data_loaded!()
    Code.ensure_loaded!(CapabilitySelection)
    modes = [:legacy, :omitted, false, true]
    snapshots = path |> File.read!() |> :erlang.binary_to_term([:safe])
    true = Enum.all?(snapshots, fn {mode, _encoded, _identity} -> mode in modes end)
    Enum.each(snapshots, &prepare/1)
  end

  defp prepare({mode, encoded, identity}) do
    {:ok, plan} = ResolvedPlanCodec.decode(encoded)
    true = ResolvedPlanCodec.encode(plan) == encoded
    caller = Map.fetch!(plan.participants, "caller")

    true =
      CapabilitySelection.identity(caller.capabilities.speech_to_text, plan.tenant_id) == identity

    credential_source =
      {TestTenantCredentialSource,
       {self(),
        %{
          {plan.tenant_id, "elevenlabs", "default"} => %{"api_key" => "synthetic-restart-fixture"}
        }}}

    engine = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    {:ok, startup} =
      PlanStartup.new(plan,
        owner: self(),
        credential_source: credential_source,
        agent_runtime: Keyword.fetch!(engine, :agent_runtime),
        speech_to_text: [
          providers: %{
            STTSession => [
              enabled: true,
              wire_module: ScribeTransport,
              wire_options: [observer: self()],
              media_ingress: [
                maximum_frames: 50,
                maximum_bytes: 262_144,
                maximum_age_ms: 2_000,
                maximum_consecutive_overflows: 5
              ]
            ]
          }
        ]
      )

    runtime = Map.fetch!(startup.speech_to_text_runtimes, caller.participant_id)
    {provider, options} = runtime.provider

    if mode == :legacy do
      STTSession = provider
      :manual = Keyword.fetch!(options, :commit_strategy)
      false = Map.has_key?(caller.capabilities.speech_to_text, :vad)
    else
      ConversationalSTT = provider
      true = Keyword.fetch!(options, :vad) == (mode == true)
      :vad = options |> Keyword.fetch!(:options) |> Keyword.fetch!(:commit_strategy)
    end

    {:ok, supervisor} =
      Supervisor.start_link([{CapabilityTree, owner: self()}],
        strategy: :one_for_one,
        name: __MODULE__.Supervisor
      )

    [{CapabilityTree, tree, :supervisor, _modules}] = Supervisor.which_children(supervisor)

    {:ok, session, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: provider,
        options: options,
        private: runtime.provider_private,
        start_timeout: 30_000
      )

    receive do
      {:vxpipe_speech, %Event{session: ^session, kind: :ready} = event} ->
        :ok = Session.ack(session, event)
    after
      30_000 -> raise "STT restart readiness timed out"
    end

    {:ok, descriptor} = Session.describe(session)
    expected_endpoint = if mode == :legacy, do: :local_gap, else: :inferred_gap
    true = descriptor.endpointing == expected_endpoint
    monitor = Process.monitor(Session.tree(session))
    :ok = Session.close(session)

    receive do
      {:DOWN, ^monitor, :process, _tree, _reason} -> :ok
    after
      5_000 -> raise "STT restart allocation did not retire"
    end

    :ok = Supervisor.stop(supervisor)
    IO.puts("STT restart snapshot verified: #{mode}")
  end
end

[path] = System.argv()
Vxpipe.Console.Test.STTRestartProbe.run(path)
