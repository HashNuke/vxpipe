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

    twilio =
      provision(
        tenant.key,
        "twilio",
        "live-telephony",
        "account_sid_auth_token",
        %{"account_sid" => settings.account_sid, "auth_token" => settings.auth_token},
        options
      )

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

    assert {:ok, _twilio} =
             TelephonyServices.register(
               tenant.key,
               %{
                 "name" => "live-twilio",
                 "ingress_key" => "vxp-test-twilio",
                 "provider" => "twilio",
                 "provider_connection_id" => settings.account_sid,
                 "credential_id" => twilio.id,
                 "outbound_number" => Map.fetch!(settings.numbers, "twilio"),
                 "answering_machine_detection" => "disabled"
               },
               options
             )

    %__MODULE__{
      tenant: tenant,
      key: key,
      principal: principal,
      settings: settings,
      options: options
    }
  end

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

  defp source(fixture, direction, service, destination, options \\ []) do
    timeout = Keyword.get(options, :ring_timeout_ms, 15_000)

    human_connection = %{
      service: "live-" <> service,
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
