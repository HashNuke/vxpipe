defmodule Vxpipe.CallEngine.Diagnostics.SourceSupervisorTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.ResolvedCallPlan.{Capabilities, Participant}
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsSupervisor, SourceSupervisor}

  test "isolated worker capacity is enforced and retired children release their slots" do
    parent = self()

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: __MODULE__.Projection,
       reader: __MODULE__.Reader,
       loader: fn ->
         send(parent, :settings)
         {:ok, %{enabled: true, revision: 1}}
       end}
    )

    assert_receive :settings
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(__MODULE__.Projection)

    start_supervised!(
      {SourceSupervisor,
       name: __MODULE__.Pool,
       workers: __MODULE__.Workers,
       inference: __MODULE__.Inference,
       tasks: __MODULE__.Tasks,
       runtime: __MODULE__.Runtime,
       maximum_sources: 1}
    )

    {:ok, output} = CaptureHandoff.new(self(), projection: __MODULE__.Projection)

    options = [
      agent: llm_agent(),
      owner: self(),
      output: output,
      projection: __MODULE__.Projection,
      source_epoch: make_ref(),
      clock_id: "clock",
      source_id: "source",
      origin_us: System.monotonic_time(:microsecond)
    ]

    assert {:ok, worker} =
             SourceSupervisor.start_source(options, __MODULE__.Workers, __MODULE__.Runtime)

    assert {:error, :max_children} =
             SourceSupervisor.start_source(options, __MODULE__.Workers, __MODULE__.Runtime)

    monitor = Process.monitor(worker)
    assert :ok = DynamicSupervisor.terminate_child(__MODULE__.Workers, worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :shutdown}

    assert {:ok, _replacement} =
             SourceSupervisor.start_source(options, __MODULE__.Workers, __MODULE__.Runtime)
  end

  test "speech-to-speech and unknown agents are rejected before touching diagnostic resources" do
    llm = struct(CapabilitySelection, kind: :model_inference)
    sts = struct(CapabilitySelection, kind: :speech_to_speech)

    for agent <- [
          nil,
          %{},
          struct(Participant, kind: :agent, capabilities: %Capabilities{speech_to_speech: sts}),
          struct(Participant,
            kind: :agent,
            capabilities: %Capabilities{model_inference: llm, speech_to_speech: sts}
          ),
          struct(Participant, kind: :human, capabilities: %Capabilities{model_inference: llm}),
          struct(Participant, kind: :agent, capabilities: %Capabilities{model_inference: sts})
        ] do
      assert {:error, :unsupported_agent} =
               SourceSupervisor.start_source(
                 [agent: agent],
                 __MODULE__.AbsentWorkers,
                 __MODULE__.AbsentRuntime
               )
    end
  end

  defp llm_agent do
    struct(Participant,
      kind: :agent,
      capabilities: %Capabilities{
        model_inference: struct(CapabilitySelection, kind: :model_inference)
      }
    )
  end
end
