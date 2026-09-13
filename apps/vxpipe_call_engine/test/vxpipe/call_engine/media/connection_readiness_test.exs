defmodule Vxpipe.CallEngine.Media.ConnectionReadinessTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.ConnectionReadiness
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.TestConnectionReadinessAdapter

  setup do
    identity = %{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "participant",
      connection_id: "connection"
    }

    policy = %Snapshot{
      revision: 1,
      present_participant_ids: MapSet.new([identity.participant_id]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: false,
        save_transcripts: false
      }
    }

    %{identity: identity, policy: policy}
  end

  test "queries the exact connection outside its callback and retains resource evidence",
       context do
    connection = connection(context)

    assert {:ok, [%Resource{instance: ^connection} = resource]} =
             ConnectionReadiness.prepare(connection, context.identity, context.policy, [])

    assert_receive {:connection_preparation_started, worker, policy, demand}
    assert worker != connection
    assert policy == context.policy
    assert demand == %{audio_input?: false, room_output?: false, speech_to_text?: false}

    assert {:ok, [^resource]} =
             ConnectionReadiness.prepare(connection, context.identity, policy, [])
  end

  test "rejects foreign identity and malformed demand before invoking a media adapter", context do
    connection = connection(context)
    foreign = %{context.identity | incarnation_id: "other-incarnation"}

    assert {:error, :wrong_connection} =
             ConnectionReadiness.prepare(connection, foreign, context.policy, [])

    assert {:error, :invalid_demand} =
             ConnectionReadiness.prepare(connection, context.identity, context.policy,
               audio_input?: nil
             )

    assert {:error, :invalid_demand} =
             ConnectionReadiness.prepare(connection, context.identity, context.policy,
               microphone: true
             )

    refute_receive {:connection_preparation_started, _, _, _}
  end

  test "returns the prepared connection identity and optional input track with its resources",
       context do
    connection = connection(context)

    assert {:ok, graph} =
             ConnectionReadiness.prepare_graph(connection, context.identity, context.policy, [])

    assert graph.identity == context.identity
    assert graph.instance == connection
    assert is_reference(graph.generation)
    assert graph.input_track == nil
    assert [%Resource{instance: ^connection}] = graph.resources
  end

  test "rejects an unsupported adapter rather than treating an attached process as ready",
       context do
    connection = connection(context, adapter: String)

    assert {:error, :unsupported_adapter} =
             ConnectionReadiness.prepare(connection, context.identity, context.policy, [])
  end

  test "rejects a resource graph from a different participant", context do
    resource = Resource.new(:media_connection, {:participant, "foreign"}, __MODULE__, :foreign)
    connection = connection(context, resource: resource)

    assert {:error, :invalid_resources} =
             ConnectionReadiness.prepare(connection, context.identity, context.policy, [])
  end

  test "discards prepared results if the connection binding changed during preparation",
       context do
    connection = connection(context, block?: true)
    tasks = start_supervised!({Task.Supervisor, name: {:global, {__MODULE__, make_ref()}}})

    request =
      Task.Supervisor.async_nolink(tasks, fn ->
        ConnectionReadiness.prepare(connection, context.identity, context.policy, [])
      end)

    assert_receive {:connection_preparation_started, worker, _, _}, 1_000
    assert :ok = TestConnectionReadinessAdapter.replace(connection)
    send(worker, :continue)
    assert {:error, :connection_changed} = Task.await(request)
  end

  test "bounds preparation and removes a worker that never finishes", context do
    connection = connection(context, block?: true)
    tasks = start_supervised!({Task.Supervisor, name: {:global, {__MODULE__, make_ref()}}})

    request =
      Task.Supervisor.async_nolink(tasks, fn ->
        ConnectionReadiness.prepare(connection, context.identity, context.policy, [], 1_000)
      end)

    assert_receive {:connection_preparation_started, worker, _, _}, 1_000
    monitor = Process.monitor(worker)
    assert {:error, :unavailable} = Task.await(request, 2_000)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}
    assert :ok = TestConnectionReadinessAdapter.replace(connection)
  end

  test "a demanded input cannot silently omit its prepared track", context do
    connection = connection(context)

    assert {:error, :invalid_input_track} =
             ConnectionReadiness.prepare(connection, context.identity, context.policy,
               audio_input?: true
             )
  end

  defp connection(context, options \\ []) do
    start_supervised!(
      {TestConnectionReadinessAdapter,
       Keyword.merge([identity: context.identity, observer: self()], options)}
    )
  end
end
