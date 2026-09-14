defmodule Vxpipe.CallEngine.Media.ConnectionReadiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.PreparedConnection
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Candidate, Snapshot}
  alias Vxpipe.CallEngine.Readiness.Resource

  @task_supervisor Vxpipe.CallEngine.ReadinessTaskSupervisor
  @demand_keys [:audio_input?, :room_output?, :speech_to_text?]

  @callback prepare_binding(map(), Snapshot.t(), map()) ::
              {:ok, [Resource.t()], PreparedConnection.input_track() | nil} | {:error, atom()}

  @callback prepare_candidate(map(), Candidate.t(), map(), keyword()) ::
              {:ok, [Resource.t()], PreparedConnection.input_track() | nil, [map()]}
              | {:error, atom()}
  @optional_callbacks prepare_candidate: 4

  def prepare_candidate(connection, identity, %Candidate{} = candidate, options, preparation)
      when is_pid(connection) do
    with {:ok, demand} <- demand(options),
         :ok <- validate_preparation(preparation),
         :ok <- validate_candidate(candidate, identity, preparation) do
      run(connection, identity, candidate, demand, remaining(preparation), preparation)
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def discard_candidate(%PreparedConnection{} = graph), do: PreparedConnection.discard(graph)

  @doc false
  def capture(connection, identity) do
    with {:ok, binding} <- read_binding(connection),
         :ok <- validate_binding(binding, connection, identity),
         :ok <- validate_adapter(binding.adapter, :candidate),
         do: {:ok, binding}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def prepare(connection, identity, policy, options, timeout \\ 5_000) do
    with {:ok, prepared} <- prepare_graph(connection, identity, policy, options, timeout),
         do: {:ok, prepared.resources}
  end

  # Lifecycle callers run this outside RoomAuthority and supply their remaining attempt budget.
  def prepare_graph(connection, identity, policy, options, timeout \\ 5_000)
      when is_pid(connection) and is_integer(timeout) and timeout > 0 do
    with {:ok, demand} <- demand(options),
         :ok <- validate_policy(policy, identity) do
      run(connection, identity, policy, demand, timeout, nil)
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp run(connection, identity, policy, demand, timeout, preparation) do
    result =
      Task.Supervisor.async_stream(
        @task_supervisor,
        [connection],
        &prepare_connection(&1, identity, policy, demand, preparation),
        max_concurrency: 1,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    case result do
      [{:ok, result}] -> result
      _unavailable -> {:error, :unavailable}
    end
  end

  defp prepare_connection(connection, identity, policy, demand, preparation) do
    with {:ok, binding} <- read_binding(connection),
         :ok <- validate_binding(binding, connection, identity),
         :ok <- validate_adapter(binding.adapter, preparation),
         {:ok, resources, input_track, preparations} <-
           prepare_binding(binding, policy, demand, preparation) do
      graph = %PreparedConnection{
        identity: identity,
        instance: connection,
        generation: binding.generation,
        input_track: input_track,
        resources: resources,
        preparations: preparations
      }

      case validate_result(graph, binding, policy, demand, preparation) do
        :ok ->
          {:ok, graph}

        {:error, _reason} = error ->
          _ = PreparedConnection.discard(graph)
          error
      end
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end

  defp prepare_binding(binding, policy, demand, nil) do
    with {:ok, resources, track} <- binding.adapter.prepare_binding(binding, policy, demand),
         do: {:ok, resources, track, []}
  end

  defp prepare_binding(binding, candidate, demand, preparation),
    do: binding.adapter.prepare_candidate(binding, candidate, demand, preparation)

  defp validate_result(graph, binding, policy, demand, preparation) do
    with :ok <- validate_input_track(graph.input_track, demand),
         :ok <- validate_resources(graph.resources, graph.instance, graph.identity),
         {:ok, current} <- read_binding(graph.instance),
         true <- current == binding,
         :ok <- validate_candidate(policy, graph.identity, preparation) do
      :ok
    else
      false -> {:error, :connection_changed}
      {:error, _reason} = error -> error
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp read_binding(connection),
    do: GenServer.call(connection, :vxpipe_connection_readiness, 1_000)

  defp validate_binding(
         %{identity: identity, instance: connection, generation: generation},
         connection,
         identity
       )
       when is_reference(generation), do: :ok

  defp validate_binding(_binding, _connection, _identity), do: {:error, :wrong_connection}

  defp validate_adapter(adapter, preparation) do
    {callback, arity} = if preparation, do: {:prepare_candidate, 4}, else: {:prepare_binding, 3}

    if is_atom(adapter) and Code.ensure_loaded?(adapter) and
         function_exported?(adapter, callback, arity),
       do: :ok,
       else: {:error, :unsupported_adapter}
  end

  defp validate_resources(resources, connection, identity)
       when is_list(resources) and length(resources) in 1..32 do
    scope = {:participant, identity.participant_id}

    valid? =
      Enum.all?(resources, &match?(%Resource{scope: ^scope}, &1)) and
        Enum.any?(resources, fn resource ->
          resource.kind == :media_connection and resource.instance == connection and
            resource.binding == identity.connection_id
        end) and
        length(Enum.uniq_by(resources, &Resource.key/1)) == length(resources)

    if valid?, do: :ok, else: {:error, :invalid_resources}
  end

  defp validate_resources(_resources, _connection, _identity), do: {:error, :invalid_resources}

  defp validate_input_track(nil, %{audio_input?: false, speech_to_text?: false}), do: :ok

  defp validate_input_track(
         %{track_id: track, codec: codec, sample_rate: rate, channels: channels} = input,
         demand
       )
       when is_binary(track) and byte_size(track) > 0 and is_atom(codec) and
              not is_nil(codec) and is_integer(rate) and rate > 0 and channels in [1, 2] and
              map_size(input) == 4 do
    if demand.audio_input? or demand.speech_to_text?,
      do: :ok,
      else: {:error, :invalid_input_track}
  end

  defp validate_input_track(_track, _demand), do: {:error, :invalid_input_track}

  defp validate_policy(%Snapshot{} = policy, %{participant_id: participant}) do
    if Snapshot.valid?(policy) and MapSet.member?(policy.present_participant_ids, participant),
      do: :ok,
      else: {:error, :invalid_policy}
  end

  defp validate_policy(_policy, _identity), do: {:error, :invalid_policy}

  defp validate_candidate(_snapshot, _identity, nil), do: :ok

  defp validate_candidate(candidate, identity, preparation) do
    with true <- Authority.whereis(identity.incarnation_id) == candidate.authority,
         :ok <- validate_policy(candidate.snapshot, identity),
         :ok <-
           Authority.validate_candidate(candidate.authority, candidate, remaining(preparation)) do
      :ok
    else
      false -> {:error, :invalid_candidate}
      {:error, _reason} = error -> error
    end
  end

  defp validate_preparation(options) do
    if Keyword.keyword?(options) and is_pid(Keyword.get(options, :owner)) and
         is_binary(Keyword.get(options, :attempt_id)) and
         byte_size(Keyword.fetch!(options, :attempt_id)) in 1..128 and
         is_integer(Keyword.get(options, :generation)) and
         Keyword.fetch!(options, :generation) > 0 and
         is_integer(Keyword.get(options, :deadline_ms)) and
         Keyword.fetch!(options, :deadline_ms) > System.monotonic_time(:millisecond),
       do: :ok,
       else: {:error, :invalid_preparation}
  end

  defp remaining(options) do
    case Keyword.fetch!(options, :deadline_ms) - System.monotonic_time(:millisecond) do
      remaining when remaining > 0 -> remaining
      _expired -> exit(:deadline_elapsed)
    end
  end

  defp demand(options) do
    if Keyword.keyword?(options) and
         Enum.all?(options, fn {key, value} -> key in @demand_keys and is_boolean(value) end) and
         length(Enum.uniq_by(options, &elem(&1, 0))) == length(options) do
      {:ok, Map.new(@demand_keys, &{&1, Keyword.get(options, &1, false)})}
    else
      {:error, :invalid_demand}
    end
  end
end
