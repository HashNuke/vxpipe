defmodule Vxpipe.CallEngine.Tool.Dispatcher do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Tool.{Call, Context, Executor}

  @call_timeout 15_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

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

  @impl true
  def init(options) do
    with {:ok, executor} <-
           Executor.new(
             Keyword.fetch!(options, :tools),
             Keyword.fetch!(options, :maximum_result_bytes)
           ) do
      {:ok, executor}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call({:execute, name, arguments, context}, _from, executor) do
    call = %Call{
      id: context.command_id,
      name: name,
      arguments: arguments
    }

    {:reply, Executor.execute(executor, call, context), executor}
  end
end
