defmodule Vxpipe.Console.Test.ConfiguredTelephonyFixture do
  @moduledoc false
  import ExUnit.Assertions

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    InstallationOperator,
    OperatorTelephonyApplications,
    ProviderCredentials,
    ProviderCredentialSource,
    TelephonyServices
  }

  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.Telephony.CallIngress
  alias Vxpipe.Persistence.EctoStorage
  alias Vxpipe.Providers.LiveModels

  @derive {Inspect, only: [:tenant]}
  defstruct [:tenant, :principal, :key, :settings, :options]

  def new(options, settings) do
    assert {:ok, tenant, key} =
             Administration.bootstrap_tenant("Live telephony", [:calls], options)

    assert {:ok, principal} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    provision(
      :platform,
      "telnyx",
      "telnyx",
      "api_key",
      %{"api_key" => settings.telnyx_key, "public_key" => settings.public_key},
      options
    )

    provision(
      :platform,
      "google",
      "live-telephony",
      "api_key",
      %{"api_key" => settings.gemini_key},
      options
    )

    provision(
      :platform,
      "deepgram",
      "live-telephony",
      "api_key",
      %{"api_key" => settings.deepgram_key},
      options
    )

    # Only the speech-to-speech case needs OpenAI; other live cases run without its key.
    case Map.get(settings, :openai_key) do
      nil ->
        :ok

      openai_key ->
        provision(
          :platform,
          "openai",
          "live-telephony",
          "api_key",
          %{"api_key" => openai_key},
          options
        )
    end

    assert {:ok, _telnyx} =
             OperatorTelephonyApplications.create(
               InstallationOperator.authority(),
               tenant.key,
               %{
                 "name" => "live-telnyx",
                 "provider_connection_id" => settings.application_id,
                 "outbound_number" => Map.fetch!(settings.numbers, "telnyx")
               },
               options
             )

    register_twilio(tenant, settings, options)

    %__MODULE__{
      tenant: tenant,
      key: key,
      principal: principal,
      settings: settings,
      options: options
    }
  end

  # Twilio is optional: Telnyx carries every telephony test that is not about Twilio itself.
  defp register_twilio(tenant, %{account_sid: sid, auth_token: token} = settings, options)
       when is_binary(sid) and is_binary(token) and is_map_key(settings.numbers, "twilio") do
    twilio =
      provision(
        tenant.key,
        "twilio",
        "live-telephony",
        "account_sid_auth_token",
        %{"account_sid" => sid, "auth_token" => token},
        options
      )

    assert {:ok, _twilio} =
             TelephonyServices.register(
               tenant.key,
               %{
                 "name" => "live-twilio",
                 "ingress_key" => "vxp-test-twilio",
                 "provider" => "twilio",
                 "provider_connection_id" => sid,
                 "credential_id" => twilio.id,
                 "outbound_number" => Map.fetch!(settings.numbers, "twilio"),
                 "answering_machine_detection" => "disabled"
               },
               options
             )
  end

  defp register_twilio(_tenant, _settings, _options), do: :ok

  def publish(fixture, dialing, receiving, options \\ []) do
    incoming =
      if Keyword.get(options, :answered?, true),
        do: publish_source(fixture, source(fixture, :incoming, receiving, receiving)),
        else: nil

    timeout = Keyword.get(options, :ring_timeout_ms, 15_000)

    outgoing =
      publish_source(
        fixture,
        source(fixture, :outgoing, dialing, receiving, ring_timeout_ms: timeout)
      )

    # The outgoing spec has no fixed number; each call supplies `to`.
    %{outgoing: outgoing, incoming: incoming, to: Map.fetch!(fixture.settings.numbers, receiving)}
  end

  @doc """
  An outgoing call handled by the selected speech-to-speech provider and a carrier-answered incoming
  call. The handler opens with "Alpha." and must answer the callee's "Bravo." with
  "Charlie.", which proves phone audio reached the model and its speech reached the phone.
  """
  def sts_sources(fixture, dialing, receiving, scenario \\ :round_trip, provider \\ "openai") do
    scenario = sts_scenario(scenario)

    outgoing =
      source(fixture, :outgoing, dialing, receiving)
      |> put_in([:participants, "assistant"], %{
        type: "agent",
        prompt: scenario.model_prompt,
        first_message: %{mode: "fixed", text: scenario.model_opening},
        tools: %{},
        transfers: [],
        capabilities: %{speech_to_speech: sts_capability(provider)}
      })

    incoming = source(fixture, :incoming, receiving, receiving) |> put_receiver(scenario)

    %{outgoing: put_limit(outgoing, scenario), incoming: put_limit(incoming, scenario)}
  end

  defp put_limit(source, %{max_duration_ms: limit}),
    do: put_in(source.limits.max_duration_ms, limit)

  defp put_limit(source, _scenario), do: source

  defp put_receiver(source, %{receiver_prompt: prompt}) do
    put_in(source, [:participants, "assistant"], %{
      type: "agent",
      prompt: prompt,
      first_message: %{mode: "wait_for_input"},
      tools: %{},
      transfers: [],
      capabilities: %{speech_to_speech: gpt_live_capability()}
    })
  end

  defp put_receiver(source, %{receiver_rule: rule} = scenario) do
    source =
      put_in(
        source,
        [:participants, "assistant", :prompt],
        "This is an automated carrier check. #{rule} Never say anything else or ask questions."
      )

    case Map.fetch(scenario, :receiver_first_message) do
      {:ok, opening} -> put_in(source, [:participants, "assistant", :first_message], opening)
      :error -> source
    end
  end

  # Round trip: the model answers the receiver's Bravo with Charlie.
  defp sts_scenario(:round_trip) do
    %{
      model_opening: "Alpha.",
      model_prompt:
        "This is an automated carrier check. You already said Alpha. When the other party " <>
          "says Bravo, reply with exactly: Charlie. Never say anything else or ask questions.",
      receiver_rule: "Whenever the other party speaks, reply with exactly: Bravo."
    }
  end

  # Barge-in: a second GPT-Live answers on the receiving number and talks over the count.
  # A text-agent receiver cannot: its own room interrupts each reply as soon as the next
  # number starts, so nothing reaches the model mid-count. GPT-Live owns its barge-in, so
  # the counter's yield ends its turn `:overlapped`.
  defp sts_scenario(:barge_in) do
    %{
      model_opening: "Alpha.",
      model_prompt:
        "This is an automated carrier check. You already said Alpha. When the other party " <>
          "says ready, count slowly from one to thirty in a single response. Say every " <>
          "number consecutively without waiting for another reply. Continue after each " <>
          "number. If the other party asks you to stop while you are counting, stop " <>
          "counting immediately and say " <>
          "only: I have stopped. Never say anything else or ask questions.",
      receiver_prompt:
        "This is an automated carrier check. When the other party says Alpha, reply with " <>
          "exactly: Ready. They will then count. As soon as you hear them say three, " <>
          "interrupt at once without waiting for a pause and say: Stop counting now, please " <>
          "stop counting. After that, say nothing else."
    }
  end

  # Long session: the two parties trade Ping and Pong for the whole call, so the provider
  # session stays busy until the test's duration elapses.
  defp sts_scenario({:long_session, duration_ms}) do
    %{
      model_opening: "Ping.",
      model_prompt:
        "This is an automated line test that lasts many minutes. You already said Ping. " <>
          "Every time the other party says Pong, reply with exactly: Ping. Never stop, never " <>
          "say anything else and never ask questions.",
      receiver_rule: "Every time the other party says Ping, reply with exactly: Pong.",
      receiver_first_message: %{mode: "wait_for_input"},
      max_duration_ms: duration_ms + 180_000
    }
  end

  defp sts_capability("google") do
    %{
      provider: "google",
      model: LiveModels.speech("google", :sts),
      credential_name: "live-telephony",
      options: %{voice: "Kore", turn_control: "provider"}
    }
  end

  defp sts_capability("openai"), do: gpt_live_capability()

  defp gpt_live_capability do
    %{
      provider: "openai",
      model: LiveModels.speech("openai", :sts),
      credential_name: "live-telephony",
      # The same delegated backend as the passing direct GPT-Live harness.
      options: %{backend_model: LiveModels.speech("openai", :backend)}
    }
  end

  def publish_sts(fixture, dialing, receiving, scenario \\ :round_trip, provider \\ "openai") do
    sources = sts_sources(fixture, dialing, receiving, scenario, provider)

    %{
      outgoing: publish_source(fixture, sources.outgoing),
      incoming: publish_source(fixture, sources.incoming),
      to: Map.fetch!(fixture.settings.numbers, receiving)
    }
  end

  def transfer_sources(fixture) do
    # The transfer caller keeps a fixed number; the paired cases exercise the request's `to`.
    caller = source(fixture, :outgoing, "telnyx", "twilio", fixed_number?: true)
    reception = source(fixture, :incoming, "twilio", "twilio")
    destination = source(fixture, :incoming, "telnyx", "telnyx")
    caller_human = Map.fetch!(reception.participants, "human")
    assistant = Map.fetch!(reception.participants, "assistant")

    assistant = %{
      assistant
      | first_message: %{mode: "fixed", text: "Charlie."},
        prompt:
          "This is an automated private transfer check. When the caller speaks, invoke " <>
            "transfer exactly once with destination support and reason Delta. " <>
            "Say nothing else. Never supply a phone number.",
        transfers: ["support"]
    }

    support = %{
      type: "human",
      description: "The controlled carrier test destination",
      connection: %{
        service: "live-twilio",
        mode: "dial",
        number: Map.fetch!(fixture.settings.numbers, "telnyx")
      },
      transfer_notice: "Private destination check. The transfer code is Delta.",
      capabilities: caller_human.capabilities
    }

    reception =
      reception
      |> Map.put(:participants, %{
        "human" => caller_human,
        "assistant" => assistant,
        "support" => support
      })
      |> Map.put(:transfer_policy, %{attempt_timeout_ms: 30_000})

    Map.new(%{caller: caller, reception: reception, destination: destination}, fn {key, spec} ->
      spec =
        put_in(spec, [:participants, "assistant", :capabilities, :model_inference], %{
          provider: "fixture",
          model: "test:telephony-#{key}"
        })

      {key, %{spec | limits: %{max_duration_ms: 90_000}}}
    end)
  end

  def publish_transfer(fixture, publisher \\ &publish_source/2) do
    Map.new(transfer_sources(fixture), fn {role, source} ->
      {role, publisher.(fixture, source)}
    end)
  end

  def endpoint_options(fixture, adapters \\ %{}) do
    archive = [
      enabled: true,
      writer: {EctoStorage, fixture.options},
      maximum_pending_facts: 256,
      retry_delay_ms: 250,
      drain_timeout_ms: 5_000,
      source_policy: %{"revision" => 0, "save_transcripts" => true}
    ]

    runtime =
      fixture.options
      |> Keyword.put(:archive, archive)
      |> Keyword.put(:credential_source, {ProviderCredentialSource, fixture.options})

    [
      call_admission: [enabled: true, backend: {CallAdmission, runtime}],
      telephony: [
        adapters: adapters,
        enabled: true,
        public_base_url: fixture.settings.public_url,
        provider_credential_repository:
          Keyword.fetch!(fixture.options, :provider_credential_repository),
        telephony_service_repository:
          Keyword.fetch!(fixture.options, :telephony_service_repository),
        handler: {CallIngress, [backend: {CallAdmission, runtime}]}
      ]
    ]
  end

  def engine_settings(original, tts_override \\ []) do
    original
    |> Keyword.update!(:agent_runtime, &Keyword.delete(&1, :fixture))
    |> Keyword.put(:speech_to_text,
      providers: %{
        Vxpipe.Providers.Deepgram.STTSession => [
          enabled: true,
          media_ingress: [
            maximum_frames: 100,
            maximum_bytes: 262_144,
            maximum_age_ms: 2_000,
            maximum_consecutive_overflows: 5
          ]
        ]
      }
    )
    |> Keyword.put(:text_to_speech,
      providers: %{
        Vxpipe.Providers.Deepgram.TTSSession =>
          Keyword.merge([enabled: true, maximum_requests: 4], tts_override)
      }
    )
  end

  defp provision(owner, provider, name, kind, payload, options) do
    assert {:ok, credential} =
             ProviderCredentials.provision(owner, provider, name, kind, payload, options)

    credential
  end

  defp publish_source(fixture, source) do
    assert {:ok, draft} = Calls.save_call_spec(fixture.tenant.key, source, fixture.options)
    assert draft.validation_errors == []

    assert {:ok, publication} =
             Calls.publish_call_spec(
               fixture.tenant.key,
               draft.call_spec_id,
               draft.revision,
               fixture.options
             )

    publication
  end

  # Endpoints name a number; both Telnyx numbers belong to the one Telnyx service.
  defp endpoint_service("telnyx-b"), do: "telnyx"
  defp endpoint_service(endpoint), do: endpoint

  defp source(fixture, direction, service, destination, options \\ []) do
    timeout = Keyword.get(options, :ring_timeout_ms, 15_000)

    human_connection = %{
      service: "live-" <> endpoint_service(service),
      number: Map.fetch!(fixture.settings.numbers, destination)
    }

    human_connection =
      case direction do
        :incoming ->
          Map.merge(human_connection, %{mode: "receive", admission: "start_call"})

        :outgoing ->
          human_connection =
            if Keyword.get(options, :fixed_number?, false),
              do: human_connection,
              else: Map.delete(human_connection, :number)

          Map.put(human_connection, :mode, "dial")
      end

    phrase =
      if direction == :outgoing,
        do: "Alpha.",
        else: "Bravo."

    source = %{
      schema_version: "20261004.01",
      name: "Live #{service} #{direction}",
      defaults: %{capabilities: %{}},
      wait_sounds: nil,
      media_policy: %{save_transcripts: true, record_audio: false},
      limits: %{max_duration_ms: 45_000},
      participants: %{
        "human" => %{
          type: "human",
          connection: human_connection,
          capabilities: %{
            speech_to_text: %{
              provider: "deepgram",
              model: LiveModels.speech("deepgram", :stt),
              credential_name: "live-telephony",
              options: %{encoding: "linear16", sample_rate: 16_000}
            }
          }
        },
        "assistant" => %{
          type: "agent",
          prompt:
            "This is an automated carrier check. Whenever the other party speaks, reply with exactly: #{phrase} Never say anything else or ask questions.",
          first_message: %{mode: "fixed", text: phrase},
          tools: %{},
          transfers: [],
          capabilities: %{
            model_inference: %{
              provider: "google",
              model: "gemini-3.5-flash-lite",
              credential_name: "live-telephony",
              options: %{max_tokens: 64}
            },
            text_to_speech: %{
              provider: "deepgram",
              model: LiveModels.speech("deepgram", :tts),
              credential_name: "live-telephony",
              options: %{encoding: "linear16", sample_rate: 48_000}
            }
          }
        }
      }
    }

    case direction do
      :incoming ->
        Map.put(source, :incoming_call, %{caller: "human", handled_by: "assistant"})

      :outgoing ->
        Map.put(source, :outgoing_call, %{
          callee: "human",
          handled_by: "assistant",
          ring_timeout_ms: timeout
        })
    end
  end
end
