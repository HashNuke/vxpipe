defmodule Vxpipe.Console.Test.LocalRecordingStoreTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.Test.LocalRecordingStore

  @tag :tmp_dir
  test "retains playable room audio and timing gaps before the call ends", %{tmp_dir: dir} do
    spec = %{
      call_id: "call-a",
      incarnation_id: "room-a",
      channels: 1,
      sample_rate: 8000,
      object_key: "recordings/room",
      kind: :full_mix
    }

    assert {:ok, session} = LocalRecordingStore.open(spec, directory: dir)

    assert {:ok, session} =
             LocalRecordingStore.write_chunk(
               session,
               %{offset_samples: 300, payload: <<1::little-16>>},
               []
             )

    assert {:ok, session} =
             LocalRecordingStore.write_chunk(
               session,
               %{offset_samples: 302, payload: <<123::little-16>>},
               []
             )

    assert <<"RIFF", 42::little-32, "WAVE", _format::binary-size(24), "data", 6::little-32,
             1::little-16, 0::little-16, 123::little-16>> =
             File.read!(Path.join([dir, "call-a", "room-a", "room.wav"]))

    assert {:ok, %{object_key: "recordings/room"}} =
             LocalRecordingStore.complete(session, %{}, [])
  end
end
