defmodule Vxpipe.CallEngine.CreateRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Room.Snapshot

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "model calls require an inline plan instead of the retired global agent selector" do
    assert {:error, %Error{code: :invalid_command, details: %{"field" => "agent"}}} =
             CreateRoom.new(
               tenant_id: "tenant-raw",
               actor_id: "actor-raw",
               agent: :model_inference,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )
  end

  test "a deterministic raw room cannot start configured speech without an inline plan" do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(settings, :text_to_speech,
        providers: %{
          Vxpipe.Providers.Deepgram.FluxTextToSpeech.Session => [
            enabled: true,
            wire_module: Vxpipe.CallEngine.TestTextToSpeechTransport,
            wire_options: [observer: self()],
            maximum_requests: 2
          ]
        }
      )
    )

    assert {:ok, command} =
             CreateRoom.new(
               tenant_id: "tenant-raw",
               actor_id: "actor-raw",
               agent: :deterministic_text,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _room} = CallEngine.create_room(command)
    refute_receive {:test_tts_transport_started, _, _}
  end

  test "a stale model command cannot bypass inline plan admission" do
    assert {:ok, command} =
             CreateRoom.new(
               tenant_id: "tenant-raw",
               actor_id: "actor-raw",
               agent: :deterministic_text,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:error, %Error{code: :room_start_failed}} =
             CallEngine.create_room(%{command | agent: :model_inference})
  end

  test "a raw connection cannot start configured recognition without an inline plan" do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(settings, :speech_to_text,
        providers: %{
          Vxpipe.Providers.Deepgram.Flux.Session => [
            enabled: true,
            wire_module: Vxpipe.CallEngine.TestSpeechToTextTransport,
            wire_options: [observer: self()],
            media_ingress: [
              maximum_frames: 50,
              maximum_bytes: 65_536,
              maximum_age_ms: 1_000,
              maximum_consecutive_overflows: 10
            ]
          ]
        }
      )
    )

    assert {:ok, command} =
             CreateRoom.new(
               tenant_id: "tenant-raw",
               actor_id: "actor-raw",
               agent: :deterministic_text,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, room} = CallEngine.create_room(command)

    assert {:ok, join} =
             Vxpipe.CallEngine.Command.JoinParticipant.new(
               tenant_id: room.tenant_id,
               actor_id: "actor-raw",
               room_id: room.room_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, participant} = CallEngine.join_participant(join)

    assert {:ok, attach} =
             Vxpipe.CallEngine.Command.AttachConnection.new(
               tenant_id: room.tenant_id,
               actor_id: "actor-raw",
               room_id: room.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "raw-connection",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, attachment} = CallEngine.attach_connection(attach)
    assert attachment.media_ingress == nil
    refute_receive {:test_stt_transport_started, _, _}
  end

  test "creates one supervised room incarnation and returns its public snapshot" do
    room_id = unique_room_id()

    assert {:ok, command} =
             CreateRoom.new(
               id: "cmd-create-room",
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, snapshot} = CallEngine.create_room(command)

    assert Snapshot.to_public(snapshot) == %{
             "created_by_actor_id" => "actor-demo",
             "created_by_command_id" => "cmd-create-room",
             "incarnation_id" => snapshot.incarnation_id,
             "lifecycle" => "open",
             "room_id" => room_id,
             "tenant_id" => "tenant-demo"
           }

    assert String.starts_with?(snapshot.incarnation_id, "rinc_")

    assert {:error, %Error{code: :room_already_exists, retryable: false}} =
             CallEngine.create_room(command)
  end

  test "rejects a command whose deadline has elapsed" do
    assert {:ok, command} =
             CreateRoom.new(
               id: "cmd-expired",
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: unique_room_id(),
               deadline: DateTime.add(DateTime.utc_now(), -1, :second)
             )

    assert {:error, %Error{code: :deadline_exceeded, retryable: false}} =
             CallEngine.create_room(command)
  end

  test "ends the room incarnation when its authority terminates" do
    existing_incarnations = incarnation_pids()
    room_id = unique_room_id()

    assert {:ok, command} =
             CreateRoom.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _snapshot} = CallEngine.create_room(command)

    assert [incarnation] = incarnation_pids() -- existing_incarnations

    assert [{authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {"tenant-demo", room_id})

    authority_monitor = Process.monitor(authority)
    incarnation_monitor = Process.monitor(incarnation)
    Process.exit(authority, :kill)

    assert_receive {:DOWN, ^authority_monitor, :process, ^authority, :killed}
    assert_receive {:DOWN, ^incarnation_monitor, :process, ^incarnation, :shutdown}
  end

  defp unique_room_id do
    "room-test-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp incarnation_pids do
    for {_id, pid, :supervisor, _modules} <-
          DynamicSupervisor.which_children(Vxpipe.CallEngine.RoomSupervisor),
        do: pid
  end
end
