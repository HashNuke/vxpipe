defmodule Vxpipe.Persistence.MCP.RepositoryBoundary do
  @moduledoc "Maps known database outages while preserving unrelated programmer failures."

  def call(operation, unavailable) when is_function(operation, 0) and is_atom(unavailable) do
    operation.()
  rescue
    error -> repository_error(error, __STACKTRACE__, unavailable)
  catch
    :exit, {_reason, {DBConnection.Holder, :checkout, _arguments}} -> {:error, unavailable}
  end

  defp repository_error(%DBConnection.ConnectionError{}, _trace, unavailable),
    do: {:error, unavailable}

  defp repository_error(%Postgrex.Error{}, _trace, unavailable), do: {:error, unavailable}

  defp repository_error(%RuntimeError{}, [{Ecto.Repo.Registry, :lookup, _, _} | _], unavailable),
    do: {:error, unavailable}

  defp repository_error(
         %ArgumentError{},
         [
           {:ets, :lookup_element, [Ecto.Repo.Registry | _], _} | _
         ],
         unavailable
       ),
       do: {:error, unavailable}

  defp repository_error(error, trace, _unavailable), do: reraise(error, trace)
end
