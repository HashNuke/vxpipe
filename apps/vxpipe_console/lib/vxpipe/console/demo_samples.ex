defmodule Vxpipe.Console.DemoSamples do
  @moduledoc "Checked-in first-call catalog and explicit tenant installer."

  alias Vxpipe.Calls.InstallationOperator

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

  @spec install(InstallationOperator.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def install(authority, tenant_key, options \\ [])

  def install(
        %InstallationOperator{grant: :installation_operator} = authority,
        tenant_key,
        options
      )
      when is_binary(tenant_key) and is_list(options) do
    :global.trans({{__MODULE__, tenant_key}, self()}, fn ->
      install_locked(authority, tenant_key, options)
    end)
  end

  def install(%InstallationOperator{}, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  def install(_authority, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  defp install_locked(authority, tenant_key, options) do
    with {:ok, directory} <-
           Vxpipe.Calls.list_operator_service_bindings(authority, tenant_key, options),
         {:ok, model_provider} <- sample_providers(directory.bindings),
         {:ok, page} <-
           Vxpipe.Calls.list_operator_call_specs(
             authority,
             tenant_key,
             Keyword.merge(options, page: 1, limit: 100)
           ) do
      summaries = Map.new(page.call_specs, &{&1.id, &1})

      results =
        model_provider
        |> catalog()
        |> Enum.map(&install_entry(&1, tenant_key, summaries, options))

      {:ok, results}
    end
  end

  defp install_entry(entry, tenant_key, summaries, options) do
    case Map.fetch(summaries, entry.id) do
      :error -> create_entry(entry, tenant_key, options)
      {:ok, summary} -> resume_entry(entry, tenant_key, summary, options)
    end
  end

  defp create_entry(entry, tenant_key, options) do
    save_options = Keyword.put(options, :call_spec_id, entry.id)

    with {:ok, draft} <- Vxpipe.Calls.save_call_spec(tenant_key, entry.source, save_options),
         {:ok, published} <-
           Vxpipe.Calls.publish_call_spec(
             tenant_key,
             draft.call_spec_id,
             draft.revision,
             options
           ) do
      installed(entry, published.revision)
    else
      {:error, reason} -> failed(entry, reason)
    end
  end

  defp resume_entry(entry, tenant_key, summary, options) do
    with {:ok, latest} <-
           Vxpipe.Calls.fetch_call_spec(tenant_key, entry.id, summary.latest_revision, options),
         true <- latest.source_digest == source_digest(entry.source) do
      if summary.published_revision == latest.revision do
        installed(entry, latest.revision)
      else
        case Vxpipe.Calls.publish_call_spec(tenant_key, entry.id, latest.revision, options) do
          {:ok, published} -> installed(entry, published.revision)
          {:error, reason} -> failed(entry, reason)
        end
      end
    else
      false -> %{id: entry.id, name: entry.name, status: :conflict}
      {:error, reason} -> failed(entry, reason)
    end
  end

  defp installed(entry, revision) do
    %{id: entry.id, name: entry.name, status: :installed, revision: revision}
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
