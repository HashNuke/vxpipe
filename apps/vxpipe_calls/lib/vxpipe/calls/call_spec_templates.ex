defmodule Vxpipe.Calls.CallSpecTemplates do
  @moduledoc """
  The local call spec template library. Templates live one per directory under the
  configured library directory.
  """

  alias Vxpipe.Calls.CallSpecTemplate

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
