defmodule Vxpipe.CallEngine.Speech.Session do
  @moduledoc """
  Owned, bounded speech sessions. The owner alone submits input and acknowledges
  events; each synchronous submission finishes before it can admit another.
  Start through `start/1` in production or `child_spec/1` under a test supervisor.
  Provider modules and private options are trusted host configuration.
  """

  alias Vxpipe.CallEngine.Speech.{Channel, SessionTree}

  @maximum_audio_bytes 131_072
  @timeout 5_000

  def child_spec(options) do
    options = Keyword.put_new(options, :owner, self())

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      type: :supervisor,
      shutdown: 5_000
    }
  end

  def start(options) do
    DynamicSupervisor.start_child(Vxpipe.CallEngine.Speech.SessionSupervisor, child_spec(options))
  end

  @doc false
  def start_link(options) do
    provider = Keyword.fetch!(options, :provider)

    with {:ok, descriptor} <- provider.configure(Keyword.get(options, :options, [])) do
      options =
        options
        |> Keyword.put(:descriptor, descriptor)
        |> Keyword.put_new(:start_timeout, @timeout)
        |> Keyword.put_new(:call_timeout, @timeout)

      SessionTree.start_link(options)
    end
  end

  def describe(session) do
    with {:ok, metadata} <- lookup(session), do: {:ok, metadata.descriptor}
  end

  def push_audio(session, audio)
      when is_binary(audio) and byte_size(audio) in 1..@maximum_audio_bytes do
    with {:ok, metadata} <- owned(session),
         true <- metadata.active? do
      invoke(session, metadata.call_timeout, fn ->
        metadata.module.push_audio(metadata.provider, audio)
      end)
    else
      false -> {:error, :not_ready}
      error -> error
    end
  end

  def push_audio(_session, audio) when is_binary(audio), do: {:error, :invalid_audio_size}
  def push_audio(_session, _audio), do: {:error, :invalid_audio}

  def ack(session, event) do
    with {:ok, _metadata} <- owned(session) do
      GenServer.call(Channel.address(session), {:ack, event}, @timeout)
    end
  catch
    :exit, _reason -> {:error, :closed}
  end

  def close(session) do
    case owned(session) do
      {:ok, metadata} ->
        _result =
          invoke(session, metadata.call_timeout, fn ->
            metadata.module.close(metadata.provider)
          end)

        retire(session)

      {:error, :closed} ->
        :ok

      error ->
        error
    end
  end

  defp invoke(session, timeout, operation) do
    task =
      Task.Supervisor.async_nolink(SessionTree.commands(session), fn -> safely(operation) end)

    case Task.yield(task, timeout) do
      {:ok, {:error, :session_failed}} ->
        retire(session)
        {:error, :session_failed}

      {:ok, result} ->
        result

      _failed ->
        Task.shutdown(task, :brutal_kill)
        retire(session)
        {:error, :session_failed}
    end
  catch
    :exit, _reason ->
      retire(session)
      {:error, :session_failed}
  end

  defp safely(operation) do
    operation.()
  rescue
    _error -> {:error, :session_failed}
  catch
    _kind, _reason -> {:error, :session_failed}
  end

  defp retire(session) do
    monitor = Process.monitor(session)
    stop_tree(session)

    receive do
      {:DOWN, ^monitor, :process, ^session, _reason} -> :ok
    after
      @timeout ->
        Process.demonitor(monitor, [:flush])
        {:error, :close_timeout}
    end
  end

  defp stop_tree(session) do
    case lookup(session) do
      {:ok, metadata} ->
        # Force retirement of the known provider before stopping its supervisor;
        # even a trapped, blocked callback cannot outlive a timed-out command.
        if is_pid(metadata.provider), do: Process.exit(metadata.provider, :kill)
        Supervisor.stop(session, :normal, @timeout)

      {:error, :closed} ->
        :ok
    end
  catch
    :exit, _reason -> Process.exit(session, :kill)
  end

  defp owned(session) do
    with {:ok, metadata} <- lookup(session) do
      if metadata.owner == self(), do: {:ok, metadata}, else: {:error, :not_owner}
    end
  end

  defp lookup(session) do
    case Registry.lookup(Vxpipe.CallEngine.Speech.Registry, session) do
      [{_channel, metadata}] ->
        if Process.alive?(session), do: {:ok, metadata}, else: {:error, :closed}

      [] ->
        {:error, :closed}
    end
  end
end
