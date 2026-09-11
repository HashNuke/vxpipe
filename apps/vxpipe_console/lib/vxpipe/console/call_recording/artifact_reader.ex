defmodule Vxpipe.Console.CallRecording.ArtifactReader do
  @moduledoc false

  @behaviour Vxpipe.Console.CallRecording.Reader

  @derive {Inspect, except: [:object_reference, :options]}
  @enforce_keys [:object_reference, :object_reader, :options]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec new(map(), module(), keyword()) :: {:ok, {module(), t()}} | {:error, atom()}
  def new(object_reference, object_reader, options)
      when is_map(object_reference) and is_atom(object_reader) and is_list(options) do
    if Code.ensure_loaded?(object_reader) and function_exported?(object_reader, :read_range, 4) do
      context = %__MODULE__{
        object_reference: object_reference,
        object_reader: object_reader,
        options: options
      }

      {:ok, {__MODULE__, context}}
    else
      {:error, :invalid_recording_object_reader}
    end
  end

  def new(_object_reference, _object_reader, _options),
    do: {:error, :invalid_recording_object_reader}

  @impl true
  def read_range(%__MODULE__{} = context, first, last) do
    context.object_reader.read_range(
      context.object_reference,
      first,
      last,
      context.options
    )
  end
end
