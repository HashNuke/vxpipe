defmodule Vxpipe.CallEngine.Speech.Session do
  @moduledoc """
  Speech allocations inside an explicitly owned `Speech.CapabilityTree` scope.
  `start/2` reserves one of two local slots and returns `{:ok, allocation, :starting}`.
  Wait for and acknowledge the allocation's ready event before submitting input.
  Prepared allocations use a lease authority and `consumer: nil`; `adopt/2` changes
  delivery authority while retaining their original supervised parent.
  """

  alias Vxpipe.CallEngine.Speech.{
    Allocation,
    Cancellation,
    Channel,
    OutputTurn,
    ProviderName,
    Request,
    Scope,
    ScopeControl,
    SessionTree,
    STSInput
  }

  @timeout 5_000
  @maximum_audio_bytes 131_072

  def start(%Scope{} = scope, options) do
    budget = Keyword.get(options, :start_timeout, @timeout)
    timeout = Keyword.get(options, :call_timeout, @timeout)

    if is_integer(budget) and budget > 0 and is_integer(timeout) and timeout in 1..@timeout and
         valid_roles?(options) and valid_usage?(options) do
      reserve(scope, options, budget, timeout)
    else
      {:error, :invalid_configuration}
    end
  end

  defp valid_roles?(options) do
    owner = Keyword.get(options, :owner, self())
    consumer = Keyword.get(options, :consumer, owner)
    lease = Keyword.get(options, :lease)

    is_pid(owner) and
      ((is_pid(consumer) and is_nil(lease)) or (is_nil(consumer) and is_pid(lease)))
  end

  defp valid_usage?(options), do: Keyword.get(options, :usage, false) in [true, false]

  defp reserve(scope, options, budget, timeout) do
    owner = Keyword.get(options, :owner, self())

    allocation = %Allocation{
      scope: scope,
      generation: make_ref(),
      owner: owner,
      consumer: Keyword.get(options, :consumer, owner),
      lease: Keyword.get(options, :lease),
      deadline: System.monotonic_time(:millisecond) + budget,
      token: :atomics.new(1, []),
      call_timeout: timeout
    }

    try do
      case ScopeControl.reserve(
             allocation,
             options,
             min(remaining(allocation.deadline), @timeout)
           ) do
        {:ok, _, :starting} = result ->
          result

        error ->
          Allocation.cancel(allocation)
          error
      end
    catch
      :exit, _reason ->
        Allocation.cancel(allocation)
        {:error, :unavailable}
    end
  end

  def describe(allocation) do
    with {:ok, metadata} <- metadata(allocation), do: {:ok, metadata.descriptor}
  end

  def adopt(allocation, consumer),
    do: adopt(allocation, consumer, System.monotonic_time(:millisecond) + allocation.call_timeout)

  def adopt(allocation, consumer, deadline) when is_integer(deadline) do
    command = command(allocation, min(deadline, operation_deadline(allocation)))

    try do
      result = request(allocation, {:adopt, consumer, command}, command.deadline)

      if result == :ok and remaining(command.deadline) == 0,
        do: adoption_timeout(allocation, command),
        else: result
    catch
      :exit, {:timeout, _call} -> adoption_timeout(allocation, command)
      :exit, _reason -> {:error, :closed}
    end
  end

  def ack(allocation, event), do: call(allocation, {:ack, event})

  @doc """
  Release completed TTS or STS output after the consumer confirms local playout.
  TTS settlement also waits for its outstanding speak callback to be accepted,
  within the original command deadline, before making the next phrase admissible.
  """
  def settle_output(allocation, %Request{session: allocation, ref: reference}, played_ms)
      when is_integer(played_ms) and played_ms >= 0,
      do: call(allocation, {:settle_output, reference, played_ms})

  def settle_output(allocation, %OutputTurn{session: allocation} = handle, played_ms)
      when is_integer(played_ms) and played_ms >= 0,
      do: call(allocation, {:settle_sts_output, handle, played_ms})

  def settle_output(_allocation, _request, _played_ms), do: {:error, :stale_request}

  @doc """
  Authorize one STS output generation after the consumer's policy checks.
  The provider receives `{:vxpipe_speech_output, channel, turn_ref, output_ref}`
  and submits credited audio using that fresh output reference. The slot remains
  occupied until `:output_completed` is acknowledged and `settle_output/3`
  confirms bounded local egress; provider completion alone does not release it.
  """
  def admit_output(allocation, turn_ref) when is_reference(turn_ref) do
    command = command(allocation)

    try do
      result = request(allocation, {:admit_output, command, turn_ref}, command.deadline)

      if match?({:ok, %OutputTurn{}}, result) and remaining(command.deadline) == 0,
        do: input_timeout(allocation, command),
        else: result
    catch
      :exit, {:timeout, _call} -> input_timeout(allocation, command)
      :exit, _reason -> {:error, :closed}
    end
  end

  def admit_output(_allocation, _turn_ref), do: {:error, :invalid_turn}

  @doc "Reject one acknowledged, not-yet-granted opted-in STS response."
  def reject_response(allocation, turn_ref) when is_reference(turn_ref),
    do: call(allocation, {:reject_response, turn_ref})

  def reject_response(_allocation, _turn_ref), do: {:error, :invalid_turn}

  @doc "Engine-authorized retirement of accepted response contexts."
  def retire_response_contexts(allocation, contexts) when is_list(contexts),
    do: call(allocation, {:retire_response_contexts, contexts})

  def retire_response_contexts(_allocation, _contexts), do: :ok

  @doc """
  Admit bounded text and return a request handle before provider acceptance.
  Actual submission arrives as `input_submitted`; clean provider rejection is a
  correlated `failed` event. Synchronous errors mean engine admission failed.
  """
  def speak(allocation, text) when is_binary(text) and byte_size(text) in 1..4_096 do
    command = command(allocation)
    reference = make_ref()

    try do
      result = request(allocation, {:speak, command, reference, text}, command.deadline)

      if match?({:ok, %Request{}}, result) and remaining(command.deadline) == 0,
        do: input_timeout(allocation, command),
        else: result
    catch
      :exit, {:timeout, _call} -> input_timeout(allocation, command)
      :exit, _reason -> {:error, :closed}
    end
  end

  def speak(_allocation, _text), do: {:error, :invalid_text}

  @doc "Fence exact request audio before interrupting the sink; the returned deadline is fixed."
  def fence_output(allocation, %Request{session: allocation, ref: reference}),
    do: fence_output(allocation, reference)

  def fence_output(allocation, reference) do
    command = command(allocation)

    try do
      result = request(allocation, {:fence_output, command, reference}, command.deadline)

      if match?({:ok, %Cancellation{}}, result) and remaining(command.deadline) == 0,
        do: input_timeout(allocation, command),
        else: result
    catch
      :exit, {:timeout, _call} -> input_timeout(allocation, command)
      :exit, _reason -> {:error, :closed}
    end
  end

  @doc """
  Complete a fence after sink interruption with actual request-relative played ms.
  The original fence deadline bounds mutations. A retained successful result may
  be read again under a fresh bounded call, without changing playback or a replacement.
  """
  def cancel(allocation, %Cancellation{} = ticket, played_ms) do
    command = command(allocation)

    try do
      request(allocation, {:cancel, command, ticket, played_ms}, command.deadline)
    catch
      :exit, {:timeout, _call} -> input_timeout(allocation, command)
      :exit, _reason -> {:error, :closed}
    end
  end

  def cancel(_allocation, _ticket, _played_ms), do: {:error, :stale_cancellation}

  @doc "Start cancellation without blocking the consumer that must acknowledge terminal events."
  def request_cancel(allocation, %Cancellation{} = ticket, played_ms) do
    command = command(allocation)

    if Allocation.valid?(allocation) do
      request_id =
        :gen.send_request(
          Channel.address(allocation),
          :"$gen_call",
          {:command, allocation, command.deadline, {:cancel, command, ticket, played_ms}}
        )

      {:ok, request_id}
    else
      {:error, :closed}
    end
  catch
    :exit, _reason -> {:error, :closed}
  end

  def request_cancel(_allocation, _ticket, _played_ms),
    do: {:error, :stale_cancellation}

  @doc false
  def cancellation_response(message, request_id),
    do: :gen.check_response(message, request_id)

  @doc "Check the exact current audio envelope before sink use."
  def validate_audio(allocation, audio), do: audio_call(allocation, :validate, audio)
  @doc "Release PCM credit after bounded sink acceptance; this does not report playback."
  def ack_audio(allocation, audio), do: audio_call(allocation, :ack, audio)

  defp audio_call(allocation, operation, audio) do
    deadline = System.monotonic_time(:millisecond) + allocation.call_timeout

    if Allocation.valid?(allocation),
      do:
        GenServer.call(
          Channel.address(allocation),
          {:audio, deadline, operation, audio},
          remaining(deadline)
        ),
      else: {:error, :closed}
  catch
    :exit, {:timeout, _call} -> {:error, :command_timeout}
    :exit, _reason -> {:error, :closed}
  end

  @doc """
  Submit 1..131072 bytes with one outstanding command per allocation. `:ok` means
  bounded provider acceptance, not recognition completion. `{:error, :busy}`
  means no acceptance; this function never retries. The command budget measures
  age from API entry, including queue waits. Raw bytes carry no capture timestamp;
  upstream ingress retains responsibility for captured-frame age limits.

  Opted-in STS descriptors require `response_context: reference`, issued by the
  consumer's engine policy owner. It is delivered atomically with input; provider
  acceptance does not authorize output. Options are closed, and non-opted-in
  allocations reject supplied contexts instead of silently discarding them.
  """
  def push_audio(allocation, audio, options \\ [])

  def push_audio(allocation, audio, options)
      when is_binary(audio) and byte_size(audio) in 1..@maximum_audio_bytes do
    with {:ok, command} <- input_command(allocation, options),
         do: submit_input(allocation, command, audio)
  end

  def push_audio(_allocation, audio, _options) when is_binary(audio),
    do: {:error, :invalid_audio_size}

  def push_audio(_allocation, _audio, _options), do: {:error, :invalid_audio}

  @doc """
  Admit bounded explicit text for an STS allocation through the same ordered
  input slot as audio. `:ok` means bounded provider acceptance; the provider
  publishes `:input_submitted` with the returned text reference. STT and TTS
  allocations reject text with `:unsupported_operation`.
  The same closed `response_context` option and acceptance rules as audio apply.
  """
  def push_text(allocation, text, options \\ [])

  def push_text(allocation, text, options) when is_binary(text) and byte_size(text) in 1..4_096 do
    with {:ok, command} <- input_command(allocation, options) do
      command = Map.put(command, :operation, {:push_text, make_ref(), text})
      submit_input(allocation, command, text)
    end
  end

  def push_text(_allocation, _text, _options), do: {:error, :invalid_text}

  @doc """
  Deliver an ordered external turn-control boundary to an STS allocation
  through the same input slot as audio and text. Unavailable in
  provider-controlled turn mode (`:unsupported_operation`).
  The same closed `response_context` option and acceptance rules as audio apply.
  """
  def input_activity(allocation, boundary, options \\ [])

  def input_activity(allocation, boundary, options) when boundary in [:started, :ended] do
    with {:ok, command} <- input_command(allocation, options) do
      command = Map.put(command, :operation, {:input_activity, boundary})
      submit_input(allocation, command, <<>>)
    end
  end

  def input_activity(_allocation, _boundary, _options), do: {:error, :invalid_activity}

  defp input_command(allocation, options) do
    with {:ok, context} <- STSInput.context_options(options),
         do: {:ok, Map.merge(command(allocation), context)}
  end

  defp submit_input(allocation, command, payload) do
    try do
      if Allocation.valid?(allocation) do
        GenServer.call(
          Channel.address(allocation),
          {:input, allocation, command, payload},
          remaining(command.deadline)
        )
      else
        {:error, :closed}
      end
    catch
      :exit, {:timeout, _call} ->
        input_timeout(allocation, command)

      :exit, _reason ->
        if(Allocation.valid?(allocation), do: {:error, :session_failed}, else: {:error, :closed})
    end
  end

  def close(allocation) do
    deadline = System.monotonic_time(:millisecond) + allocation.call_timeout

    case ScopeControl.close(allocation, :closed, deadline) do
      {:ok, tree} -> await_closed(tree, deadline)
      error -> error
    end
  catch
    :exit, {:timeout, _call} -> {:error, :close_timeout}
    :exit, _reason -> if(tree(allocation), do: {:error, :unavailable}, else: :ok)
  end

  @doc false
  def retire(allocation, deadline) when is_integer(deadline) do
    case ScopeControl.close(allocation, :closed, deadline) do
      {:ok, _tree} -> :ok
      error -> error
    end
  catch
    :exit, {:timeout, _call} -> {:error, :close_timeout}
    :exit, _reason -> if(tree(allocation), do: {:error, :unavailable}, else: :ok)
  end

  defp await_closed(nil, _deadline), do: :ok

  defp await_closed(tree, deadline) do
    monitor = Process.monitor(tree)

    try do
      receive do
        {:DOWN, ^monitor, :process, ^tree, _reason} -> :ok
      after
        remaining(deadline) -> {:error, :close_timeout}
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  @doc false
  def tree(allocation), do: GenServer.whereis(SessionTree.address(allocation))
  @doc false
  def provider(allocation) do
    case ProviderName.whereis_name(allocation) do
      :undefined -> nil
      pid -> pid
    end
  end

  @doc false
  def input_quiescent?(allocation) do
    with {:ok, %{producer: producer, module: module, descriptor: %{kind: :sts}}} <-
           metadata(allocation),
         true <- is_pid(producer) and function_exported?(module, :input_quiescent?, 1),
         true <- provider_input_quiescent?(module, producer),
         true <- call(allocation, :input_evidence_idle?) do
      true
    else
      _unproven -> false
    end
  end

  @doc "Keep an STS session alive while muting or resuming its caller input."
  def set_input_hold(allocation, held?) when is_boolean(held?),
    do: call(allocation, {:set_input_hold, held?})

  def set_input_hold(_allocation, _held?), do: {:error, :invalid_hold}

  @doc "Append published caller or agent text to an STS provider's reseed history."
  def append_history(allocation, {role, text} = entry)
      when role in [:caller, :agent] and is_binary(text) and byte_size(text) > 0,
      do: call(allocation, {:append_history, entry})

  def append_history(_allocation, _entry), do: {:error, :invalid_history}

  defp provider_input_quiescent?(module, provider) do
    apply(module, :input_quiescent?, [provider]) == true
  catch
    _, _ -> false
  end

  defp metadata(allocation), do: call(allocation, :metadata)

  defp call(allocation, message) do
    deadline = System.monotonic_time(:millisecond) + allocation.call_timeout

    request(allocation, message, deadline)
  catch
    :exit, {:timeout, _call} -> {:error, :command_timeout}
    :exit, _reason -> {:error, :closed}
  end

  defp request(allocation, message, deadline) do
    if Allocation.valid?(allocation),
      do:
        GenServer.call(
          Channel.address(allocation),
          {:command, allocation, deadline, message},
          remaining(deadline)
        ),
      else: {:error, :closed}
  end

  defp command(allocation) do
    command(allocation, operation_deadline(allocation))
  end

  defp command(_allocation, deadline) do
    %{
      ref: make_ref(),
      deadline: deadline,
      token: :atomics.new(1, [])
    }
  end

  defp operation_deadline(allocation),
    do: System.monotonic_time(:millisecond) + allocation.call_timeout

  defp adoption_timeout(allocation, command) do
    if :atomics.compare_exchange(command.token, 1, 0, 2) == 1, do: retire(allocation)
    {:error, :command_timeout}
  end

  defp input_timeout(allocation, command) do
    # Only the Channel can admit this fresh ticket after checking current authority.
    # Cancelling a queued command must not revoke an otherwise usable allocation.
    case :atomics.compare_exchange(command.token, 1, 0, 2) do
      :ok ->
        {:error, :command_timeout}

      1 ->
        retire(allocation)
        {:error, :session_failed}
    end
  end

  defp retire(allocation) do
    Allocation.cancel(allocation)
    ScopeControl.failed(allocation, :session_failed)
    if pid = provider(allocation), do: Process.exit(pid, :kill)
    if pid = GenServer.whereis(Channel.address(allocation)), do: Process.exit(pid, :kill)
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
