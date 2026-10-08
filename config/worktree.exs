# Evaluated only from development/test runtime configuration. Keep this reader
# dependency-free so direct root and child Mix invocations share the same defaults.
root = Path.expand("..", __DIR__)
path = Path.join(root, ".vxpipe/worktree.json")

case File.read(path) do
  {:error, :enoent} ->
    nil

  {:ok, contents} ->
    try do
      %{"version" => 1, "id" => id, "root" => ^root, "databases" => databases} =
        metadata = JSON.decode!(contents)

      true = is_binary(id) and Regex.match?(~r/\A[a-f0-9]{32}\z/, id)
      true = databases == %{"dev" => "vxpipe_#{id}_dev", "test" => "vxpipe_#{id}_test"}
      ports = Map.get(metadata, "ports")

      if ports do
        true = is_map(ports) and Enum.sort(Map.keys(ports)) == ~w(astro console storybook)
        values = Map.values(ports)
        true = Enum.all?(values, &(is_integer(&1) and &1 in 1024..65_535 and &1 != 4600))
        true = length(Enum.uniq(values)) == 3
      end

      Map.take(metadata, ~w(id databases ports))
    rescue
      _invalid ->
        raise "invalid, unsupported or copied worktree metadata; recover .vxpipe/worktree.json before running bin/setup"
    end

  {:error, _reason} ->
    raise "cannot read worktree metadata at .vxpipe/worktree.json"
end
