defmodule Vxpipe.CallEngine.Diagnostics.ModelFixture do
  @moduledoc false

  use GenServer

  @scenarios [:success, :delay, :failure, :missing]
  @call_timeout 1_000
  @maximum_delay_ms 10_000

  def start_link(options) do
    {genserver_options, options} = Keyword.split(options, [:name])
    GenServer.start_link(__MODULE__, options, genserver_options)
  end

  @spec arm(GenServer.server(), atom()) :: :ok | {:error, :invalid_scenario | :unavailable}
  def arm(server \\ __MODULE__, scenario) do
    GenServer.call(server, {:arm, scenario}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec status(GenServer.server()) :: map() | {:error, :unavailable}
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec take(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :unavailable}
  def take(server \\ __MODULE__, user) when is_binary(user) and user != "" do
    GenServer.call(server, {:take, user}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             default_scenario: :success,
             delay_ms: 1_500,
             response: "Local fixture response."
           ),
         default_scenario when default_scenario in @scenarios <-
           Keyword.fetch!(options, :default_scenario),
         delay_ms when is_integer(delay_ms) and delay_ms >= 0 and delay_ms <= @maximum_delay_ms <-
           Keyword.fetch!(options, :delay_ms),
         response when is_binary(response) and response != "" <-
           Keyword.fetch!(options, :response) do
      {:ok,
       %{
         default_scenario: default_scenario,
         delay_ms: delay_ms,
         next_scenario: default_scenario,
         response: response
       }}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call({:arm, scenario}, _from, state) when scenario in @scenarios do
    {:reply, :ok, %{state | next_scenario: scenario}}
  end

  def handle_call({:arm, _scenario}, _from, state) do
    {:reply, {:error, :invalid_scenario}, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, Map.take(state, [:next_scenario, :default_scenario, :delay_ms]), state}
  end

  def handle_call({:take, user}, _from, state) do
    scenario = state.next_scenario

    fixture = %{
      delay_ms: if(scenario == :delay, do: state.delay_ms, else: 0),
      response: state.response,
      scenario: scenario,
      user: user
    }

    {:reply, {:ok, fixture}, %{state | next_scenario: state.default_scenario}}
  end
end
