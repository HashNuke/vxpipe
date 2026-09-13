defmodule Vxpipe.CallEngine.Media.ConnectionReadiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.PreparedConnection
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.Resource

  @task_supervisor Vxpipe.CallEngine.ReadinessTaskSupervisor
  @demand_keys [:audio_input?, :room_output?, :speech_to_text?]

  @callback prepare_binding(map(), Snapshot.t(), map()) ::
              {:ok, [Resource.t()], PreparedConnection.input_track() | nil} | {:error, atom()}

  def prepare(connection, identity, policy, options, timeout \\ 5_000) do
    with {:ok, prepared} <- prepare_graph(connection, identity, policy, options, timeout),
         do: {:ok, prepared.resources}
  end

  # Lifecycle callers run this outside RoomAuthority and supply their remaining attempt budget.
  def prepare_graph(connection, identity, policy, options, timeout \\ 5_000)
      when is_pid(connection) and is_integer(timeout) and timeout > 0 do
    with {:ok, demand} <- demand(options),
         :ok <- validate_policy(policy, identity) do
      result =
        Task.Supervisor.async_stream_nolink(
          @task_supervisor,
          [connection],
          &prepare_connection(&1, identity, policy, demand),
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
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp prepare_connection(connection, identity, policy, demand) do
    with {:ok, binding} <- read_binding(connection),
         :ok <- validate_binding(binding, connection, identity),
         :ok <- validate_adapter(binding.adapter),
         {:ok, resources, input_track} <- binding.adapter.prepare_binding(binding, policy, demand),
         :ok <- validate_input_track(input_track, demand),
         :ok <- validate_resources(resources, connection, identity),
         {:ok, current} <- read_binding(connection) do
      if current == binding do
        {:ok,
         %PreparedConnection{
           identity: identity,
           instance: connection,
           generation: binding.generation,
           input_track: input_track,
           resources: resources
         }}
      else
        {:error, :connection_changed}
      end
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
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

  defp validate_adapter(adapter) do
    if is_atom(adapter) and Code.ensure_loaded?(adapter) and
         function_exported?(adapter, :prepare_binding, 3),
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
