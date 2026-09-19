defmodule Vxpipe.Persistence.OperatorKeyCLI do
  @moduledoc false
  alias Vxpipe.Persistence.{CLI, OperatorKeyFile}

  def issue(mode, arguments) do
    path = argument!(arguments, :output)
    CLI.ensure_ready!()

    case OperatorKeyFile.issue(mode, path) do
      {:ok, metadata} ->
        CLI.output!(metadata)

      {:error, :operator_key_output_failed} ->
        Mix.raise(
          "operator key output failed; use explicit replacement with a new protected output file"
        )

      {:error, reason} ->
        CLI.unwrap!({:error, reason})
    end
  end

  def argument!(arguments, key) do
    flag = "--" <> String.replace(Atom.to_string(key), "_", "-")

    arguments =
      case arguments do
        [^flag, value] -> [flag <> "=" <> value]
        other -> other
      end

    case OptionParser.parse(arguments, strict: [{key, :string}]) do
      {[{^key, value}], [], []} when is_binary(value) and byte_size(value) > 0 ->
        value

      _invalid ->
        Mix.raise("supply exactly one #{flag} argument; secret arguments are not accepted")
    end
  end
end
