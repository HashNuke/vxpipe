defmodule Vxpipe.CallEngine.Speech.Silero.CPUBudget do
  @moduledoc "Resolves the node's CPU budget for operational Silero workers at pool startup."

  def detect(opts \\ []) do
    read = Keyword.get(opts, :read, &File.read/1)
    linux? = Keyword.get(opts, :linux?, :os.type() == {:unix, :linux})
    affinity = if linux?, do: affinity(read)
    quota = if linux?, do: quota(read)
    logical = count(opts, :logical_processors, :logical_processors_available)

    online =
      unless linux? or not is_nil(logical),
        do: count(opts, :online_processors, :logical_processors_online)

    dirty = count(opts, :dirty_schedulers, :dirty_cpu_schedulers_online)

    availability =
      cond do
        affinity -> [affinity: affinity]
        logical -> [logical_processors: logical]
        online -> [online_processors: online]
        is_number(quota) -> []
        true -> [fallback: 1]
      end

    limits =
      (availability ++ [quota: quota, dirty_schedulers: dirty])
      |> Enum.filter(fn {_, value} -> is_number(value) end)

    minimum = limits |> Keyword.values() |> Enum.min()

    %{
      workers: max(1, floor(minimum)),
      limiting: for({name, value} <- limits, value == minimum, do: name),
      affinity: affinity,
      logical_processors: logical,
      online_processors: online,
      quota: quota,
      dirty_schedulers: dirty
    }
  end

  defp count(opts, key, info) do
    case Keyword.get_lazy(opts, key, fn -> :erlang.system_info(info) end) do
      n when is_integer(n) and n > 0 -> n
      _ -> nil
    end
  end

  defp contents(read, path) do
    case read.(path) do
      {:ok, text} -> String.trim(text)
      _ -> ""
    end
  end

  defp affinity(read) do
    case Regex.run(
           ~r/^Cpus_allowed_list:[ \t]*([0-9,-]+)[ \t]*$/m,
           contents(read, "/proc/self/status")
         ) do
      [_, list] -> count_ranges(String.split(list, ","), -1, 0)
      _ -> nil
    end
  end

  # The kernel emits ordered, nonoverlapping ranges.
  defp count_ranges([], _, total), do: total

  defp count_ranges([range | rest], previous, total) do
    case String.split(range, "-") |> Enum.map(&Integer.parse/1) do
      [{n, ""}] when n > previous ->
        count_ranges(rest, n, total + 1)

      [{a, ""}, {b, ""}] when a > previous and b >= a ->
        count_ranges(rest, b, total + b - a + 1)

      _ ->
        nil
    end
  end

  defp quota(read) do
    memberships =
      for line <- String.split(contents(read, "/proc/self/cgroup"), "\n"),
          [_, controllers, path] <- [String.split(line, ":", parts: 3)],
          do: {String.split(controllers, ","), path}

    values =
      for line <- String.split(contents(read, "/proc/self/mountinfo"), "\n"),
          [left, right] <- [String.split(line, " - ", parts: 2)],
          [_, _, _, root, mount | _] <- [String.split(left)],
          [fs, _, options | _] <- [String.split(right)],
          {controllers, member} <- memberships,
          cpu_mount?(fs, options, controllers),
          visible <- ancestors(read, unescape(root), unescape(mount), member),
          do: bandwidth(read, fs, visible)

    finite = Enum.filter(values, &is_number/1)
    Enum.min(finite, fn -> if :unlimited in values, do: :unlimited end)
  end

  defp cpu_mount?("cgroup2", _, [""]), do: true

  defp cpu_mount?("cgroup", options, controllers),
    do: "cpu" in controllers and "cpu" in String.split(options, ",")

  defp cpu_mount?(_, _, _), do: false

  defp unescape(path) do
    Regex.replace(~r/\\(040|011|012|134)/, path, fn _, octal ->
      <<String.to_integer(octal, 8)>>
    end)
  end

  defp ancestors(read, root, mount, "/" <> _ = member) do
    root_parts = Path.split(root)
    member_parts = Path.split(member)
    direct? = List.starts_with?(member_parts, root_parts)
    parts = if direct?, do: Enum.drop(member_parts, length(root_parts)), else: tl(member_parts)

    cond do
      Enum.any?(parts, &(&1 in ["..", "."])) ->
        []

      direct? or member?(read, Path.join([mount | parts])) ->
        [mount | Enum.scan(parts, mount, &Path.join(&2, &1))]

      true ->
        []
    end
  end

  defp ancestors(_, _, _, _), do: []

  # A namespace-relative path may also fit an unrelated bind mount.
  defp member?(read, dir) do
    pid = List.to_string(:os.getpid())
    contents(read, Path.join(dir, "cgroup.procs")) |> String.split() |> Enum.member?(pid)
  end

  defp bandwidth(read, "cgroup2", dir) do
    case String.split(contents(read, Path.join(dir, "cpu.max"))) do
      [quota, period] -> fraction(quota, period)
      _ -> nil
    end
  end

  defp bandwidth(read, "cgroup", dir) do
    fraction(
      contents(read, Path.join(dir, "cpu.cfs_quota_us")),
      contents(read, Path.join(dir, "cpu.cfs_period_us"))
    )
  end

  defp fraction(quota, _) when quota in ["max", "-1"], do: :unlimited

  defp fraction(quota, period) do
    with {p, ""} when p > 0 <- Integer.parse(period) do
      case Integer.parse(quota) do
        {n, ""} when n > 0 -> n / p
        _ -> nil
      end
    else
      _ -> nil
    end
  end
end
