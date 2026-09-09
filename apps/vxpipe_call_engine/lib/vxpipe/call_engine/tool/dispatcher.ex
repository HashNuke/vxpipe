defmodule Vxpipe.CallEngine.Tool.Dispatcher do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.CallVariables.Binding
  alias Vxpipe.CallEngine.Tool.{Call, Context, Executor}
  alias Vxpipe.CallEngine.Tool.Dispatcher.State

  @call_timeout 15_000

  def start_link(options) do
    genserver_options = Keyword.take(options, [:name])
    GenServer.start_link(__MODULE__, options, genserver_options)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :activation_id)},
      start: {__MODULE__, :start_link, [options]}
    }
  end

  @spec execute(GenServer.server(), String.t(), map(), Context.t()) ::
          {:ok, term()}
          | {:error, :invalid_arguments | :invalid_result | :tool_failed | :unknown_tool}
  def execute(dispatcher, name, arguments, %Context{} = context)
      when is_binary(name) and is_map(arguments) do
    GenServer.call(dispatcher, {:execute, name, arguments, context}, @call_timeout)
  catch
    :exit, _reason -> {:error, :tool_failed}
  end

  @spec variable_projection(GenServer.server()) :: {:ok, nil | map()} | {:error, :tool_failed}
  def variable_projection(dispatcher) do
    GenServer.call(dispatcher, :variable_projection, @call_timeout)
  catch
    :exit, _reason -> {:error, :tool_failed}
  end

  @spec register_tool_call(GenServer.server(), String.t(), map()) :: :ok | {:error, term()}
  def register_tool_call(dispatcher, request_id, tool_call)
      when is_binary(request_id) and is_map(tool_call) do
    GenServer.call(dispatcher, {:register_tool_call, request_id, tool_call}, @call_timeout)
  catch
    :exit, _reason -> {:error, :tool_failed}
  end

  @impl true
  def init(options) do
    with {:ok, executor} <-
           Executor.new(
             Keyword.fetch!(options, :tools),
             Keyword.fetch!(options, :maximum_result_bytes)
           ) do
      {:ok,
       %State{
         executor: executor,
         maximum_result_bytes: Keyword.fetch!(options, :maximum_result_bytes),
         variable_binding: Keyword.get(options, :variable_binding),
         tool_calls: %{}
       }}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call({:execute, name, arguments, context}, _from, %State{} = state) do
    call = %Call{
      id: context.command_id,
      name: name,
      arguments: arguments
    }

    {result, state} = execute_call(state, call, context)
    {:reply, result, state}
  end

  def handle_call({:register_tool_call, request_id, tool_call}, _from, %State{} = state) do
    case registration(request_id, tool_call, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:variable_projection, _from, %State{variable_binding: nil} = state) do
    {:reply, {:ok, nil}, state}
  end

  def handle_call(:variable_projection, _from, %State{} = state) do
    {:reply, Binding.projection(state.variable_binding), state}
  end

  defp execute_call(%State{variable_binding: %Binding{} = binding} = state, call, context) do
    if Binding.variable_tool?(call.name) do
      case pop_tool_call(state, context.agent_request_id, call) do
        {:ok, tool_call_id, state} ->
          context = %{context | tool_call_id: tool_call_id}

          result =
            binding
            |> Binding.execute(call.name, call.arguments, context)
            |> normalize_variable_result(state.maximum_result_bytes)

          {result, state}

        {:error, state} ->
          {{:error, :tool_failed}, state}
      end
    else
      {Executor.execute(state.executor, call, context), state}
    end
  end

  defp execute_call(%State{} = state, call, context) do
    {Executor.execute(state.executor, call, context), state}
  end

  defp registration(request_id, tool_call, %State{} = state) do
    with {:ok, name} <- fetch(tool_call, :tool_name),
         true <- is_binary(name),
         {:ok, tool_call_id} <- fetch(tool_call, :tool_call_id),
         true <- is_binary(tool_call_id),
         {:ok, arguments} <- fetch(tool_call, :arguments),
         true <- is_map(arguments) do
      if match?(%Binding{}, state.variable_binding) and Binding.variable_tool?(name) do
        key = tool_call_key(request_id, name, arguments)
        queue = :queue.in(tool_call_id, Map.get(state.tool_calls, key, :queue.new()))
        {:ok, %{state | tool_calls: Map.put(state.tool_calls, key, queue)}}
      else
        {:ok, state}
      end
    else
      _invalid -> {:error, :invalid_tool_call}
    end
  end

  defp pop_tool_call(%State{} = state, request_id, call) when is_binary(request_id) do
    key = tool_call_key(request_id, call.name, call.arguments)

    case state.tool_calls |> Map.get(key, :queue.new()) |> :queue.out() do
      {{:value, tool_call_id}, queue} ->
        tool_calls =
          if :queue.is_empty(queue) do
            Map.delete(state.tool_calls, key)
          else
            Map.put(state.tool_calls, key, queue)
          end

        {:ok, tool_call_id, %{state | tool_calls: tool_calls}}

      {:empty, _queue} ->
        {:error, state}
    end
  end

  defp pop_tool_call(%State{} = state, _request_id, _call), do: {:error, state}

  defp tool_call_key(request_id, name, arguments) do
    {request_id, name, arguments |> normalize_json() |> JSON.encode!()}
  end

  defp normalize_json(value) when is_map(value) do
    Map.new(value, fn {key, nested} ->
      key = if is_atom(key), do: Atom.to_string(key), else: key
      {key, normalize_json(nested)}
    end)
  end

  defp normalize_json(value) when is_list(value), do: Enum.map(value, &normalize_json/1)
  defp normalize_json(value), do: value

  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(map, Atom.to_string(key))
    end
  end

  defp normalize_variable_result({:ok, result}, maximum_result_bytes) do
    try do
      if byte_size(JSON.encode!(result)) <= maximum_result_bytes do
        {:ok, result}
      else
        {:error, :invalid_result}
      end
    rescue
      _exception -> {:error, :invalid_result}
    end
  end

  defp normalize_variable_result({:error, reason}, _maximum_result_bytes), do: {:error, reason}
end
