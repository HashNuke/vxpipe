defmodule Vxpipe.Console.CallUsageComponents do
  @moduledoc false

  use Phoenix.Component

  alias Vxpipe.Console.CallUsageFormat

  attr(:report, Vxpipe.Calls.UsageReport, default: nil)
  attr(:status, :atom, required: true)

  def panel(assigns) do
    ~H"""
    <section class="usage-bay" data-state={@status} aria-labelledby="usage-bay-heading">
      <header class="usage-bay-heading">
        <div>
          <h3 id="usage-bay-heading">Usage &amp; cost</h3>
          <p>Effective provider work with non-overlapping totals.</p>
        </div>
        <span>{summary(@report, @status)}</span>
      </header>

      <div :if={@status == :unavailable} class="usage-notice" role="status">
        <strong>Usage evidence unavailable</strong>
        <span>The call evidence remains available. Reload after usage storage recovers.</span>
      </div>

      <div :if={empty?(@report, @status)} class="usage-notice" role="status">
        <strong>No usage observations projected</strong>
        <span>This call has no persisted provider measurements or operation evidence yet.</span>
      </div>

      <div :if={pending_aggregate?(@report, @status)} class="usage-notice" role="status">
        <strong>No non-overlapping total yet</strong>
        <span>Included components are available while their aggregate remains in transit.</span>
      </div>

      <div
        :if={totals?(@report, @status)}
        class="usage-table-scroll"
        role="region"
        tabindex="0"
        aria-label="Non-overlapping usage totals"
      >
        <table class="usage-table usage-total-table">
          <caption class="sr-only">Non-overlapping call usage totals</caption>
          <thead>
            <tr>
              <th>Capability</th>
              <th>Provider</th>
              <th>Attribution</th>
              <th>Quantity</th>
              <th>Provenance</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={total <- @report.totals}>
              <td>{CallUsageFormat.capability(total.capability)}</td>
              <td title={CallUsageFormat.provider(total)}>{CallUsageFormat.provider(total)}</td>
              <td title={CallUsageFormat.attribution(total)}>
                {CallUsageFormat.attribution(total)}
              </td>
              <td class="usage-quantity">{CallUsageFormat.quantity(total)}</td>
              <td>{CallUsageFormat.provenance(total.provenance)}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <details :if={amounts?(@report, @status)} class="usage-evidence">
        <summary>{length(@report.amounts)} effective operations</summary>
        <div
          class="usage-table-scroll"
          role="region"
          tabindex="0"
          aria-label="Effective usage operation evidence"
        >
          <table class="usage-table usage-operation-table">
            <caption class="sr-only">Effective usage operation evidence</caption>
            <thead>
              <tr>
                <th>Attempt</th>
                <th>Capability / component</th>
                <th>Provider / external reference</th>
                <th>Attribution</th>
                <th>Quantity</th>
                <th>Settlement</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={amount <- @report.amounts}>
                <td title={amount.attempt_id}>{amount.attempt_id}</td>
                <td>
                  <strong>{CallUsageFormat.capability(amount.capability)}</strong>
                  <span title={CallUsageFormat.component(amount)}>
                    {CallUsageFormat.component(amount)}
                  </span>
                </td>
                <td>
                  <strong title={CallUsageFormat.provider(amount.provider)}>
                    {CallUsageFormat.provider(amount.provider)}
                  </strong>
                  <span title={CallUsageFormat.provider_references(amount.provider)}>
                    {CallUsageFormat.provider_references(amount.provider)}
                  </span>
                </td>
                <td title={CallUsageFormat.attribution(amount.attribution)}>
                  {CallUsageFormat.attribution(amount.attribution)}
                </td>
                <td class="usage-quantity">{CallUsageFormat.quantity(amount)}</td>
                <td>{CallUsageFormat.settlement(amount)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
    </section>
    """
  end

  defp summary(_report, :unavailable), do: "Unavailable"
  defp summary(nil, _status), do: "Unavailable"

  defp summary(report, :available) do
    total_label = count_label(length(report.totals), "non-overlapping total")
    amount_label = count_label(length(report.amounts), "effective operation")
    total_label <> " · " <> amount_label
  end

  defp count_label(1, label), do: "1 " <> label
  defp count_label(count, label), do: Integer.to_string(count) <> " " <> label <> "s"

  defp empty?(%{amounts: []}, :available), do: true
  defp empty?(_report, _status), do: false

  defp pending_aggregate?(%{amounts: [_first | _rest], totals: []}, :available), do: true
  defp pending_aggregate?(_report, _status), do: false

  defp totals?(%{totals: [_first | _rest]}, :available), do: true
  defp totals?(_report, _status), do: false

  defp amounts?(%{amounts: [_first | _rest]}, :available), do: true
  defp amounts?(_report, _status), do: false
end
