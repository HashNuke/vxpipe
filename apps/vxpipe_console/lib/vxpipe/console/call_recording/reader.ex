defmodule Vxpipe.Console.CallRecording.Reader do
  @moduledoc false

  @callback read_range(term(), non_neg_integer(), non_neg_integer()) ::
              {:ok, binary()} | {:error, term()}

  @spec valid?(term()) :: boolean()
  def valid?({module, _context}) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :read_range, 3)
  end

  def valid?(_reader), do: false

  @spec read_range(term(), non_neg_integer(), non_neg_integer()) ::
          {:ok, binary()} | {:error, term()}
  def read_range({module, context} = reader, first, last)
      when is_integer(first) and is_integer(last) and first >= 0 and last >= first do
    if valid?(reader),
      do: module.read_range(context, first, last),
      else: {:error, :invalid_recording_reader}
  end

  def read_range(_reader, _first, _last), do: {:error, :invalid_recording_range}
end
