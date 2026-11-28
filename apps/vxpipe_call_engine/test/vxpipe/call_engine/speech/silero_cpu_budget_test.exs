defmodule Vxpipe.CallEngine.Speech.Silero.CPUBudgetTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Silero.CPUBudget

  defp resolve(files, overrides \\ []) do
    CPUBudget.detect(
      Keyword.merge(
        [
          linux?: true,
          read: &Map.fetch(files, &1),
          logical_processors: 8,
          dirty_schedulers: 6
        ],
        overrides
      )
    )
  end

  test "minimum uses the ancestor's actual bandwidth and a noncontiguous affinity mask" do
    files = %{
      "/proc/self/status" => "Name:\tbeam\nCpus_allowed_list:\t1,3-5\n",
      "/proc/self/cgroup" => "0::/docker/root/app",
      "/proc/self/mountinfo" => "35 20 0:29 /docker /sys/cg rw - cgroup2 cgroup rw",
      "/sys/cg/root/app/cpu.max" => "max 100000",
      "/sys/cg/root/cpu.max" => "25000 10000",
      "/sys/cg/cpu.max" => "300000 100000"
    }

    assert %{workers: 2, affinity: 4, quota: 2.5, limiting: [:quota]} = resolve(files)
  end

  test "reads a v1 CPU controller with escaped mount point and namespace-relative membership" do
    files = %{
      "/proc/self/cgroup" => "9:memory:/\n4:cpu,cpuacct:/nested",
      "/proc/self/mountinfo" =>
        "1 2 0:1 /host /memory rw - cgroup cgroup rw,memory\n" <>
          "2 1 0:2 /host /cpu\\040group rw - cgroup cgroup rw,cpu,cpuacct",
      "/cpu group/nested/cgroup.procs" => :os.getpid() |> to_string(),
      "/cpu group/nested/cpu.cfs_period_us" => "100000",
      "/cpu group/nested/cpu.cfs_quota_us" => "25000",
      "/cpu group/cpu.cfs_quota_us" => "90000",
      "/cpu group/cpu.cfs_period_us" => "100000"
    }

    assert %{workers: 1, quota: 0.25} = resolve(files)
  end

  test "ignores a bind mount for another cgroup" do
    files = %{
      "/proc/self/cgroup" => "0::/jobs/current",
      "/proc/self/mountinfo" =>
        "1 2 0:1 / /cg rw - cgroup2 cgroup rw\n" <>
          "2 1 0:1 /jobs/other /other rw - cgroup2 cgroup rw",
      "/cg/jobs/current/cpu.max" => "400000 100000",
      "/other/cpu.max" => "50000 100000"
    }

    assert %{workers: 4} = resolve(files)
  end

  test "dirty schedulers cap the available CPUs and bad inputs do not erase valid limits" do
    files = %{"/proc/self/status" => "Cpus_allowed_list: 0-1,8-9"}
    assert %{workers: 1, limiting: [:dirty_schedulers]} = resolve(files, dirty_schedulers: 1)
    assert %{workers: 4, limiting: [:affinity]} = resolve(files)
    assert %{workers: 3} = resolve(%{}, linux?: false, logical_processors: 3)

    assert %{workers: 1} =
             resolve(%{"/proc/self/status" => "Cpus_allowed_list: 3-1"},
               logical_processors: :unknown
             )
  end
end
