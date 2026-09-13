defmodule Vxpipe.CallEngine.Readiness.Barrier do
  @moduledoc """
  Tracks operational evidence for one prospective resource set.

  The lifecycle owner supplies the complete required set and owns preparing/removing its diff.
  Resource adapters supply reports; starting a child does not supply readiness. This module
  neither starts processes nor calls providers, so it can be used inside the room authority.
  """

  alias Vxpipe.CallEngine.Readiness.{Report, Resource}

  @enforce_keys [:incarnation_id, :attempt_id, :entries]
  defstruct @enforce_keys

  @type entry :: %{
          resource: Resource.t(),
          request_id: reference(),
          sequence: integer(),
          status: Report.status()
        }
  @type t :: %__MODULE__{
          incarnation_id: String.t(),
          attempt_id: term(),
          entries: %{Resource.key() => entry()}
        }
  @type diff :: %{prepare: [Resource.t()], remove: [Resource.t()], retain: [Resource.t()]}

  @spec new(String.t(), term(), [Resource.t()]) :: t()
  def new(incarnation_id, attempt_id, resources) when is_binary(incarnation_id) do
    entries = Map.new(index(resources), fn {key, resource} -> {key, entry(resource)} end)
    %__MODULE__{incarnation_id: incarnation_id, attempt_id: attempt_id, entries: entries}
  end

  @spec reconcile(t(), term(), [Resource.t()]) :: {t(), diff()}
  def reconcile(%__MODULE__{} = barrier, attempt_id, resources) do
    desired = index(resources)

    entries =
      Map.new(desired, fn {key, resource} ->
        entry = reconcile_entry(Map.get(barrier.entries, key), resource, barrier, attempt_id)
        {key, entry}
      end)

    retained =
      desired
      |> Enum.filter(fn {key, resource} ->
        match?(%{resource: ^resource}, Map.get(barrier.entries, key))
      end)
      |> Map.new()

    diff = %{
      prepare: desired |> Map.drop(Map.keys(retained)) |> Map.values() |> sort(),
      remove:
        barrier.entries
        |> Map.drop(Map.keys(retained))
        |> Enum.map(fn {_key, entry} -> entry.resource end)
        |> sort(),
      retain: retained |> Map.values() |> sort()
    }

    {%{barrier | attempt_id: attempt_id, entries: entries}, diff}
  end

  @spec request_id(t(), Resource.key()) :: reference()
  def request_id(%__MODULE__{} = barrier, key), do: Map.fetch!(barrier.entries, key).request_id

  @spec report(t(), Report.t()) :: {:accepted | :ignored, t()}
  def report(%__MODULE__{} = barrier, %Report{resource: %Resource{} = resource} = report) do
    key = Resource.key(resource)

    if valid_report?(barrier, Map.get(barrier.entries, key), report) do
      entries =
        Map.update!(
          barrier.entries,
          key,
          &%{&1 | status: report.status, sequence: report.sequence}
        )

      {:accepted, %{barrier | entries: entries}}
    else
      {:ignored, barrier}
    end
  end

  @spec status(t()) :: Report.status()
  def status(%__MODULE__{} = barrier) do
    statuses = Enum.map(barrier.entries, fn {_key, entry} -> entry.status end)

    cond do
      :failed in statuses -> :failed
      :preparing in statuses -> :preparing
      true -> :ready
    end
  end

  @spec blockers(t()) :: [map()]
  def blockers(%__MODULE__{} = barrier) do
    barrier.entries
    |> Enum.sort_by(fn {key, _entry} -> key end)
    |> Enum.reject(fn {_key, entry} -> entry.status == :ready end)
    |> Enum.map(fn {_key, entry} ->
      %{kind: entry.resource.kind, scope: entry.resource.scope, status: entry.status}
    end)
  end

  defp reconcile_entry(%{resource: resource} = current, resource, barrier, attempt_id) do
    if barrier.attempt_id == attempt_id do
      current
    else
      %{current | request_id: make_ref(), sequence: -1}
    end
  end

  defp reconcile_entry(_old, resource, _barrier, _attempt_id), do: entry(resource)

  defp entry(%Resource{} = resource) do
    status = if resource.adapter == nil, do: :failed, else: :preparing
    %{resource: resource, request_id: make_ref(), sequence: -1, status: status}
  end

  defp valid_report?(barrier, %{resource: resource, request_id: request_id} = entry, report) do
    report.incarnation_id == barrier.incarnation_id and
      report.attempt_id == barrier.attempt_id and report.request_id == request_id and
      report.resource == resource and Resource.bound?(resource) and entry.status != :failed and
      report.status in [:preparing, :ready, :failed] and
      is_integer(report.sequence) and report.sequence >= 0 and report.sequence > entry.sequence
  end

  defp valid_report?(_barrier, _missing, _report), do: false

  defp index(resources) do
    Enum.reduce(resources, %{}, fn %Resource{} = resource, indexed ->
      key = Resource.key(resource)

      if Map.has_key?(indexed, key) do
        raise ArgumentError, "duplicate readiness resource"
      else
        Map.put(indexed, key, resource)
      end
    end)
  end

  defp sort(resources), do: Enum.sort_by(resources, &Resource.key/1)
end
