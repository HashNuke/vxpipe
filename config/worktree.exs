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
        JSON.decode!(contents)

      true = is_binary(id) and Regex.match?(~r/\A[a-f0-9]{32}\z/, id)
      true = databases == %{"dev" => "vxpipe_#{id}_dev", "test" => "vxpipe_#{id}_test"}
      %{"id" => id, "databases" => databases}
    rescue
      _invalid ->
        raise "invalid, unsupported or copied worktree metadata; recover .vxpipe/worktree.json before running bin/setup"
    end

  {:error, _reason} ->
    raise "cannot read worktree metadata at .vxpipe/worktree.json"
end
