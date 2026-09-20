defmodule Vxpipe.CallEngine.SpeechProviderContract do
  @moduledoc false

  import ExUnit.Assertions

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Descriptor, Event, Session}

  def assert_descriptor(provider, options, kind) do
    assert {:ok, descriptor} = provider.configure(options)
    assert %Descriptor{kind: ^kind} = descriptor
    assert :ok = Descriptor.validate(descriptor)
    :ok
  end

  def start_scope!(owner \\ self()) do
    ExUnit.Callbacks.start_supervised!(
      Supervisor.child_spec({CapabilityTree, owner: owner}, id: make_ref())
    )
    |> CapabilityTree.scope()
  end

  def start_profile!(provider, options \\ []) do
    scope = start_scope!(Keyword.get(options, :owner, self()))
    session = start_session!(scope, provider, options)
    ack_ready!(session)
    session
  end

  def start_session!(scope, provider, options \\ []) do
    session_options =
      options
      |> Keyword.take([:owner, :consumer, :lease, :start_timeout, :call_timeout, :usage])
      |> Keyword.put(:provider, provider)
      |> Keyword.put(:options, Keyword.get(options, :options, []))
      |> Keyword.put(:private, Keyword.get(options, :private, []))

    session_options =
      if Keyword.has_key?(options, :owner) and not Keyword.has_key?(options, :consumer) do
        Keyword.put(session_options, :consumer, self())
      else
        session_options
      end

    assert {:ok, session, :starting} = Session.start(scope, session_options)
    session
  end

  def ack_ready!(session, timeout \\ 1_000) do
    event = receive_event!(session, timeout)
    assert event.kind == :ready
    assert :ok = Session.ack(session, event)
    event
  end

  def ack_event!(session, kind, timeout \\ 1_000) do
    event = receive_event!(session, timeout)
    assert event.kind == kind
    assert :ok = Session.ack(session, event)
    event
  end

  def ack_events!(session, count, timeout \\ 1_000) do
    Enum.map(1..count, fn _index ->
      event = receive_event!(session, timeout)
      assert :ok = Session.ack(session, event)
      event
    end)
  end

  def ack_audio!(session, request_ref, expected, timeout \\ 1_000) do
    audio = next_audio!(session, request_ref, expected, timeout)
    assert :ok = Session.ack_audio(session, audio)
    audio
  end

  def next_audio!(session, request_ref, expected, timeout \\ 1_000) do
    receive do
      {:vxpipe_speech_audio,
       %Audio{session: ^session, request_ref: ^request_ref, payload: ^expected} = audio} ->
        assert :ok = Session.validate_audio(session, audio)
        audio
    after
      timeout -> flunk("speech provider did not publish the expected credited audio")
    end
  end

  def ack_received_audio!(session, %Audio{session: session} = audio) do
    assert :ok = Session.ack_audio(session, audio)
    :ok
  end

  def drain_tts!(session, request_ref, timeout \\ 1_000),
    do: drain_tts(session, request_ref, [], timeout)

  def assert_cancelled_start_never_initializes!(scope, provider, options, initialization_hook)
      when is_function(initialization_hook, 1) do
    :ok = :sys.suspend(scope.sessions)

    try do
      session = start_session!(scope, provider, options)
      assert :ok = Session.close(session)
    after
      :ok = :sys.resume(scope.sessions)
    end

    replacement = start_session!(scope, provider, options)
    ack_ready!(replacement)
    replacement_provider = Session.provider(replacement)
    assert {:ok, ^replacement_provider} = receive_matching(initialization_hook, 500)
    assert :none = receive_matching(initialization_hook, 50)
    assert :ok = Session.close(replacement)
    :ok
  end

  defp drain_tts(session, request_ref, chunks, timeout) do
    receive do
      {:vxpipe_speech_audio, %Audio{session: ^session, request_ref: ^request_ref} = audio} ->
        assert byte_size(audio.payload) > 0
        assert :ok = Session.validate_audio(session, audio)
        assert :ok = Session.ack_audio(session, audio)
        drain_tts(session, request_ref, [audio.payload | chunks], timeout)

      {:vxpipe_speech,
       %Event{session: ^session, request_ref: ^request_ref, kind: :completed} = event} ->
        assert :ok = Session.ack(session, event)
        chunks |> Enum.reverse() |> IO.iodata_to_binary()

      {:vxpipe_speech, %Event{session: ^session, request_ref: ^request_ref} = event} ->
        assert event.kind == :input_submitted
        assert :ok = Session.ack(session, event)
        drain_tts(session, request_ref, chunks, timeout)
    after
      timeout -> flunk("speech provider did not finish its request")
    end
  end

  defp receive_event!(session, timeout) do
    receive do
      {:vxpipe_speech, %Event{session: ^session} = event} -> event
    after
      timeout -> flunk("speech provider did not publish its next semantic event")
    end
  end

  defp receive_matching(hook, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    receive_matching_until(hook, deadline)
  end

  defp receive_matching_until(hook, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      message ->
        case hook.(message) do
          {:ok, _value} = result -> result
          :ignore -> receive_matching_until(hook, deadline)
        end
    after
      remaining -> :none
    end
  end
end
