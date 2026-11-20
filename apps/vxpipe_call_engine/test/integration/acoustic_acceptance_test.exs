defmodule Vxpipe.CallEngine.Integration.AcousticAcceptanceTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :acoustic_accuracy
  @moduletag timeout: 300_000
  @moduletag :capture_log
  @moduletag :tmp_dir

  test "frozen human corpus traverses distinct native fallback and operational reuse paths",
       context do
    helper = Vxpipe.CallEngine.AcousticAcceptanceReplay
    assert Code.ensure_loaded?(helper), "native acoustic replay helper is not implemented"

    root = Path.expand("../../../..", __DIR__)
    corpus = Path.join(context.tmp_dir, "corpus")
    generator = Path.join(root, "scripts/diagnostics/acoustic_acceptance.py")
    {output, status} = System.cmd("python3", [generator, "--output", corpus])
    assert status == 0, output
    manifest = corpus |> Path.join("manifest.json") |> File.read!() |> JSON.decode!()
    assert length(manifest["cases"]) == 12

    traces =
      for mode <- [:benchmark_only, :operational_reuse], scenario <- manifest["cases"] do
        pcm = File.read!(Path.join(corpus, scenario["file"]))
        assert Base.encode16(:crypto.hash(:sha256, pcm), case: :lower) == scenario["sha256"]
        trace = apply(helper, :run, [pcm, mode])
        assert trace.mode == Atom.to_string(mode)
        assert trace.completed_samples >= scenario["samples"]
        assert trace.resets == []
        assert trace.raw_packets != []

        assert trace.path ==
                 if(mode == :benchmark_only,
                   do: "SourceWorker native diagnostic inference",
                   else:
                     "ConversationalSTT native inference -> InferenceTap -> SourceWorker reuse"
                 )

        Map.merge(trace, %{case_id: scenario["id"], pcm_sha256: scenario["sha256"]})
      end

    report = %{
      reference_sha256: manifest["reference_sha256"],
      manifest: manifest,
      traces: traces,
      provenance: provenance(root),
      scope:
        "offline frame-acknowledged acoustic accuracy; not live provider or performance evidence"
    }

    destination =
      System.get_env("VXPIPE_ACOUSTIC_REPORT") || Path.join(context.tmp_dir, "native.json")

    File.write!(destination, JSON.encode!(report))
    IO.puts("Acoustic acceptance artifact: #{destination}")
  end

  defp provenance(root) do
    {revision, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root)

    paths = [
      "apps/vxpipe_call_engine/test/support/acoustic_acceptance_replay.ex",
      "apps/vxpipe_call_engine/test/integration/acoustic_acceptance_test.exs",
      "apps/vxpipe_call_engine/lib/vxpipe/call_engine/diagnostics/source_worker.ex",
      "apps/vxpipe_call_engine/lib/vxpipe/call_engine/diagnostics/inference_tap.ex",
      "apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech/conversational_stt.ex",
      "apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech/activity_boundary.ex",
      "apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech/silero.ex",
      "scripts/diagnostics/acoustic_acceptance.py"
    ]

    %{
      source_revision: String.trim(revision),
      note: "Working-tree hashes identify executed code, including uncommitted helper changes",
      file_sha256:
        Map.new(paths, fn path ->
          {path,
           Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(root, path))), case: :lower)}
        end)
    }
  end
end
