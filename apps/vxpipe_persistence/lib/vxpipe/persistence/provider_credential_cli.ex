defmodule Vxpipe.Persistence.ProviderCredentialCLI do
  @moduledoc false

  def options!(arguments, mode) do
    switches =
      if mode == :provision,
        do: [tenant: :string, provider: :string, name: :string, auth_kind: :string],
        else: [tenant: :string]

    required = if mode == :provision, do: [:tenant, :provider], else: [:tenant]

    arguments = normalize_arguments(arguments, switches)

    case OptionParser.parse(arguments, strict: switches) do
      {options, [], []} ->
        if Enum.all?(required, &(Keyword.get(options, &1) not in [nil, ""])),
          do: options,
          else: Mix.raise("missing required provider credential arguments")

      _invalid ->
        Mix.raise("invalid provider credential arguments; supply the payload through stdin")
    end
  end

  def payload! do
    require_protected_stdin!()

    # IO.read counts code points on Unicode devices; also enforce the byte limit.
    with input when is_binary(input) and byte_size(input) <= 16_384 <-
           IO.read(:stdio, 16_385),
         {:ok, value} when is_map(value) <- JSON.decode(input) do
      value
    else
      _invalid ->
        Mix.raise("provider credential stdin must contain a JSON object of at most 16384 bytes")
    end
  end

  defp require_protected_stdin! do
    # Elixir.IO has no terminal-query wrapper. `stdin` describes the input stream;
    # OTP's `terminal` option describes stdout and would reject a pipe into a TTY.
    case :io.getopts(:standard_io) do
      options when is_list(options) ->
        if Keyword.get(options, :stdin, false),
          do: Mix.raise("provider credentials require protected stdin; redirect a file or pipe")

      _unavailable ->
        Mix.raise("could not verify protected stdin for provider credentials")
    end
  end

  defp normalize_arguments(arguments, switches) do
    names =
      Map.new(switches, fn {key, :string} ->
        {"--" <> String.replace(Atom.to_string(key), "_", "-"), true}
      end)

    normalize_values(arguments, names)
  end

  defp normalize_values([option, value | rest], names) when is_map_key(names, option),
    do: [option <> "=" <> value | normalize_values(rest, names)]

  defp normalize_values([argument | rest], names),
    do: [argument | normalize_values(rest, names)]

  defp normalize_values([], _names), do: []

  def summary(credential) do
    %{
      "credential_id" => credential.id,
      "tenant_key" => credential.tenant_key,
      "provider" => credential.provider,
      "name" => credential.name,
      "auth_kind" => credential.auth_kind,
      "version" => credential.version,
      "status" => Atom.to_string(credential.status),
      "payload_schema_version" => credential.payload_schema_version,
      "encryption_key_id" => credential.encryption_key_id,
      "inserted_at" => DateTime.to_iso8601(credential.inserted_at),
      "updated_at" => DateTime.to_iso8601(credential.updated_at)
    }
  end
end
