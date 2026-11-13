defmodule Vxpipe.Providers.Telnyx.CallCostDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.Measurement

  def decode(body) do
    case JSON.decode(body) do
      {:ok, %{"data" => %{"event_type" => "call.cost"} = data}} -> decode_event(data)
      _other -> :ignore
    end
  end

  defp decode_event(
         %{"record_type" => "event", "id" => id, "occurred_at" => at, "payload" => payload} = data
       )
       when is_map(payload) and is_binary(at) do
    with true <-
           Enum.all?(
             [id, payload["connection_id"], payload["call_leg_id"], payload["call_session_id"]],
             &identifier?/1
           ),
         {:ok, observed_at, _offset} <- DateTime.from_iso8601(at),
         {:ok, measurements} <- measurements(payload) do
      {:ok,
       %{
         id: id,
         application_id: payload["connection_id"],
         leg_id: payload["call_leg_id"],
         session_id: payload["call_session_id"],
         observed_at: observed_at,
         # A measurement-free receipt fences the complete delivery before component writes.
         measurements: [nil | measurements],
         fingerprint: digest(data)
       }}
    else
      _invalid -> {:error, :invalid_telnyx_webhook}
    end
  end

  defp decode_event(_invalid), do: {:error, :invalid_telnyx_webhook}

  defp measurements(%{"status" => "error"}), do: {:ok, []}

  defp measurements(%{"status" => "success", "cost_parts" => parts} = payload)
       when is_list(parts) and length(parts) <= 64 do
    total = payload["total_cost"]

    with {:ok, components} <- cost_parts(parts, if(is_nil(total), do: nil, else: "cost")),
         {:ok, totals} <- total_cost(total, components),
         {:ok, duration} <- duration(payload["billed_duration_secs"]) do
      {:ok, totals ++ duration ++ components}
    end
  end

  defp measurements(_invalid), do: {:error, :invalid_cost}

  defp cost_parts(parts, included_in) do
    Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
      case cost_part(part, included_in) do
        {:ok, measurement} ->
          if Enum.any?(acc, &(&1.component == measurement.component)),
            do: {:halt, {:error, :duplicate_cost_part}},
            else: {:cont, {:ok, acc ++ [measurement]}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp cost_part(%{"call_part" => name, "cost" => cost, "currency" => currency}, included_in)
       when is_binary(name) and byte_size(name) in 1..59 do
    if Regex.match?(~r/^[a-z][a-z0-9_-]*$/, name) do
      measurement(
        "cost_" <> String.replace(name, "-", "_"),
        {:currency, currency},
        cost,
        included_in
      )
    else
      {:error, :invalid_cost_part}
    end
  end

  defp cost_part(_invalid, _included_in), do: {:error, :invalid_cost_part}

  defp total_cost(nil, _parts), do: {:ok, []}

  defp total_cost(total, parts) do
    case parts |> Enum.map(& &1.unit) |> Enum.uniq() do
      [{:currency, _currency} = unit] -> single_measurement("cost", unit, total)
      _ambiguous -> {:error, :unknown_total_currency}
    end
  end

  defp duration(nil), do: {:ok, []}

  defp duration(seconds) when is_integer(seconds) and seconds >= 0,
    do: single_measurement("billed_duration", :milliseconds, seconds * 1000)

  defp duration(_invalid), do: {:error, :invalid_duration}

  defp single_measurement(component, unit, quantity) do
    with {:ok, measurement} <- measurement(component, unit, quantity, nil),
         do: {:ok, [measurement]}
  end

  defp measurement(component, unit, quantity, included_in) do
    Measurement.new(
      component: component,
      unit: unit,
      quantity: quantity,
      included_in: included_in,
      mode: :cumulative,
      status: :final,
      provenance: :provider_reported
    )
  end

  defp identifier?(value),
    do: is_binary(value) and byte_size(value) in 1..128 and String.trim(value) != ""

  defp digest(data),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(data, [:deterministic]))
      |> Base.encode16(case: :lower)
end
