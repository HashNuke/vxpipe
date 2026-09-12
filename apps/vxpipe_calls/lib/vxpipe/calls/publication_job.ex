defmodule Vxpipe.Calls.PublicationJob do
  @moduledoc "Validated dependencies and limits for delivering one call-details snapshot."

  alias Vxpipe.Calls.{
    CallDetailsPublication,
    CallDetailsSnapshot,
    PublicationArtifactWriter,
    PublicationRepository
  }

  @default_maximum_attempts 3
  @default_retry_delay_ms 1_000
  @default_attempt_timeout_ms 15_000

  @derive {Inspect, except: [:source, :repository, :artifact_writer]}
  @enforce_keys [
    :tenant_key,
    :call_id,
    :source,
    :repository,
    :artifact_writer,
    :registry,
    :task_supervisor,
    :maximum_attempts,
    :retry_delay_ms,
    :attempt_timeout_ms,
    :observer
  ]
  defstruct @enforce_keys

  @type adapter :: {module(), term()}

  @type t :: %__MODULE__{
          tenant_key: String.t(),
          call_id: String.t(),
          source: CallDetailsSnapshot.t() | CallDetailsPublication.t(),
          repository: adapter(),
          artifact_writer: adapter(),
          registry: atom(),
          task_supervisor: GenServer.server(),
          maximum_attempts: pos_integer(),
          retry_delay_ms: non_neg_integer(),
          attempt_timeout_ms: pos_integer(),
          observer: nil | pid()
        }

  @spec new(String.t(), String.t(), CallDetailsSnapshot.t(), keyword()) ::
          {:ok, t()} | {:error, :invalid_publication_job}
  def new(tenant_key, call_id, %CallDetailsSnapshot{} = snapshot, options)
      when is_binary(tenant_key) and tenant_key != "" and is_binary(call_id) and call_id != "" and
             is_list(options) do
    build(tenant_key, call_id, snapshot, options)
  end

  def new(_tenant_key, _call_id, _snapshot, _options), do: {:error, :invalid_publication_job}

  @spec resume(CallDetailsPublication.t(), keyword()) ::
          {:ok, t()} | {:error, :invalid_publication_job}
  def resume(%CallDetailsPublication{} = publication, options) when is_list(options) do
    build(publication.tenant_key, publication.call_id, publication, options)
  end

  def resume(_publication, _options), do: {:error, :invalid_publication_job}

  @spec key(t()) :: {String.t(), String.t(), binary()}
  def key(%__MODULE__{} = job),
    do: {job.tenant_key, job.call_id, job.source.source_digest}

  @spec publication_id(t()) :: String.t()
  def publication_id(%__MODULE__{source: %CallDetailsSnapshot{} = snapshot}),
    do: snapshot.publication_id

  def publication_id(%__MODULE__{source: %CallDetailsPublication{} = publication}),
    do: publication.id

  @spec via(t()) :: {:via, Registry, {atom(), term()}}
  def via(%__MODULE__{} = job), do: {:via, Registry, {job.registry, key(job)}}

  defp build(tenant_key, call_id, source, options) do
    settings = configured_settings()

    with {:ok, repository} <-
           port(options, settings, :publication_repository, PublicationRepository),
         {:ok, artifact_writer} <-
           port(options, settings, :publication_artifact_writer, PublicationArtifactWriter),
         registry when is_atom(registry) <-
           value(options, settings, :publication_registry, Vxpipe.Calls.PublicationRegistry),
         task_supervisor when is_atom(task_supervisor) or is_pid(task_supervisor) <-
           value(
             options,
             settings,
             :publication_task_supervisor,
             Vxpipe.Calls.PublicationTaskSupervisor
           ),
         maximum_attempts when is_integer(maximum_attempts) and maximum_attempts > 0 <-
           value(options, settings, :maximum_attempts, @default_maximum_attempts),
         retry_delay_ms when is_integer(retry_delay_ms) and retry_delay_ms >= 0 <-
           value(options, settings, :retry_delay_ms, @default_retry_delay_ms),
         attempt_timeout_ms when is_integer(attempt_timeout_ms) and attempt_timeout_ms > 0 <-
           value(options, settings, :attempt_timeout_ms, @default_attempt_timeout_ms),
         {:ok, observer} <- optional_observer(Keyword.get(options, :observer)) do
      {:ok,
       %__MODULE__{
         tenant_key: tenant_key,
         call_id: call_id,
         source: source,
         repository: repository,
         artifact_writer: artifact_writer,
         registry: registry,
         task_supervisor: task_supervisor,
         maximum_attempts: maximum_attempts,
         retry_delay_ms: retry_delay_ms,
         attempt_timeout_ms: attempt_timeout_ms,
         observer: observer
       }}
    else
      _invalid -> {:error, :invalid_publication_job}
    end
  end

  defp configured_settings do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])
    Keyword.merge(configured, Keyword.get(configured, :call_details_publication, []))
  end

  defp port(options, settings, key, behaviour) do
    case value(options, settings, key, nil) do
      {module, _context} = port when is_atom(module) ->
        if behaviour.valid?(module), do: {:ok, port}, else: {:error, key}

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
