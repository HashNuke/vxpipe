defmodule Vxpipe.Calls.DemoSamples do
  @moduledoc "Checked-in first-call catalog and explicit tenant installer."

  alias Vxpipe.Calls.{
    CallSpecAuthoring,
    CallSpecs,
    EffectiveServiceBindings,
    ProviderAuth,
    Repositories,
    Tenant,
    UserAuthorization
  }

  alias Vxpipe.Identity.Principal

  @catalog_version 1
  @model_providers ["google", "zenmux", "openai", "deepseek", "openrouter", "fireworks"]

  @spec catalog(String.t()) :: [map()]
  def catalog(model_provider) when model_provider in @model_providers do
    [
      entry(
        "sample-voice-conversation",
        "Voice conversation",
        "A direct browser conversation with a concise voice assistant.",
        participants(%{
          "assistant" => agent("You are a concise, helpful voice assistant.")
        }),
        model_provider
      ),
      entry(
        "sample-agent-handoff",
        "Agent handoff",
        "A receptionist can hand the conversation to a specialist agent.",
        participants(%{
          "assistant" =>
            agent(
              "You are a receptionist. Transfer to specialist when the caller asks for specialist help.",
              transfers: ["specialist"]
            ),
          "specialist" => agent("You are a concise product specialist.")
        }),
        model_provider
      ),
      entry(
        "sample-human-handoff",
        "Human handoff",
        "An assistant can transfer the caller to a separately joined support seat.",
        participants(%{
          "assistant" =>
            agent(
              "You are a support assistant. Transfer to human-support when the caller asks for a person.",
              transfers: ["human-support"]
            ),
          "human-support" => %{
            type: "human",
            description: "Browser support seat",
            connection: %{service: "web", mode: "receive", admission: "transfer"},
            transfer_notice: "A caller is waiting for human support."
          }
        }),
        model_provider
      )
    ]
  end

  @spec install(Principal.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def install(actor, tenant_key, options \\ [])

  def install(%Principal{} = actor, tenant_key, options) when is_list(options) do
    with :ok <- UserAuthorization.authorize_installation(actor, "tenants.write"),
         :ok <- ProviderAuth.tenant_key(tenant_key),
         :ok <- UserAuthorization.authorize_tenant(actor, "call_specs.write", tenant_key),
         :ok <- existing_demo(tenant_key, options) do
      :global.trans({{__MODULE__, tenant_key}, self()}, fn ->
        install_locked(actor, tenant_key, options)
      end)
    end
  end

  def install(_actor, _tenant_key, _options), do: {:error, :forbidden}

  defp existing_demo(tenant_key, options) do
    with {:ok, repository} <- Repositories.fetch(options, :demo_tenant_repository),
         {:ok, %Tenant{key: ^tenant_key}} <- Repositories.call(repository, :fetch, []) do
      :ok
    else
      {:ok, _other} -> {:error, :not_found}
      error -> error
    end
  end

  defp install_locked(actor, tenant_key, options) do
    with {:ok, directory} <- EffectiveServiceBindings.list(tenant_key, options),
         {:ok, model_provider} <- sample_providers(directory.bindings),
         :ok <- authorize_bindings(actor, directory.bindings, model_provider),
         {:ok, repository} <- Repositories.fetch(options, :call_spec_repository) do
      results =
        Enum.map(
          catalog(model_provider),
          &install_entry(&1, actor, tenant_key, repository, options)
        )

      {:ok, results}
    end
  end

  defp authorize_bindings(actor, bindings, model_provider) do
    inherited? =
      Enum.any?(bindings, fn binding ->
        binding.provider in ["deepgram", model_provider] and binding.name == binding.provider and
          binding.source == :platform
      end)

    if inherited? and not UserAuthorization.platform_authoring_allowed?(actor),
      do: {:error, :forbidden},
      else: :ok
  end

  # Revision one is immutable even when the display name changes. At most two
  # matches are needed to distinguish a unique sample from an ambiguous name.
  defp install_entry(entry, actor, tenant_key, repository, options) do
    case Repositories.call(repository, :find_by_original_name, [tenant_key, entry.name]) do
      {:ok, []} -> create_entry(entry, actor, tenant_key, options)
      {:ok, [id]} -> resume_entry(entry, actor, tenant_key, id, repository, options)
      {:ok, [_first, _second]} -> %{id: entry.id, name: entry.name, status: :conflict}
      {:error, reason} -> failed(entry, reason)
    end
  end

  defp create_entry(entry, actor, tenant_key, options) do
    with {:ok, draft} <- CallSpecAuthoring.save(actor, tenant_key, entry.source, options),
         {:ok, published} <-
           CallSpecAuthoring.publish(
             actor,
             tenant_key,
             draft.call_spec_id,
             draft.revision,
             options
           ) do
      installed(entry, published)
    else
      {:error, reason} -> failed(entry, reason)
    end
  end

  defp resume_entry(entry, actor, tenant_key, id, repository, options) do
    with {:ok, next} <- Repositories.call(repository, :next_revision, [tenant_key, id]),
         {:ok, latest} <- CallSpecs.fetch(tenant_key, id, next - 1, options),
         true <- latest.tenant_key == tenant_key and latest.call_spec_id == id,
         true <- latest.source_digest == source_digest(entry.source),
         {:ok, published} <- publish_if_needed(actor, tenant_key, latest, repository, options) do
      installed(entry, published)
    else
      false -> %{id: entry.id, name: entry.name, status: :conflict}
      {:error, reason} -> failed(entry, reason)
    end
  end

  defp publish_if_needed(actor, tenant_key, latest, repository, options) do
    case Repositories.call(repository, :fetch_published_revision, [
           tenant_key,
           latest.call_spec_id
         ]) do
      {:ok, %{revision: revision}} when revision == latest.revision ->
        {:ok, latest}

      {:ok, _older} ->
        CallSpecAuthoring.publish(
          actor,
          tenant_key,
          latest.call_spec_id,
          latest.revision,
          options
        )

      {:error, :call_spec_not_published} ->
        CallSpecAuthoring.publish(
          actor,
          tenant_key,
          latest.call_spec_id,
          latest.revision,
          options
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp installed(entry, revision) do
    %{
      id: entry.id,
      name: entry.name,
      status: :installed,
      call_spec_id: revision.call_spec_id,
      revision: revision.revision
    }
  end

  defp failed(entry, reason) do
    %{id: entry.id, name: entry.name, status: :failed, reason: reason}
  end

  defp sample_providers(bindings) do
    active =
      bindings
      |> Enum.filter(&(&1.status == :connected and &1.name == &1.provider))
      |> MapSet.new(& &1.provider)

    with true <- MapSet.member?(active, "deepgram"),
         provider when is_binary(provider) <-
           Enum.find(@model_providers, &MapSet.member?(active, &1)) do
      {:ok, provider}
    else
      _missing -> {:error, :sample_prerequisites_missing}
    end
  end

  defp entry(id, name, description, participants, model_provider) do
    %{
      id: id,
      name: name,
      description: description,
      version: @catalog_version,
      source: %{
        schema_version: "20260915.01",
        name: name,
        entry_caller: "caller",
        entry_receiver: "assistant",
        defaults: %{capabilities: capabilities(model_provider)},
        participants: participants,
        limits: %{max_duration_ms: 900_000}
      }
    }
  end

  defp participants(additional) do
    Map.put(additional, "caller", %{
      type: "human",
      description: "Browser caller",
      connection: %{service: "web", mode: "receive", admission: "start_call"}
    })
  end

  defp agent(prompt, options \\ []) do
    %{
      type: "agent",
      prompt: prompt,
      first_message: %{mode: "wait_for_input"},
      tools: %{"hangup" => %{type: "platform", tool: "hangup"}},
      transfers: Keyword.get(options, :transfers, [])
    }
  end

  defp capabilities(model_provider) do
    %{
      speech_to_text: %{
        provider: "deepgram",
        model: "flux-general-en",
        credential_name: "deepgram",
        options: %{encoding: "opus", sample_rate: 48_000}
      },
      model_inference: %{
        provider: model_provider,
        model: model_name(model_provider),
        credential_name: model_provider
      },
      text_to_speech: %{
        provider: "deepgram",
        model: "flux",
        credential_name: "deepgram",
        options: %{voice: "haley"}
      }
    }
  end

  defp model_name("google"), do: "gemini-2.5-flash"
  defp model_name("zenmux"), do: "openai/gpt-5"
  defp model_name("openai"), do: "gpt-5"
  defp model_name("deepseek"), do: "deepseek-flash"
  defp model_name("openrouter"), do: "google/gemini-3.5-flash-lite"
  defp model_name("fireworks"), do: "accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b"

  defp source_digest(source) do
    source
    |> JSON.encode!()
    |> JSON.decode!()
    |> JSON.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
