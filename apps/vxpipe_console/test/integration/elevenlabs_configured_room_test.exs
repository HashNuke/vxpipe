defmodule Vxpipe.Console.Integration.ElevenLabsConfiguredRoomTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log
  @moduletag timeout: 90_000

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler}
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Event.ParticipantTranscription
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.Calls.{Administration, ProviderCredentials, ProviderCredentialSource}
  alias Vxpipe.Console.Test.{ScribeTransport, SpeechConnection}

  alias Vxpipe.Persistence.{
    CallSpecStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo
  }

  alias Vxpipe.Providers.Deepgram.LiveFixture
  alias Vxpipe.Providers.ElevenLabs.STTSession
  alias Vxpipe.Providers.LiveModels

  setup do
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    %{
      original: original,
      options: [
        credential_repository: {CredentialStore, Repo},
        provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
        call_spec_repository: {CallSpecStore, Repo}
      ]
    }
  end

  test "encrypted platform selection reaches room audio and retires its owned recognizer",
       context do
    configure(context.original, wire_module: ScribeTransport, wire_options: [observer: self()])
    {plan, room} = published_room(context.options, "synthetic-configured-scribe")
    caller = attach(plan, room, plan.entry_caller)
    assert_receive {:configured_scribe_started, wire}, 5_000
    monitor = Process.monitor(wire)
    receiver = attach(plan, room, plan.entry_receiver)
    await_ready(caller, receiver)

    events = stream(caller, File.read!(LiveFixture.pcm_path()), [], 0)
    events = await_final(events, System.monotonic_time(:millisecond) + 5_000)

    assert [
             %ParticipantTranscription{
               final: true,
               provider_turn_index: 0,
               text: "Public telescope."
             }
           ] = finals(events)

    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 5_000
    retire_room(caller, receiver)
  end

  @tag :live_providers
  @tag :live_elevenlabs
  test "configured Scribe room preserves one long acoustic turn across manual segments",
       context do
    configure(context.original, [])
    # The key is only input to encrypted provisioning. Room startup resolves it
    # through the normal production credential source; no adapter is called here.
    {plan, room} = published_room(context.options, System.fetch_env!("ELEVENLABS_API_KEY"))
    caller = attach(plan, room, plan.entry_caller)
    receiver = attach(plan, room, plan.entry_receiver)
    await_ready(caller, receiver)

    audio = long_audio()
    prefix_size = 21 * 32_000
    <<prefix::binary-size(prefix_size), tail::binary>> = audio
    events = stream(caller, prefix, [], 0)
    assert finals(events) == [], "recognizer segmentation ended the caller turn early"
    events = stream(caller, tail, events, prefix_size)
    events = await_final(events, System.monotonic_time(:millisecond) + 15_000)
    assert [ended] = finals(events)
    assert ended.provider_turn_index == 0
    assert ended.participant_id == Map.fetch!(plan.participants, plan.entry_caller).participant_id
    assert String.downcase(ended.text) =~ "telescope", "long room turn lost its earlier segment"
    assert Regex.match?(~r/\byes\b/i, ended.text), "long room turn lost its final segment"

    assert Enum.any?(events, fn event ->
             not event.final and event.provider_turn_index == 0 and
               String.downcase(event.text) =~ "telescope"
           end),
           "long room turn did not publish intermediate recognition"

    retire_room(caller, receiver)

    IO.puts(
      "Configured Scribe: encrypted platform service; 24.2 seconds input; one final room turn with prefix and suffix; room retired"
    )
  end

  defp configure(original, wire_options) do
    settings =
      [
        enabled: true,
        media_ingress: [
          maximum_frames: 50,
          maximum_bytes: 262_144,
          maximum_age_ms: 2_000,
          maximum_consecutive_overflows: 5
        ]
      ] ++ wire_options

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :speech_to_text, providers: %{STTSession => settings})
    )
  end

  defp published_room(options, key) do
    assert {:ok, tenant, _} =
             Administration.bootstrap_tenant("Configured Scribe", [:admin], options)

    assert {:ok, service} =
             ProviderCredentials.provision(
               :platform,
               "elevenlabs",
               "configured-scribe",
               "api_key",
               %{"api_key" => key},
               options
             )

    assert {:ok, resolved} =
             ProviderCredentialSource.resolve(
               options,
               tenant.key,
               "elevenlabs",
               "configured-scribe"
             )

    assert resolved.owner == :platform and resolved.id == service.id and
             resolved.version == service.version

    assert {:ok, draft} = Vxpipe.Calls.save_call_spec(tenant.key, source(), options)
    assert draft.validation_errors == []

    assert {:ok, publication} =
             Vxpipe.Calls.publish_call_spec(
               tenant.key,
               draft.call_spec_id,
               draft.revision,
               options
             )

    publication_private? = not String.contains?(:erlang.term_to_binary(publication), key)
    assert publication_private?, "publication exposed a credential"

    assert {:ok, spec} =
             CallSpec.new(publication.source,
               resource_id: publication.call_spec_id,
               revision: publication.revision
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: publication.call_spec_id, revision: publication.revision},
                 transport: %{type: "web"}
               },
               tenant_id: tenant.key,
               actor_id: "configured-scribe-test"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})

    assert {:ok, room} =
             CallEngine.start_call(plan, credential_source: {ProviderCredentialSource, options})

    {plan, room}
  end

  defp source do
    human = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"},
      capabilities: %{}
    }

    caller =
      Map.put(human, :capabilities, %{
        speech_to_text: %{
          provider: "elevenlabs",
          model: LiveModels.speech("elevenlabs", :stt),
          credential_name: "configured-scribe",
          options: %{language_code: "en"}
        }
      })

    %{
      schema_version: "20260915.01",
      name: "Configured Scribe room",
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      wait_sounds: nil,
      media_policy: %{save_transcripts: true},
      call_variables: %{sections: %{}},
      participants: %{"caller" => caller, "receiver" => human},
      limits: %{max_duration_ms: 60_000}
    }
  end

  defp attach(plan, room, participant_id) do
    participant = Map.fetch!(plan.participants, participant_id)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "configured-#{participant_id}",
               deadline: DateTime.add(DateTime.utc_now(), 20, :second)
             )

    connection =
      start_supervised!({SpeechConnection, command: command, observer: self()},
        id: participant_id
      )

    assert {:ok, attachment} = SpeechConnection.attach(connection)

    on_exit(fn ->
      stop_room(attachment.room_authority)
    end)

    %{
      command: command,
      connection: connection,
      attachment: attachment,
      supervisor_id: participant_id
    }
  end

  defp await_ready(caller, receiver) do
    for connection <- [caller.connection, receiver.connection] do
      assert_receive {:configured_speech_ready, ^connection}, 20_000
    end
  end

  defp long_audio do
    fixture = File.read!(LiveFixture.pcm_path())
    size = byte_size(fixture) - 64_000
    <<phrase::binary-size(size), tail::binary>> = fixture
    assert tail == :binary.copy(<<0>>, 64_000)
    audio = :binary.copy(phrase, 10) <> File.read!(LiveFixture.short_pcm_path()) <> tail
    assert byte_size(audio) in (21 * 32_000)..(25 * 32_000)
    audio
  end

  defp stream(_caller, "", events, _position), do: events

  defp stream(caller, audio, events, position) do
    size = min(byte_size(audio), 3_200)
    <<chunk::binary-size(size), rest::binary>> = audio
    attachment = SpeechConnection.attachment(caller.connection)
    identity = caller.command

    assert :ok =
             CallEngine.push_audio(attachment, %AudioFrame{
               tenant_id: identity.tenant_id,
               room_id: identity.room_id,
               incarnation_id: identity.incarnation_id,
               participant_id: identity.participant_id,
               connection_id: identity.connection_id,
               track_id: "configured-speech",
               codec: :linear16,
               sample_rate: 16_000,
               channels: 1,
               sequence_number: div(position, 3_200),
               timestamp: div(position, 2),
               payload: chunk,
               received_at: System.monotonic_time(:millisecond)
             })

    ref = make_ref()
    Process.send_after(self(), {:configured_pcm_pace, ref}, div(size, 32))
    events = collect(events, {:pace, ref}, System.monotonic_time(:millisecond) + 2_000)
    stream(caller, rest, events, position + size)
  end

  defp await_final(events, deadline) do
    if finals(events) == [], do: collect(events, :final, deadline), else: events
  end

  defp collect(events, target, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "configured room observation exceeded its deadline"

    receive do
      {:configured_pcm_pace, ref} when target == {:pace, ref} ->
        events

      {:vxpipe_event, %ParticipantTranscription{} = event} ->
        events = Enum.uniq_by(events ++ [event], & &1.id)
        if target == :final and event.final, do: events, else: collect(events, target, deadline)

      {:configured_speech_closed, _connection} ->
        flunk("configured room closed before acceptance")
    after
      remaining -> flunk("configured room acknowledgement missing")
    end
  end

  defp finals(events), do: Enum.filter(events, & &1.final)

  defp retire_room(caller, receiver) do
    assert {:ok, monitor} =
             CallEngine.monitor_room(
               caller.command.tenant_id,
               caller.command.room_id,
               caller.command.incarnation_id
             )

    stop_supervised!(receiver.supervisor_id)
    stop_supervised!(caller.supervisor_id)
    stop_room(caller.attachment.room_authority)
    assert_receive {:DOWN, ^monitor, :process, _room, _reason}, 5_000
  end

  defp stop_room(authority) do
    GenServer.stop(authority, :shutdown)
  catch
    :exit, {:noproc, _call} -> :ok
  end
end
