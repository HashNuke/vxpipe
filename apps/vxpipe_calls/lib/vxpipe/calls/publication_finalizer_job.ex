defmodule Vxpipe.Calls.PublicationFinalizerJob do
  @moduledoc "Validated dependencies for assessing one ended call until it is publishable."

  alias Vxpipe.Calls.{
    ProcessPublicationTimer,
    PublicationClock,
    PublicationSources,
    PublicationTimer,
    SystemPublicationClock
  }

  @default_poll_ms 5_000

  @derive {Inspect, except: [:options, :clock, :timer]}
  @enforce_keys [
    :tenant_key,
    :call_id,
    :options,
    :registry,
    :clock,
    :timer,
    :settlement_poll_ms,
    :observer
  ]
  defstruct @enforce_keys

  @type adapter :: {module(), term()}

  @type t :: %__MODULE__{
          tenant_key: String.t(),
          call_id: String.t(),
          options: keyword(),
          registry: atom(),
          clock: adapter(),
          timer: adapter(),
          settlement_poll_ms: pos_integer(),
          observer: nil | pid()
        }

  @spec new(String.t(), String.t(), keyword()) ::
          {:ok, t()} | {:error, :invalid_publication_finalizer}
  def new(tenant_key, call_id, options)
      when is_binary(tenant_key) and tenant_key != "" and is_binary(call_id) and call_id != "" and
             is_list(options) do
    settings = configured_settings()

    with {:ok, _source} <- PublicationSources.fetch(options),
         registry when is_atom(registry) <-
           value(options, settings, :publication_registry, Vxpipe.Calls.PublicationRegistry),
         {:ok, clock} <-
           port(
             options,
             settings,
             :publication_clock,
             {SystemPublicationClock, nil},
             PublicationClock
           ),
         {:ok, timer} <-
           port(
             options,
             settings,
             :publication_timer,
             {ProcessPublicationTimer, nil},
             PublicationTimer
           ),
         settlement_poll_ms when is_integer(settlement_poll_ms) and settlement_poll_ms > 0 <-
           value(options, settings, :settlement_poll_ms, @default_poll_ms),
         {:ok, observer} <- optional_observer(Keyword.get(options, :observer)) do
      {:ok,
       %__MODULE__{
         tenant_key: tenant_key,
         call_id: call_id,
         options: options,
         registry: registry,
         clock: clock,
         timer: timer,
         settlement_poll_ms: settlement_poll_ms,
         observer: observer
       }}
    else
      _invalid -> {:error, :invalid_publication_finalizer}
    end
  end

  def new(_tenant_key, _call_id, _options), do: {:error, :invalid_publication_finalizer}

  @spec key(t()) :: {:call_details_finalizer, String.t(), String.t()}
  def key(%__MODULE__{} = job),
    do: {:call_details_finalizer, job.tenant_key, job.call_id}

  @spec via(t()) :: {:via, Registry, {atom(), term()}}
  def via(%__MODULE__{} = job), do: {:via, Registry, {job.registry, key(job)}}

  defp configured_settings do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])
    Keyword.merge(configured, Keyword.get(configured, :call_details_publication, []))
  end

  defp port(options, settings, key, default, behaviour) do
    case value(options, settings, key, default) do
      {module, _context} = adapter when is_atom(module) ->
        if behaviour.valid?(module), do: {:ok, adapter}, else: {:error, key}

      _invalid ->
        {:error, key}
    end
  end

  defp value(options, settings, key, default) do
    Keyword.get(options, key, Keyword.get(settings, key, default))
  end

  defp optional_observer(nil), do: {:ok, nil}
  defp optional_observer(observer) when is_pid(observer), do: {:ok, observer}
  defp optional_observer(_observer), do: {:error, :observer}
end
