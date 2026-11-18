defmodule Vxpipe.Console.Integration.UniversalEditorBrowserTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, ProviderCredentials}
  alias Vxpipe.Console.Test.{UniversalEditorDriver, UniversalEditorSite}

  alias Vxpipe.Persistence.{
    CallSpecStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo
  }

  @moduletag :integration
  @moduletag :universal_editor_browser
  @moduletag timeout: 120_000

  for {provider, model, label} <- [
        {"google", "gemini-3.5-flash-lite", "Google AI Studio"},
        {"openai", "gpt-6-luna", "OpenAI"}
      ] do
    test "configured #{provider} saves and publishes through rendered editor" do
      if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
      sandbox = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox) end)

      {:ok, keyring} =
        CredentialKeyring.new("editor", %{"editor" => :crypto.strong_rand_bytes(32)})

      options = [
        credential_repository: {CredentialStore, Repo},
        call_spec_repository: {CallSpecStore, Repo},
        provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
        registries: %{host_tools: %{}}
      ]

      original = Application.fetch_env!(:vxpipe_calls, Calls)
      Application.put_env(:vxpipe_calls, Calls, Keyword.merge(original, options))
      on_exit(fn -> Application.put_env(:vxpipe_calls, Calls, original) end)

      {:ok, tenant, issued} =
        Administration.bootstrap_tenant("Synthetic editor acceptance", [:admin, :calls], options)

      {:ok, authority} = Administration.authenticate(tenant.key, issued.secret, :admin, options)
      provider = unquote(provider)
      model = unquote(model)

      assert {:ok, _credential} =
               ProviderCredentials.provision(
                 tenant.key,
                 provider,
                 "browser",
                 "api_key",
                 %{"api_key" => "synthetic-browser-only"},
                 options
               )

      source = source(provider, model)

      bootstrap = %{
        tenant: tenant.key,
        source: source,
        catalog: %{
          model_inference: %{provider => [%{id: model, name: model, default: true, voices: nil}]}
        },
        lookups: %{
          credentialNames: %{provider => ["browser"]},
          telephonyServices: [],
          mcpIntegrations: [],
          toolCatalog: %{tools: [], mcpAvailable: false}
        }
      }

      directory =
        Path.join(System.tmp_dir!(), "universal-editor-#{System.unique_integer([:positive])}")

      File.mkdir_p!(directory)
      on_exit(fn -> File.rm_rf!(directory) end)
      assert :ok = UniversalEditorDriver.build_assets(directory)

      server =
        start_supervised!(
          {Bandit,
           plug:
             {UniversalEditorSite,
              %{
                owner: self(),
                assets: directory,
                bootstrap: bootstrap,
                authority: authority,
                tenant: tenant.key
              }},
           ip: {127, 0, 0, 1},
           port: 0}
        )

      {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
      evidence = UniversalEditorDriver.run("http://127.0.0.1:#{port}", unquote(label))
      assert evidence["revision"] == 1
      assert evidence["publishedRevision"] == 1
      assert {:ok, stored} = Calls.fetch_call_spec(tenant.key, evidence["callSpecId"], 1, options)
      assert stored.source == JSON.decode!(JSON.encode!(source))
      assert stored.compiled_metadata["agent_protocol"]["version"] == "mode_message_v1"

      assert {:ok, published} =
               CallSpecStore.fetch_published_revision(Repo, tenant.key, stored.call_spec_id)

      assert published.revision == 1
      assert_receive {:universal_editor_write, _saved}
      assert_receive {:universal_editor_write, _published}

      IO.puts(
        "UNIVERSAL_EDITOR_EVIDENCE " <> JSON.encode!(Map.put(evidence, "provider", provider))
      )
    end
  end

  defp source(provider, model) do
    %{
      schema_version: "20261004.01",
      name: "Synthetic universal reply editor",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{
        capabilities: %{
          model_inference: %{
            provider: provider,
            model: model,
            credential_name: "browser",
            options: %{max_tokens: 4096}
          }
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt:
            "You are the assistant for a synthetic browser acceptance scenario. Help the caller clearly and concisely. Use native tools only when requested and never invent a result.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
