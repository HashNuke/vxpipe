defmodule Vxpipe.CallEngine.SpeechRequestTTSProfile do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Speech.TTSProvider

  alias Vxpipe.CallEngine.Speech.{
    Channel,
    Descriptor,
    Event,
    Playback,
    SessionTree,
    TTSProvider
  }

  @default_sample_rate 16_000
  @default_chunk_bytes 640
  @default_maximum_response_bytes 131_072

  @impl true
  def models, do: [Vxpipe.CallEngine.Speech.Model.new("test", "Test provider", true)]

  @impl true
  def configure(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             sample_rate: @default_sample_rate,
             delivery: :streamed,
             chunk_bytes: @default_chunk_bytes,
             maximum_response_bytes: @default_maximum_response_bytes
           ),
         true <- valid_public_options?(options) do
      settings = Map.new(options)

      Descriptor.new(
        kind: :tts,
        settings: settings,
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: settings.sample_rate,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{
          provider: :request_profile,
          model: settings.delivery,
          provenance: :locally_measured
        },
        readiness: :initialized,
        endpointing: :none,
        cache_identity: :crypto.hash(:sha256, :erlang.term_to_binary({__MODULE__, settings}))
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def start_link(options), do: TTSProvider.start_link(__MODULE__, options)

  @impl true
  def speak(pid, reference, text),
    do: GenServer.call(pid, {:speak, reference, text}, 5_000)

  @impl true
  def cancel(pid, reference, playback),
    do: GenServer.call(pid, {:cancel, reference, playback}, 5_000)

  @impl true
  def close(pid), do: GenServer.call(pid, :close, 5_000)

  def continue_batch(pid, token, index),
    do: GenServer.call(pid, {:continue_batch, token, index}, 5_000)

  def deliver_late(pid, task_ref, token, audio) do
    send(pid, {task_ref, {:whole, token, audio}})
    :ok
  end

  @impl true
  def init(options) do
    allocation = Keyword.fetch!(options, :allocation)
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    private = Keyword.fetch!(options, :private)

    with {:ok, observer, responses, hold_ready?} <- validate_private(private),
         :ok <- Channel.bind(channel) do
      send(observer, {:speech_profile_bound, self()})

      if hold_ready? do
        receive do
          :release_ready -> :ok
        end
      end

      with :ok <- Event.emit(channel, :ready, readiness: :initialized) do
        {:ok,
         %{
           allocation: allocation,
           channel: channel,
           last_terminal_request: nil,
           observer: observer,
           request: nil,
           responses: responses,
           settings: descriptor.settings
         }}
      end
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:speak, reference, _text}, _from, %{request: nil} = state) do
    case state.responses do
      [response | responses] ->
        with :ok <- validate_response(response, state.settings) do
          token = make_ref()
          context = %{request_ref: reference, token: token}
          parent = self()

          task =
            Task.Supervisor.async_nolink(SessionTree.commands(state.allocation), fn ->
              send(parent, {:speech_profile_submitted, token, self()})

              receive do
                {:speech_profile_submission_accepted, ^token} -> :ok
              end

              run_response(parent, token, response)
            end)

          send(state.observer, {:speech_profile_task, token, task.ref, task.pid, context})

          request = %{
            awaiting: nil,
            context: context,
            gate: nil,
            offset: 0,
            ref: reference,
            task: task,
            token: token,
            whole: nil
          }

          {:reply, :ok, %{state | request: request, responses: responses}}
        else
          {:error, reason} -> {:reply, {:error, reason}, %{state | responses: responses}}
        end

      [] ->
        {:reply, {:error, :busy}, state}
    end
  end

  def handle_call({:speak, _reference, _text}, _from, state),
    do: {:reply, {:error, :busy}, state}

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: %{ref: reference} = request} = state
      ) do
    stop_task(request.task)
    send(state.observer, {:speech_profile_cancelled, request.token, request.context})

    case Event.emit(state.channel, :cancelled, request_ref: reference) do
      :ok -> {:reply, :ok, %{state | request: nil, last_terminal_request: reference}}
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: nil, last_terminal_request: reference} = state
      ),
      do: {:reply, :ok, %{state | last_terminal_request: nil}}

  def handle_call({:cancel, _reference, _playback}, _from, state),
    do: {:reply, {:error, :stale_request}, state}

  def handle_call(
        {:continue_batch, token, index},
        _from,
        %{request: %{token: token, gate: {index, worker}} = request} = state
      ) do
    send(worker, {:speech_profile_continue, token, index})
    {:reply, :ok, %{state | request: %{request | gate: nil}}}
  end

  def handle_call({:continue_batch, _token, _index}, _from, state),
    do: {:reply, {:error, :stale_batch}, state}

  def handle_call(:close, _from, state) do
    if state.request, do: stop_task(state.request.task)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info(
        {:speech_profile_submitted, token, worker},
        %{request: %{token: token, task: %{pid: worker}} = request} = state
      ) do
    case Event.emit(state.channel, :input_submitted,
           request_ref: request.ref,
           provenance: :locally_measured
         ) do
      :ok ->
        send(worker, {:speech_profile_submission_accepted, token})
        {:noreply, state}

      _failure ->
        {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(
        {:speech_profile_chunk, token, worker, audio},
        %{request: %{token: token, awaiting: nil} = request} = state
      ) do
    if valid_chunk?(audio, state.settings.chunk_bytes) do
      case Channel.submit(state.channel, request.ref, audio) do
        {:ok, credit} ->
          awaiting = %{credit: credit, worker: worker}
          {:noreply, %{state | request: %{request | awaiting: awaiting}}}

        _failure ->
          {:stop, {:shutdown, :session_failed}, state}
      end
    else
      {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(
        {:speech_profile_batch_done, token, index, worker, gate?},
        %{request: %{token: token} = request} = state
      ) do
    send(state.observer, {:speech_profile_batch_done, token, index, request.context})
    gate = if gate?, do: {index, worker}, else: request.gate
    {:noreply, %{state | request: %{request | gate: gate}}}
  end

  def handle_info(
        {:speech_profile_batches_coalesced, token, logical_count, worker},
        %{request: %{token: token} = request} = state
      ) do
    send(
      state.observer,
      {:speech_profile_batches_coalesced, token, logical_count, 1, request.context}
    )

    {:noreply, %{state | request: %{request | gate: {:coalesced, worker}}}}
  end

  def handle_info(
        {:vxpipe_speech_credit, channel, reference, credit, :ok},
        %{
          channel: channel,
          request:
            %{
              ref: reference,
              awaiting: %{credit: credit, worker: worker}
            } = request
        } = state
      ) do
    request = %{request | awaiting: nil}
    if is_pid(worker), do: send(worker, {:speech_profile_credited, request.token})
    state = %{state | request: request}

    if is_nil(worker) do
      send(self(), {:speech_profile_emit_whole, request.token})
    end

    {:noreply, state}
  end

  def handle_info(
        {task_ref, {:whole, token, audio}},
        %{request: %{token: token, task: %{ref: task_ref}} = request} = state
      ) do
    Process.demonitor(task_ref, [:flush])

    case validate_whole(audio, state.settings.maximum_response_bytes) do
      :ok ->
        request = %{request | task: nil, whole: audio, offset: 0}
        send(self(), {:speech_profile_emit_whole, token})
        {:noreply, %{state | request: request}}

      {:error, _reason} ->
        {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(
        {task_ref, {:complete, token}},
        %{request: %{token: token, task: %{ref: task_ref}, awaiting: nil} = request} = state
      ) do
    Process.demonitor(task_ref, [:flush])
    finish_request(%{state | request: %{request | task: nil}})
  end

  def handle_info(
        {:speech_profile_emit_whole, token},
        %{request: %{token: token, awaiting: nil, whole: whole} = request} = state
      )
      when is_binary(whole) do
    if request.offset == byte_size(whole) do
      finish_request(state)
    else
      size = min(state.settings.chunk_bytes, byte_size(whole) - request.offset)
      audio = binary_part(whole, request.offset, size)

      case Channel.submit(state.channel, request.ref, audio) do
        {:ok, credit} ->
          awaiting = %{credit: credit, worker: nil}
          request = %{request | awaiting: awaiting, offset: request.offset + size}
          {:noreply, %{state | request: request}}

        _failure ->
          {:stop, {:shutdown, :session_failed}, state}
      end
    end
  end

  def handle_info(
        {:DOWN, task_ref, :process, _worker, reason},
        %{request: %{task: %{ref: task_ref}}} = state
      )
      when reason != :normal,
      do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :request_tts_profile)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp finish_request(%{request: request} = state) do
    case Event.emit(state.channel, :completed, request_ref: request.ref) do
      :ok ->
        {:noreply, %{state | request: nil, last_terminal_request: request.ref}}

      _failure ->
        {:stop, {:shutdown, :session_failed}, state}
    end
  end

  defp run_response(_parent, token, {:whole, audio}), do: {:whole, token, audio}

  defp run_response(_parent, token, {:held, audio}) do
    receive do
      {:speech_profile_release, ^token} -> {:whole, token, audio}
    end
  end

  defp run_response(parent, token, {:streamed, chunks}) do
    stream_chunks(parent, token, chunks)
    {:complete, token}
  end

  defp run_response(parent, token, {:batched, batches, gate}) do
    count = length(batches)

    batches
    |> Enum.with_index(1)
    |> Enum.each(fn {chunks, index} ->
      stream_chunks(parent, token, chunks)
      gate? = gate == :gate_first and index == 1
      send(parent, {:speech_profile_batch_done, token, index, self(), gate?})

      if gate? do
        receive do
          {:speech_profile_continue, ^token, ^index} -> :ok
        end
      end

      if index == count, do: :ok
    end)

    {:complete, token}
  end

  defp run_response(parent, token, {:coalesced, chunks, logical_count}) do
    stream_chunks(parent, token, chunks)
    send(parent, {:speech_profile_batches_coalesced, token, logical_count, self()})

    receive do
      {:speech_profile_continue, ^token, :coalesced} -> :ok
    end

    {:complete, token}
  end

  defp stream_chunks(parent, token, chunks) do
    Enum.each(chunks, fn audio ->
      send(parent, {:speech_profile_chunk, token, self(), audio})

      receive do
        {:speech_profile_credited, ^token} -> :ok
      end
    end)
  end

  defp stop_task(nil), do: :ok

  defp stop_task(task) do
    _result = Task.shutdown(task, :brutal_kill)
    :ok
  end

  defp validate_private(private) do
    credential = Keyword.get(private, :credential)
    observer = Keyword.get(private, :observer)
    responses = Keyword.get(private, :responses, [])
    hold_ready? = Keyword.get(private, :hold_ready?, false)

    if is_binary(credential) and byte_size(credential) > 0 and is_pid(observer) and
         is_list(responses) and is_boolean(hold_ready?),
       do: {:ok, observer, responses, hold_ready?},
       else: {:error, :invalid_private_configuration}
  end

  defp validate_response({:whole, audio}, %{delivery: :whole}) when is_binary(audio), do: :ok

  defp validate_response({:held, audio}, _settings) when is_binary(audio), do: :ok

  defp validate_response({:streamed, chunks}, %{delivery: :streamed})
       when is_list(chunks) and chunks != [],
       do: :ok

  defp validate_response({:batched, batches, gate}, %{delivery: :batched})
       when gate in [:ungated, :gate_first] and is_list(batches),
       do:
         if(Enum.all?(batches, &(is_list(&1) and &1 != [])),
           do: :ok,
           else: {:error, :invalid_text}
         )

  defp validate_response(
         {:coalesced, chunks, logical_count},
         %{delivery: :batched}
       )
       when is_integer(logical_count) and logical_count > 1 and is_list(chunks) and chunks != [],
       do: :ok

  defp validate_response(_response, _settings), do: {:error, :invalid_text}

  defp validate_whole(audio, maximum) do
    if is_binary(audio) and byte_size(audio) in 2..maximum and rem(byte_size(audio), 2) == 0,
      do: :ok,
      else: {:error, :output_too_large}
  end

  defp valid_chunk?(audio, maximum),
    do: is_binary(audio) and byte_size(audio) in 2..maximum and rem(byte_size(audio), 2) == 0

  defp valid_public_options?(options) do
    rate = Keyword.fetch!(options, :sample_rate)
    delivery = Keyword.fetch!(options, :delivery)
    chunk = Keyword.fetch!(options, :chunk_bytes)
    maximum = Keyword.fetch!(options, :maximum_response_bytes)

    is_integer(rate) and rate > 0 and delivery in [:streamed, :whole, :batched] and
      is_integer(chunk) and chunk in 2..131_072 and rem(chunk, 2) == 0 and
      is_integer(maximum) and maximum in 2..1_048_576 and rem(maximum, 2) == 0 and
      chunk <= maximum
  end
end
