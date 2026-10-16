defmodule Vxpipe.Calls.CallSpecTemplates do
  @moduledoc """
  The local call spec template library and its tenant installer.

  Templates live one per directory under the configured library directory. An
  installation renders a template with caller-supplied inputs, validates the result
  against the tenant and stores it through ordinary authoring.
  """

  alias Vxpipe.Calls.{CallSpecAuthoring, CallSpecAuthorization, CallSpecTemplate}

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
  Renders, validates and saves a template as a new call spec in the tenant. Every
  install creates a separate spec, even for identical inputs. A rendering that fails
  the tenant's save-time checks is rejected without being stored. Pass `publish: true`
  to publish the new revision.
  """
  @spec install(term(), String.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def install(authority, tenant_key, id, inputs, options \\ []) do
    # A supplied ID would append a revision to that spec instead of creating one.
    options = Keyword.delete(options, :call_spec_id)

    with :ok <- CallSpecAuthorization.authorize(authority, :write, tenant_key),
         {:ok, source} <- render(id, inputs, options),
         {:ok, []} <- CallSpecAuthoring.validate(authority, tenant_key, source, options),
         {:ok, draft} <- CallSpecAuthoring.save(authority, tenant_key, source, options),
         {:ok, published?} <- maybe_publish(draft, authority, options) do
      {:ok,
       %{
         template_id: id,
         call_spec_id: draft.call_spec_id,
         revision: draft.revision,
         published: published?
       }}
    else
      {:ok, errors} when is_list(errors) -> {:error, {:call_spec_template_invalid, errors}}
      {:error, _reason} = error -> error
    end
  end

  defp maybe_publish(draft, authority, options) do
    if Keyword.get(options, :publish, false) do
      with {:ok, _published} <-
             CallSpecAuthoring.publish(
               authority,
               draft.tenant_key,
               draft.call_spec_id,
               draft.revision,
               options
             ),
           do: {:ok, true}
    else
      {:ok, false}
    end
  end

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
