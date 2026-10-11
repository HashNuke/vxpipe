defmodule Vxpipe.Console.Integration.STTRestartCompatibilityTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :capture_log
  @moduletag timeout: 120_000

  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.Calls.{Administration, ProviderCredentials}

  alias Vxpipe.Persistence.{
    CallSpecStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo,
    ResolvedPlanCodec
  }

  setup do
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      call_spec_repository: {CallSpecStore, Repo}
    ]

    %{options: options}
  end

  @tag :tmp_dir
  test "fresh VMs prepare stored published onset choices and historical manual Scribe", context do
    {:ok, tenant, _} = Administration.bootstrap_tenant("STT restart", [:admin], context.options)

    {:ok, _credential} =
      ProviderCredentials.provision(
        tenant.key,
        "elevenlabs",
        "default",
        "api_key",
        %{"api_key" => "synthetic-restart-fixture"},
        context.options
      )

    snapshots =
      for mode <- [:omitted, false, true] do
        {:ok, draft} = Vxpipe.Calls.save_call_spec(tenant.key, source(mode), context.options)
        assert draft.validation_errors == []

        {:ok, published} =
          Vxpipe.Calls.publish_call_spec(
            tenant.key,
            draft.call_spec_id,
            draft.revision,
            context.options
          )

        {:ok, reloaded} =
          Vxpipe.Calls.fetch_call_spec(
            tenant.key,
            published.call_spec_id,
            published.revision,
            context.options
          )

        assert reloaded.source == published.source

        {:ok, spec} =
          CallSpec.new(reloaded.source,
            resource_id: reloaded.call_spec_id,
            revision: reloaded.revision
          )

        {:ok, invocation} =
          CallInvocation.new(
            %{
              call_spec: %{id: reloaded.call_spec_id, revision: reloaded.revision},
              transport: %{type: "web"}
            },
            tenant_id: tenant.key,
            actor_id: "restart-fixture"
          )

        {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
        {mode, plan}
      end

    {:omitted, original} = List.keyfind(snapshots, :omitted, 0)
    caller = Map.fetch!(original.participants, "caller")

    historical = %{
      caller
      | capabilities: %{
          caller.capabilities
          | speech_to_text: Map.delete(caller.capabilities.speech_to_text, :vad)
        }
    }

    legacy = %{original | participants: Map.put(original.participants, "caller", historical)}

    encoded =
      Enum.map([{:legacy, legacy} | snapshots], fn {mode, plan} ->
        selection = Map.fetch!(plan.participants, "caller").capabilities.speech_to_text

        {mode, ResolvedPlanCodec.encode(plan),
         CapabilitySelection.identity(selection, tenant.key)}
      end)

    path = Path.join(context.tmp_dir, "published-stt-snapshots.bin")
    File.write!(path, :erlang.term_to_binary(encoded, [:deterministic]))
    root = Path.expand("../../../..", __DIR__)
    probe = "apps/vxpipe_console/test/fixtures/stt_restart_probe.exs"

    for _restart <- 1..2 do
      {output, status} =
        System.cmd("mix", ["run", "--no-compile", probe, path],
          cd: root,
          env: [{"MIX_ENV", "test"}],
          stderr_to_stdout: true
        )

      assert status == 0, "fresh-VM STT preparation failed:\n#{output}"

      for mode <- [:legacy, :omitted, false, true],
          do: assert(output =~ "STT restart snapshot verified: #{mode}")
    end
  end

  defp source(mode) do
    selection = %{provider: "elevenlabs", model: "scribe_v2_realtime"}
    selection = if mode == :omitted, do: selection, else: Map.put(selection, :vad, mode)

    %{
      schema_version: "20260915.01",
      name: "STT restart",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{
        capabilities: %{
          model_inference: %{provider: "fixture", model: "echo"},
          speech_to_text: selection
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer briefly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
