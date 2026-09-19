defmodule Vxpipe.Persistence.OperatorKeyFile do
  @moduledoc false
  alias Vxpipe.Calls

  def issue(mode, path, options \\ []) when mode in [:bootstrap, :replace] do
    case File.open(path, [:write, :exclusive, :binary]) do
      {:ok, file} ->
        result =
          try do
            with :ok <- File.chmod(path, 0o600),
                 {:ok, issued} <- issue_key(mode, options) do
              write_key(file, issued, options)
            end
          after
            File.close(file)
          end

        case result do
          {:ok, _metadata} ->
            result

          {:error, _reason} ->
            File.rm(path)
            result
        end

      {:error, _reason} ->
        {:error, :operator_key_output_unavailable}
    end
  end

  defp issue_key(:bootstrap, options), do: Calls.bootstrap_operator_api_key(options)
  defp issue_key(:replace, options), do: Calls.replace_operator_api_key(options)

  defp write_key(file, issued, options) do
    contents = JSON.encode!(%{api_key_id: issued.id, api_key: issued.secret}) <> "\n"
    write = Keyword.get(options, :write, &IO.binwrite/2)

    with :ok <- write_output(write, file, contents) do
      {:ok, %{api_key_id: issued.id, written: true}}
    else
      {:error, _reason} ->
        _ = Calls.revoke_operator_api_key(issued.id, options)
        {:error, :operator_key_output_failed}
    end
  end

  defp write_output(write, file, contents) do
    with :ok <- write.(file, contents), do: :file.sync(file)
  rescue
    _error -> {:error, :output_failed}
  catch
    _kind, _reason -> {:error, :output_failed}
  end
end
