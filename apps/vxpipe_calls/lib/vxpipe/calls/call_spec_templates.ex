defmodule Vxpipe.Calls.CallSpecTemplates do
  @moduledoc """
  The local call spec template library and its tenant installer.

  Templates live one per directory under the configured library directory. An
  installation renders a template with caller-supplied inputs, validates the result
  against the tenant and stores it through ordinary authoring.
  """

  alias Vxpipe.Calls.{
    CallSpecAuthoring,
    CallSpecAuthorization,
    CallSpecs,
    CallSpecTemplate,
    Repositories
  }

  @spec list(keyword()) :: {:ok, [CallSpecTemplate.t()]} | {:error, term()}
  def list(options \\ []) do
    directory = directory(options)

    case File.ls(directory) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.map(&Path.join(directory, &1))
        |> Enum.filter(&File.dir?/1)
        |> load_all()

      {:error, _reason} ->
        {:error, :call_spec_template_library_unavailable}
    end
  end

  @spec fetch(String.t(), keyword()) :: {:ok, CallSpecTemplate.t()} | {:error, term()}
  def fetch(id, options \\ []) do
    path = CallSpecTemplate.valid_id?(id) && Path.join(directory(options), id)

    if path && File.dir?(path),
      do: CallSpecTemplate.load(path),
      else: {:error, :call_spec_template_not_found}
  end

  @spec render(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def render(id, inputs, options \\ []) do
    with {:ok, template} <- fetch(id, options), do: CallSpecTemplate.render(template, inputs)
  end

  @doc """
  Renders, validates and saves a template into a tenant. The source `name` identifies
  the installation: an identical existing source is reused and a different one is a
  conflict, never overwritten. A rendering that fails the tenant's save-time checks is
  rejected without being stored. Pass `publish: true` to publish the installed revision.
  """
  @spec install(term(), String.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def install(authority, tenant_key, id, inputs, options \\ []) do
    # Installations locate their target by name only; a supplied ID would append to it.
    options = Keyword.delete(options, :call_spec_id)

    with :ok <- CallSpecAuthorization.authorize(authority, :write, tenant_key),
         {:ok, source} <- render(id, inputs, options),
         {:ok, repository} <- Repositories.fetch(options, :call_spec_repository) do
      :global.trans({{__MODULE__, tenant_key, source["name"]}, self()}, fn ->
        install_locked(authority, tenant_key, id, source, repository, options)
      end)
    end
  end

  defp install_locked(authority, tenant_key, id, source, repository, options) do
    case Repositories.call(repository, :find_by_original_name, [tenant_key, source["name"]]) do
      {:ok, []} ->
        with {:ok, []} <- CallSpecAuthoring.validate(authority, tenant_key, source, options),
             {:ok, draft} <- CallSpecAuthoring.save(authority, tenant_key, source, options) do
          finish(:created, id, draft, authority, repository, options)
        else
          {:ok, errors} -> {:error, {:call_spec_template_invalid, errors}}
          {:error, _reason} = error -> error
        end

      {:ok, [call_spec_id]} ->
        with {:ok, latest} <- latest(repository, tenant_key, call_spec_id, options) do
          if latest.source == source,
            do: finish(:unchanged, id, latest, authority, repository, options),
            else: {:error, :call_spec_template_conflict}
        end

      {:ok, _ambiguous} ->
        {:error, :call_spec_template_conflict}

      {:error, _reason} = error ->
        error
    end
  end

  defp latest(repository, tenant_key, call_spec_id, options) do
    with {:ok, next} <- Repositories.call(repository, :next_revision, [tenant_key, call_spec_id]) do
      CallSpecs.fetch(tenant_key, call_spec_id, next - 1, options)
    end
  end

  defp finish(status, id, revision, authority, repository, options) do
    with {:ok, published?} <- published?(repository, revision),
         {:ok, published?} <- maybe_publish(published?, revision, authority, options) do
      {:ok,
       %{
         template_id: id,
         status: status,
         call_spec_id: revision.call_spec_id,
         revision: revision.revision,
         published: published?,
         validation_errors: revision.validation_errors
       }}
    end
  end

  defp published?(repository, revision) do
    case Repositories.call(repository, :fetch_published_revision, [
           revision.tenant_key,
           revision.call_spec_id
         ]) do
      {:ok, %{revision: published}} -> {:ok, published == revision.revision}
      {:error, :call_spec_not_published} -> {:ok, false}
      {:error, _reason} = error -> error
    end
  end

  defp maybe_publish(false, revision, authority, options) do
    if Keyword.get(options, :publish, false) do
      with {:ok, _published} <-
             CallSpecAuthoring.publish(
               authority,
               revision.tenant_key,
               revision.call_spec_id,
               revision.revision,
               options
             ),
           do: {:ok, true}
    else
      {:ok, false}
    end
  end

  defp maybe_publish(true, _revision, _authority, _options), do: {:ok, true}

  defp load_all(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, templates} ->
      case CallSpecTemplate.load(path) do
        {:ok, template} -> {:cont, {:ok, [template | templates]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, templates} -> {:ok, Enum.reverse(templates)}
      error -> error
    end
  end

  defp directory(options) do
    Keyword.get_lazy(options, :directory, fn ->
      :vxpipe_calls
      |> Application.get_env(__MODULE__, [])
      |> Keyword.fetch!(:directory)
    end)
  end
end
